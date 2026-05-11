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

-- ---------------------------------------------------------------------------
-- Arc input
-- ---------------------------------------------------------------------------

-- Each turn of an arc encoder accumulates into that ring's signed speed.
-- Speed is the per-tick phase delta; a positive value rolls the cursor
-- clockwise. Clamped so a single furious twist can't lock the device.
local function on_arc_delta(n, d)
  local r = rings[n]
  r.speed = util.clamp(r.speed + d, -SPEED_CLAMP, SPEED_CLAMP)
  dirty = true
  screen_dirty = true
end

-- The arc has a single button. Pressing it freezes the world: zero every
-- ring's speed (snows behavior). Phases stay where they are; release
-- alone won't restart motion -- the user has to spin again.
local function on_arc_key(n, z)
  if z == 1 then
    for i = 1, NUM_RINGS do
      rings[i].speed = 0
    end
    dirty = true
    screen_dirty = true
  end
end

-- Connect to the first arc and wire the callbacks. Safe to call once at
-- init; arc.add / arc.remove handle reconnects after that.
local function setup_arc()
  a = arc.connect()
  a.delta = on_arc_delta
  a.key = on_arc_key
end

-- ---------------------------------------------------------------------------
-- Sequencer tick
-- ---------------------------------------------------------------------------

-- Number of step slots crossed going from prev to cur on a circular axis
-- of `num` slots, in direction `dir` (+1 forward, -1 backward).
local function steps_between(prev, cur, num, dir)
  if dir > 0 then
    return (cur - prev) % num
  else
    return (prev - cur) % num
  end
end

-- Apply a gate transition for voice v: send note_on on a rising edge
-- (using the currently armed pitch from pitch_lane[pitch_idx]) and
-- note_off on a falling edge (using whatever note we last sent).
local function apply_gate(v, gate_on)
  local voice = voices[v]
  if gate_on and not voice.gate_high then
    local note = voice.pitch_lane[voice.pitch_idx]
    if note and m then
      local ch = params:get("v" .. v .. "_ch")
      local vel = params:get("velocity")
      m:note_on(note, vel, ch)
      voice.last_note = note
    end
    voice.gate_high = true
  elseif not gate_on and voice.gate_high then
    if voice.last_note and m then
      local ch = params:get("v" .. v .. "_ch")
      m:note_off(voice.last_note, 0, ch)
    end
    voice.last_note = nil
    voice.gate_high = false
  end
end

-- Advance voice v's pitch index for each slot crossed by its phasor.
local function handle_pitch_ring(v, prev_phase, cur_phase, dir)
  local lane = voices[v].pitch_lane
  if #lane == 0 then
    return
  end
  local slot_w = PHASE_MAX / #lane
  local prev_slot = math.floor(prev_phase / slot_w)
  local cur_slot = math.floor(cur_phase / slot_w)
  local crossings = steps_between(prev_slot, cur_slot, #lane, dir)
  for _ = 1, crossings do
    if dir > 0 then
      voices[v].pitch_idx = (voices[v].pitch_idx % #lane) + 1
    else
      voices[v].pitch_idx = ((voices[v].pitch_idx - 2) % #lane) + 1
    end
  end
end

-- Walk voice v's rhythm pattern step-by-step for each slot crossed.
-- Each new step is evaluated as a gate edge, so even a fast phasor that
-- traverses several steps in one tick fires balanced note_on/note_off
-- pairs in order.
local function handle_rhythm_ring(v, prev_phase, cur_phase, dir)
  local pat = voices[v].rhythm
  if #pat == 0 then
    return
  end
  local slot_w = PHASE_MAX / #pat
  local prev_slot = math.floor(prev_phase / slot_w)
  local cur_slot = math.floor(cur_phase / slot_w)
  local crossings = steps_between(prev_slot, cur_slot, #pat, dir)
  for _ = 1, crossings do
    if dir > 0 then
      voices[v].gate_idx = (voices[v].gate_idx % #pat) + 1
    else
      voices[v].gate_idx = ((voices[v].gate_idx - 2) % #pat) + 1
    end
    apply_gate(v, pat[voices[v].gate_idx])
  end
end

-- ---------------------------------------------------------------------------
-- Arc drawing
-- ---------------------------------------------------------------------------

-- Triple-LED interpolated cursor borrowed from snows.lua / ribbons. Maps a
-- phase value in [0, PHASE_MAX) onto the 64-LED ring with sub-LED
-- precision: the lit LED is bright, the next-leading LED carries the
-- fractional brightness, and the trailing LED carries the inverse. Reads
-- as a smooth dot of light moving around the ring.
local function point(ring, x)
  local xi = math.floor(x)
  local c = xi >> 4
  a:led(ring, c % 64 + 1, 15)
  a:led(ring, (c + 1) % 64 + 1, xi % 16)
  a:led(ring, (c + 63) % 64 + 1, 15 - (xi % 16))
end

-- LED index (1..64) for slot i (0-based) on a ring divided into nlen slots.
local function slot_led(i, nlen)
  return math.floor(i * RING_LEDS / nlen) + 1
end

-- Pitch ring: dim dot at every lane slot, brighter dot at the currently
-- armed slot, plus the moving cursor.
local function draw_pitch_ring(v)
  local n = PITCH_RING[v]
  local lane = voices[v].pitch_lane
  local nlen = #lane
  if nlen == 0 then
    return
  end
  for i = 0, nlen - 1 do
    local level = (i + 1 == voices[v].pitch_idx) and 12 or 3
    a:led(n, slot_led(i, nlen), level)
  end
  point(n, rings[n].phase)
end

-- Rhythm ring: dim dot at every step boundary, mid for active gates,
-- bright at the cursor's current step (extra bright when gate is high),
-- plus the moving cursor.
local function draw_rhythm_ring(v)
  local n = RHYTHM_RING[v]
  local pat = voices[v].rhythm
  local nlen = #pat
  if nlen == 0 then
    return
  end
  for i = 0, nlen - 1 do
    local active = pat[i + 1]
    local level
    if i + 1 == voices[v].gate_idx then
      level = voices[v].gate_high and 15 or 8
    elseif active then
      level = 6
    else
      level = 2
    end
    a:led(n, slot_led(i, nlen), level)
  end
  point(n, rings[n].phase)
end

-- Clear all rings and redraw them. Caller is responsible for the refresh.
local function draw_arc()
  if a == nil then
    return
  end
  a:all(0)
  for v = 1, NUM_VOICES do
    draw_pitch_ring(v)
    draw_rhythm_ring(v)
  end
end

-- One tick of the engine: advance every ring with non-zero speed, dispatch
-- to its pitch/rhythm handler, mark dirty so the redraw loop refreshes.
local function tick_step()
  for n = 1, NUM_RINGS do
    local r = rings[n]
    if r.speed ~= 0 then
      local prev = r.phase
      local cur = (prev + r.speed) % PHASE_MAX
      r.phase = cur
      local dir = r.speed > 0 and 1 or -1
      local v = math.ceil(n / 2)
      if n % 2 == 1 then
        handle_pitch_ring(v, prev, cur, dir)
      else
        handle_rhythm_ring(v, prev, cur, dir)
      end
      dirty = true
      screen_dirty = true
    end
  end
end
