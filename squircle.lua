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
