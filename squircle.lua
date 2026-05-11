-- squircle
-- v0.1.0 @icco
--
-- dual midi channel sequencer
-- four free-running arc rings
--
-- arc1 / arc3 enc: pitch phasor speed (v1 / v2)
-- arc2 / arc4 enc: rhythm phasor speed (v1 / v2)
-- arc key:        freeze (zero all speeds)
--
-- enc1: root note      enc2: scale       enc3: pitch-lane length
-- key2: regen pitch lanes
-- key3: regen rhythm patterns (long: panic)

local musicutil = require("musicutil")
local er = require("er")

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

local TICK_HZ = 60 -- arc redraw + sequencer tick rate
local RING_LEDS = 64 -- LEDs per arc ring
local PHASE_MAX = 1024 -- snows-style fixed-point phase per ring
local SPEED_CLAMP = 32 -- max |speed| per ring (per-tick phase delta)

local NUM_VOICES = 2
local NUM_RINGS = 4

-- Per-voice mapping: voice v owns rings (v*2 - 1) and (v*2)
-- ring 1 = pitch (v1), ring 2 = rhythm (v1), ring 3 = pitch (v2), ring 4 = rhythm (v2)
local PITCH_RING = { 1, 3 }
local RHYTHM_RING = { 2, 4 }

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

local rings = {} -- [1..4] = { speed = 0, phase = 0 }
for i = 1, NUM_RINGS do
  rings[i] = { speed = 0, phase = 0 }
end

local voices = {} -- [1..2] = { ch, pitch_lane, pitch_idx, rhythm, gate_idx, gate_high, last_note }
for v = 1, NUM_VOICES do
  voices[v] = {
    ch = v,
    pitch_lane = {},
    pitch_idx = 1,
    rhythm = {},
    gate_idx = 0,
    gate_high = false,
    last_note = nil,
  }
end

local a -- arc.connect()
local m -- midi.connect(target) -- the currently selected midi out device
local dirty = true -- arc needs a redraw
local screen_dirty = true -- norns screen needs a redraw

-- ---------------------------------------------------------------------------
-- MIDI devices
-- ---------------------------------------------------------------------------

local midi_devices = {}
local midi_device_names = {}

local function rebuild_midi_devices()
  midi_devices = {}
  midi_device_names = {}
  for i = 1, #midi.vports do
    midi_devices[i] = midi.connect(i)
    local name = midi_devices[i].name or ("port " .. i)
    midi_device_names[i] = i .. ": " .. util.trim_string_to_width(name, 80)
  end
end

-- Re-point `m` at the currently selected device. Called from the
-- "midi_target" param action and on hot-plug.
local function refresh_midi_target()
  local target = params:get("midi_target")
  m = midi_devices[target]
end

-- Send all-notes-off (CC 123) on every channel we use. Defensive against a
-- stuck note when changing devices, panicking, or cleaning up.
local function panic()
  if m == nil then
    return
  end
  for v = 1, NUM_VOICES do
    local ch = params:get("v" .. v .. "_ch")
    m:cc(123, 0, ch)
    voices[v].last_note = nil
    voices[v].gate_high = false
  end
end

-- ---------------------------------------------------------------------------
-- Params
-- ---------------------------------------------------------------------------

-- Forward declarations: setup_params wires set_action callbacks that invoke
-- these regen helpers. Their bodies live further down.
local regen_pitch_lane
local regen_pitch_lanes
local regen_rhythm
local regen_rhythms

-- musicutil.SCALES is an array of { name = "Major", intervals = {...} }.
-- Build a parallel name list for the scale option param.
local scale_names = {}
for i, s in ipairs(musicutil.SCALES) do
  scale_names[i] = s.name
end

-- Find the default scale by name (fall back to 1 = Major if missing).
local function scale_index(name)
  for i, s in ipairs(musicutil.SCALES) do
    if s.name == name then
      return i
    end
  end
  return 1
end

local function setup_params()
  rebuild_midi_devices()

  params:add_separator("squircle_sep", "SQUIRCLE")

  params:add_option("midi_target", "midi out", midi_device_names, 1)
  params:set_action("midi_target", function()
    refresh_midi_target()
    panic()
  end)

  params:add_group("voices", 6)
  params:add_number("v1_ch", "voice 1 channel", 1, 16, 1)
  params:add_number("v2_ch", "voice 2 channel", 1, 16, 2)
  params:add_number("velocity", "velocity", 1, 127, 100)
  params:add_option("root", "root", musicutil.NOTE_NAMES, 1) -- C
  params:set_action("root", function()
    regen_pitch_lanes()
  end)
  params:add_option("scale", "scale", scale_names, scale_index("Natural Minor"))
  params:set_action("scale", function()
    regen_pitch_lanes()
  end)
  params:add_number("lane_len", "pitch lane length", 3, 12, 5)
  params:set_action("lane_len", function()
    regen_pitch_lanes()
  end)

  params:add_group("rhythm", 4)
  params:add_number("v1_steps", "v1 rhythm steps", 4, 32, 16)
  params:set_action("v1_steps", function(v)
    if params:get("v1_pulses") > v then
      params:set("v1_pulses", v)
    end
    regen_rhythm(1)
  end)
  params:add_number("v1_pulses", "v1 rhythm pulses", 1, 32, 5)
  params:set_action("v1_pulses", function()
    regen_rhythm(1)
  end)
  params:add_number("v2_steps", "v2 rhythm steps", 4, 32, 16)
  params:set_action("v2_steps", function(v)
    if params:get("v2_pulses") > v then
      params:set("v2_pulses", v)
    end
    regen_rhythm(2)
  end)
  params:add_number("v2_pulses", "v2 rhythm pulses", 1, 32, 7)
  params:set_action("v2_pulses", function()
    regen_rhythm(2)
  end)

  params:bang()
end

-- ---------------------------------------------------------------------------
-- Pattern generation
-- ---------------------------------------------------------------------------

-- Per-voice base MIDI note. Voice 1 sits around middle C (octave 4),
-- voice 2 an octave below so the two lanes occupy distinct registers
-- when feeding a single sound source (e.g. 98-duo-midi mono mode).
local VOICE_BASE = { 60, 48 }

-- Build voice v's pitch lane: lane_len notes starting from root in the
-- current scale, anchored to that voice's base octave. Snapped to scale
-- by construction.
function regen_pitch_lane(v)
  local root = (params:get("root") - 1) + VOICE_BASE[v]
  local scale_name = scale_names[params:get("scale")]
  local len = params:get("lane_len")
  voices[v].pitch_lane = musicutil.generate_scale_of_length(root, scale_name, len)
  if voices[v].pitch_idx > #voices[v].pitch_lane then
    voices[v].pitch_idx = 1
  end
  dirty = true
  screen_dirty = true
end

function regen_pitch_lanes()
  for v = 1, NUM_VOICES do
    regen_pitch_lane(v)
  end
end

-- Build voice v's rhythm pattern via Euclidean distribution. Resulting
-- table is length steps with boolean gates; gate_idx wraps to the new
-- length so a step shrink doesn't dangle.
function regen_rhythm(v)
  local steps = params:get("v" .. v .. "_steps")
  local pulses = params:get("v" .. v .. "_pulses")
  voices[v].rhythm = er.gen(pulses, steps)
  if #voices[v].rhythm > 0 then
    voices[v].gate_idx = voices[v].gate_idx % #voices[v].rhythm
  else
    voices[v].gate_idx = 0
  end
  dirty = true
  screen_dirty = true
end

function regen_rhythms()
  for v = 1, NUM_VOICES do
    regen_rhythm(v)
  end
end
