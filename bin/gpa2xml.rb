#!/usr/bin/env ruby

# Takes a Go PlayAlong XML file with synchronization data and Guitar Pro tab
# and produces Rocksmith 2014 XML tracks.

# Metadata comes from the guitar pro tablature
# Copyright => Year
# AlbumArt =>
# Tones => Note.text defines tone name and tone change

require 'rexml/document'
require 'interpolator'
require 'guitar_pro_parser'
require 'gyoku'
require 'matrix'

# To be removed since it already exists in master for guitar_pro_parser
def GuitarProHelper.note_to_digit(note)
  result = 0
  result += 1 until GuitarProHelper.digit_to_note(result) == note
  result
end

## HELPERS

I_DURATIONS = GuitarProHelper::DURATIONS.invert

STANDARD_TUNING = %w(E3 A3 D4 G4 B4 E5).map do |n|
  GuitarProHelper.note_to_digit(n)
end

def sortable_name(n)
  n.sub(/^(the|a|an)\s+/i, '').capitalize
end

# Counted arrays
def carray(symbol, arr)
  {
    :@count => arr.count,
    :content! => { symbol => arr }
  }
end

def compute_tuning(gp_tuning)
  t = gp_tuning.reverse.map { |n| GuitarProHelper.note_to_digit(n) }
  x = Vector.elements(t) - Vector.elements(STANDARD_TUNING)

  {
    :@string0 => x[0], :@string1 => x[1], :@string2 => x[2],
    :@string3 => x[3], :@string4 => x[4], :@string5 => x[5]
  }
end

## OVERVIEW

# Build notes and chords
# anchors
# handshapes
# chord templates
# fingering
# arrangement properties

# TODO
# cent offset is missing from GP
# compute internalName, sort names
# ToneA, ..., D

class SngXmlBuilder
  def initialize(gp_song, track, sync_data)
    @gp_song = gp_song
    @track = track
    @timerinter = sync_data

    @internal_name = @gp_song.artist.gsub(/[^0-9a-z]/i, '') + '_'
    @internal_name += @gp_song.title.gsub(/[^0-9a-z]/i, '')

    @notes = []
    @chords = []
    @ebeats = []
    @sections = []
    @tone_map = ['ToneBase']
    @tones = []

    @phrases = [
      {
        :@disparity => 0,
        :@name => '',
        :@ignore => 0,
        :@maxDifficulty => 0,
        :@solo => 0
      }
    ]

    @phrase_iterations = [
      {
        :@time => 10.000,
        :@phraseId => 0,
        :@variation => ''
      }
    ]

    @new_linked_diffs = []
    # {
    #   :@levelBreak => -1,
    #   :@ratio => 1.0,
    #   :@phraseCount => 1,
    #   :nld__phrase => [ { :@id => 1} ]
    # }]

    @linked_diffs = []
    #   {
    #     :@childId => 1,
    #     :@parentId => 1
    #   }
    # ]

    @chord_templates = [
      {
        :@chordName => '',
        :@displayName => 'g5p5',
        :@finger0 => -1,
        :@finger1 => -1,
        :@finger2 => -1,
        :@finger3 => -1,
        :@finger4 => 1,
        :@finger5 => 1,
        :@fret0 => -1,
        :@fret1 => -1,
        :@fret2 => -1,
        :@fret3 => -1,
        :@fret4 => 5,
        :@fret5 => 5
      }
    ]

    @events = [
      {
        :@time => 10.0,
        :@code => 'B0'
      }
    ]

    @fret_hand_mutes = []

    @anchors = [
      {
        :@time => 275.931,
        :@fret => 13,
        :@width => 4.000
      }
    ]

    @hand_shapes = [
      {
        :@chordId => 0,
        :@endTime => 5.728,
        :@startTime => 5.672
      }
    ]
  end

  def buildXML
    {
      :@version      => 8,
      :title         => @gp_song.title,
      :arrangement   => @track.name,
      :wavefilepath  => '',
      :part          => 1,
      :offset        => -10.000,
      :centOffset    => 0,
      :songLength    => 0.000,
      :internalName  => @internal_name,
      :songNameSort  => sortable_name(@gp_song.title),
      :startBeat     => 0.000,
      :averageTempo  => @gp_song.bpm,
      :tuning        => compute_tuning(@track.strings),
      :capo          => @track.capo,
      :artistName    => @gp_song.artist,
      :artistNameSort => sortable_name(@gp_song.artist),
      :albumName     => @gp_song.album,
      :albumNameSort => sortable_name(@gp_song.album),
      :albumYear     => @gp_song.copyright.to_i,
      :albumArt      => '', # TODO: default value based on name
      :crowdSpeed    => 1,
      :arrangementProperties => {
        :@represent         => 1,
        :@bonusArr          => 0,
        :@standardTuning    => 1,
        :@nonStandardChords => 0,
        :@barreChords       => 0,
        :@powerChords       => 0,
        :@dropDPower        => 0,
        :@openChords        => 0,
        :@fingerPicking     => 0,
        :@pickDirection     => 0,
        :@doubleStops       => 0,
        :@palmMutes         => 0,
        :@harmonics         => 0,
        :@pinchHarmonics    => 0,
        :@hopo              => 0,
        :@tremolo           => 0,
        :@slides            => 0,
        :@unpitchedSlides   => 0,
        :@bends             => 0,
        :@tapping           => 0,
        :@vibrato           => 0,
        :@fretHandMutes     => 0,
        :@slapPop           => 0,
        :@twoFingerPicking  => 0,
        :@fifthsAndOctaves  => 0,
        :@syncopation       => 0,
        :@bassPick          => 0,
        :@sustain           => 0,
        :@pathLead          => 1,
        :@pathRhythm        => 0,
        :@pathBass          => 0
      },
      :lastConversionDateTime => Time.now.strftime('%F %T'),

      :tone__Base => '', # TODO: default values
      :tone__A => @tone_map.count > 1 ? @tone_map[1] : '',
      :tone__B => @tone_map.count > 2 ? @tone_map[2] : '',
      :tone__C => @tone_map.count > 3 ? @tone_map[3] : '',
      :tone__D => @tone_map.count > 4 ? @tone_map[4] : '',
      :tone__Multiplayer => '',
      :tones => carray(:tone, @tones),

      :phrases => carray(:phrase, @phrases),

      :phraseIterations => carray(:phraseIteration, @phrase_iterations),

      :newLinkedDiffs => carray(:newLinkedDiff, @new_linked_diffs),

      :linkedDiffs => carray(:linkedDiff, @linked_diffs),

      :phraseProperties => [],

      :chordTemplates => carray(:chordTemplate, @chord_templates),

      :fretHandMuteTemplates => carray(:fretHandMuteTemplate, []),

      :ebeats => carray(:ebeat, @ebeats),

      :sections => carray(:section, @sections),

      :events => carray(:event, @events),

      :transcriptionTrack => { :@difficulty => -1 },

      :levels => carray(:level, [
        {
          :@difficulty => 0,
          :notes => carray(:note, @notes),
          :chords => carray(:chord, @chords),
          :fretHandMutes => carray(:fretHandMute, @fret_hand_mutes),
          :anchors => carray(:anchor, @anchors),
          :handShapes => carray(:handShape, @hand_shapes)
        }
      ])
    }
  end

  def create_note(time, string, note)
    bb = []
    if note.bend
      # TODO: skip first if step == 0 ?
      note.bend[:points].each do |b|
        bb << {
          :@time => b[:time],
          :@step => b[:pitch_alteration] / 100.0
        }
      end
    end

    if note.slide
    end

    if note.hammer_or_pull
    end

    if note.grace
    end

    # sustain
    # hammer / pull / hopo
    # slides

    n = {
      :@time => time,
      # :@linkNext => 0,
      :@accent => note.accentuated ? 1 : 0,
      :@bend => bb.count > 0 ? 1 : 0,
      :@fret => note.fret,
      # :@hammerOn => 0,
      :@harmonic => note.harmonic != :none ? 1 : 0, # note.harmonic != :pinch
      # :@hopo => 0,
      :@ignore => 0,
      :@leftHand => -1,
      :@mute => note.type == :dead ? 1 : 0,
      :@palmMute => note.palm_mute ? 1 : 0,
      :@pluck => -1,
      # :@pullOff => 0,
      :@slap => -1,
      # :@slideTo => -1,
      :@string => string,
      # :@sustain => 1.130,
      :@tremolo => note.tremolo ? 1 : 0,
      :@harmonicPinch => note.harmonic == :pinch ? 1 : 0,
      :@pickDirection => 0,
      :@rightHand => -1,
      # :@slideUnpitchTo => -1,
      :@tap => 0,
      :@vibrato => 0,
      :bendValues => carray(:bendValue, bb)
    }
    n
  end

  def create_chord(time, notes)
    # TODO: bendValues
    notes.each { |n| n.delete(:bendValues) }

    {
      :@time => time,
      # :@linkNext => 0,
      :@accent => (notes.any? { |n| n[:@accent] == 1 }) ? 1 : 0,
      # :@chordId => 12,
      # :@fretHandMute => 0,
      # :@highDensity => 0, # criterion needed here
      :@ignore => notes.any? { |n| n[:@ignore] == 1 } ? 1 : 0,
      :@palmMute => notes.all? { |n| n[:@palmMute] == 1 } ? 1 : 0,
      :@hopo => notes.any? { |n| n[:@hopo] == 1 } ? 1 : 0,
      # :@strum => "down", # in the beat actually
      :chordNote => notes
    }
  end

  def bar2time(barfraction)
    t = @timerinter.read(barfraction)
    (t * 1000).round / 1000.0
  end

  def build
    # current offset in tablature
    measure = 0.0

    @track.bars.zip(@gp_song.bars_settings).each do |bar, bar_settings|
      measure_fraction = 0.0

      if bar_settings.new_time_signature
        s = bar_settings.new_time_signature
        @signature = 4.0 * s[:numerator] / s[:denominator]
      end

      @ebeats << {
        :@time => bar2time(measure),
        :@measure => (measure + 1).to_i
      }
      1.upto(@signature - 1).each do |i|
        @ebeats << {
          :@time => bar2time(measure + i / @signature),
          :@measure => -1
        }
      end

      @sections << {
        :@name => bar_settings.marker[:name],
        :@number => @sections.count + 1,
        :@startTime => bar2time(measure)
      } if bar_settings.marker

      bar.voices[:lead].each do |beat|
        t = bar2time(measure + measure_fraction)

        nn = beat.strings.map do |string, note|
          string = @track.strings.count - string.to_i
          create_note(t, string, note)
        end

        if beat.text
          idx = @tone_map.index(beat.text)
          unless idx
            idx = @tone_map.count
            @tone_map << beat.text
          end

          @tones << {
            :@id => idx,
            :@time => t
          }
        end

        @notes << nn[0] if nn.count == 1
        @chords << create_chord(t, nn) if nn.count > 1

        measure_fraction += fraction_in_bar(beat.duration)
      end

      measure += 1.0
    end
  end

  def fraction_in_bar(d)
    1.0 / (2**Integer(I_DURATIONS[d])) / @signature
  end
end

def time_interpolator(sync_data)
  s = sync_data.split '#'
  s.shift

  t = s.map { |u| u.split ';' }

  m = t.map do |time, bar, bar_fraction, beat_duration|
    { bar.to_f + bar_fraction.to_f => time.to_f / 1000.0 }
  end

  Interpolator::Table.new m.reduce Hash.new, :merge
end

## SCRIPT

gpa_xml = REXML::Document.new File.new(ARGV[0], 'r')
score_url = gpa_xml.elements['track'].elements['scoreUrl'].text
# mp3_url = gpa_xml.elements['track'].elements['mp3Url'].text
sync_data = gpa_xml.elements['track'].elements['sync'].text

# TODO: if no sync data use bpm

tabsong = GuitarProParser.read_file(score_url)

tabsong.tracks[0, 1].each do |track|
  xml = SngXmlBuilder.new tabsong, track, time_interpolator(sync_data)
  xml.build

  puts Gyoku.xml :song => xml.buildXML
end
