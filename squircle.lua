-- squircle: dual midi sequencer for arc
-- v0.2.1 @icco
--
-- one phasor per voice, two midi channels
--
-- arc 1 / 3 : phasor speed   (v1 / v2)
-- arc 2 / 4 : transpose      (v1 / v2, scale-degree, wraps octaves)
-- arc key   : freeze speeds
--
-- ribbons-style display: notes appear at their chromatic position on
-- arc 1/3; turning arc 2/4 shifts the whole layout around the ring.
--
-- enc1 root   enc2 scale   enc3 lane length
-- key2 regen pitches   key3 regen rhythms
-- panic and other params live in PARAMETERS

local musicutil = require("musicutil")
local er = require("er")

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

local TICK_HZ = 60
local RING_LEDS = 64
local PHASE_MAX = 1024 -- snows-style fixed-point phase per voice
local SPEED_CLAMP = 32

local NUM_VOICES = 2
local NUM_RINGS = 4

-- ring layout: voice v owns rings (v*2 - 1) pitch and (v*2) transpose
local PITCH_RING = { 1, 3 }
local TRANSPOSE_RING = { 2, 4 }

-- ribbons-style chromatic-anchor offset (sets where root sits on ring)
local RING_OFFSET = 40

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

-- One phasor per voice; phase drives both pitch lane and Euclidean gate.
local phasors = {}
for v = 1, NUM_VOICES do
  phasors[v] = { speed = 0, phase = 0 }
end

local voices = {}
for v = 1, NUM_VOICES do
  voices[v] = {
    ch = v,
    pitch_lane = {},
    pitch_idx = 1,
    offset = 0, -- scale-degree transpose, unbounded; wraps an octave per lane_len
    rhythm = {},
    gate_idx = 0,
    gate_high = false,
    last_note = nil,
  }
end

-- Arc delta accumulator (one per ring) for snows-style coarse stepping.
local arc_ticks = { 0, 0, 0, 0 }

local a -- arc.connect()
local m -- midi.connect(target)
local dirty = true
local screen_dirty = true

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

local function refresh_midi_target()
  m = midi_devices[params:get("midi_target")]
end

-- All-notes-off on every voice channel; clears stuck notes.
local function panic()
  if m == nil then
    return
  end
  for v = 1, NUM_VOICES do
    m:cc(123, 0, params:get("v" .. v .. "_ch"))
    voices[v].last_note = nil
    voices[v].gate_high = false
  end
end

-- ---------------------------------------------------------------------------
-- Params
-- ---------------------------------------------------------------------------

-- Forward decls; setup_params set_actions call these.
local regen_pitch_lane
local regen_pitch_lanes
local regen_rhythm
local regen_rhythms

local scale_names = {}
for i, s in ipairs(musicutil.SCALES) do
  scale_names[i] = s.name
end

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

  -- Raw arc deltas per emitted step. Default 4 == snows.lua arc_res(i, 4).
  params:add_number("arc_sens", "arc sensitivity", 1, 16, 4)

  params:add_trigger("panic", "panic (all notes off)")
  params:set_action("panic", panic)

  params:add_group("voices", 8)
  params:add_number("v1_ch", "voice 1 channel", 1, 16, 1)
  params:add_number("v2_ch", "voice 2 channel", 1, 16, 2)
  params:add_number("v1_transpose", "v1 transpose", -24, 24, 0)
  params:set_action("v1_transpose", function(x)
    voices[1].offset = x
    dirty = true
    screen_dirty = true
  end)
  params:add_number("v2_transpose", "v2 transpose", -24, 24, 0)
  params:set_action("v2_transpose", function(x)
    voices[2].offset = x
    dirty = true
    screen_dirty = true
  end)
  params:add_number("velocity", "velocity", 1, 127, 100)
  params:add_option("root", "root", musicutil.NOTE_NAMES, 1)
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

-- Distinct registers so a shared root yields two octaves.
local VOICE_BASE = { 60, 48 }

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

-- Software accumulator; emits one step per arc_sens raw deltas.
-- Mirrors snows' arc_res(i, 4) since norns has no hardware-res arc API.
local function on_arc_delta(n, d)
  local sens = params:get("arc_sens")
  arc_ticks[n] = arc_ticks[n] + d
  if math.abs(arc_ticks[n]) < sens then
    return
  end
  local val = arc_ticks[n] / sens
  val = (val > 0) and math.floor(val) or math.ceil(val)
  arc_ticks[n] = math.fmod(arc_ticks[n], sens)
  if val == 0 then
    return
  end

  local v = math.ceil(n / 2)
  if n % 2 == 1 then
    phasors[v].speed = util.clamp(phasors[v].speed + val, -SPEED_CLAMP, SPEED_CLAMP)
  else
    params:delta("v" .. v .. "_transpose", val)
  end
  dirty = true
  screen_dirty = true
end

-- Arc key freezes both voice phasors. Offsets are persistent.
local function on_arc_key(n, z)
  if z == 1 then
    for v = 1, NUM_VOICES do
      phasors[v].speed = 0
    end
    for i = 1, NUM_RINGS do
      arc_ticks[i] = 0
    end
    dirty = true
    screen_dirty = true
  end
end

local function setup_arc()
  a = arc.connect()
  a.delta = on_arc_delta
  a.key = on_arc_key
end

-- ---------------------------------------------------------------------------
-- Sequencer tick
-- ---------------------------------------------------------------------------

-- Slots crossed prev -> cur on a circle of `num`, direction `dir`.
local function steps_between(prev, cur, num, dir)
  if dir > 0 then
    return (cur - prev) % num
  else
    return (prev - cur) % num
  end
end

-- Rotate within the lane; shift an octave each time offset wraps.
local function voice_note(v)
  local lane = voices[v].pitch_lane
  local len = #lane
  if len == 0 then
    return nil
  end
  local k = (voices[v].pitch_idx - 1) + voices[v].offset
  local idx = (k % len) + 1
  local octave_shift = math.floor(k / len) * 12
  return lane[idx] + octave_shift
end

-- Rising edge: note_on armed pitch. Falling edge: note_off last.
local function apply_gate(v, gate_on)
  local voice = voices[v]
  if gate_on and not voice.gate_high then
    local note = voice_note(v)
    if note and m then
      m:note_on(note, params:get("velocity"), params:get("v" .. v .. "_ch"))
      voice.last_note = note
    end
    voice.gate_high = true
  elseif not gate_on and voice.gate_high then
    if voice.last_note and m then
      m:note_off(voice.last_note, 0, params:get("v" .. v .. "_ch"))
    end
    voice.last_note = nil
    voice.gate_high = false
  end
end

local function handle_pitch_ring(v, prev_phase, cur_phase, dir)
  local lane = voices[v].pitch_lane
  if #lane == 0 then
    return
  end
  local slot_w = PHASE_MAX / #lane
  local crossings =
    steps_between(math.floor(prev_phase / slot_w), math.floor(cur_phase / slot_w), #lane, dir)
  for _ = 1, crossings do
    if dir > 0 then
      voices[v].pitch_idx = (voices[v].pitch_idx % #lane) + 1
    else
      voices[v].pitch_idx = ((voices[v].pitch_idx - 2) % #lane) + 1
    end
  end
end

-- Walk one slot at a time so balanced pairs still fire at high speed.
local function handle_rhythm_ring(v, prev_phase, cur_phase, dir)
  local pat = voices[v].rhythm
  if #pat == 0 then
    return
  end
  local slot_w = PHASE_MAX / #pat
  local crossings =
    steps_between(math.floor(prev_phase / slot_w), math.floor(cur_phase / slot_w), #pat, dir)
  for _ = 1, crossings do
    if dir > 0 then
      voices[v].gate_idx = (voices[v].gate_idx % #pat) + 1
    else
      voices[v].gate_idx = ((voices[v].gate_idx - 2) % #pat) + 1
    end
    apply_gate(v, pat[voices[v].gate_idx])
  end
end

local function tick_step()
  for v = 1, NUM_VOICES do
    local p = phasors[v]
    if p.speed ~= 0 then
      local prev = p.phase
      local cur = (prev + p.speed) % PHASE_MAX
      p.phase = cur
      local dir = p.speed > 0 and 1 or -1
      handle_pitch_ring(v, prev, cur, dir)
      handle_rhythm_ring(v, prev, cur, dir)
      dirty = true
      screen_dirty = true
    end
  end
end

-- ---------------------------------------------------------------------------
-- Arc drawing
-- ---------------------------------------------------------------------------

-- Ribbons-style chromatic placement: each note shows up at its MIDI value
-- mod 64 (anchored by RING_OFFSET). Turn the transpose wheel and every
-- note's chromatic position shifts, so arc 1/3 and arc 2/4 visibly
-- rotate together.
local function chromatic_pos(note)
  return (note + RING_OFFSET) % RING_LEDS + 1
end

-- Note at lane index i (0-based) with the voice's transpose applied.
local function lane_note_at(v, i)
  local lane = voices[v].pitch_lane
  local len = #lane
  local k = i + voices[v].offset
  local idx = (k % len) + 1
  local octave_shift = math.floor(k / len) * 12
  return lane[idx] + octave_shift
end

local function draw_pitch_ring(v)
  local n = PITCH_RING[v]
  local len = #voices[v].pitch_lane
  if len == 0 then
    return
  end
  for i = 0, len - 1 do
    a:led(n, chromatic_pos(lane_note_at(v, i)), 3)
  end
  -- Bright LED at the currently armed note's chromatic position.
  local now_note = voice_note(v)
  if now_note then
    a:led(n, chromatic_pos(now_note), 15)
  end
end

-- Transpose ring: same chromatic layout (so the wheel feels coupled to
-- the pitch ring) plus a brighter marker on the lane's current downbeat
-- (lane index 0 with transpose applied) so turning the wheel produces
-- immediate motion on this ring as well.
local function draw_transpose_ring(v)
  local n = TRANSPOSE_RING[v]
  local len = #voices[v].pitch_lane
  if len == 0 then
    return
  end
  for i = 0, len - 1 do
    a:led(n, chromatic_pos(lane_note_at(v, i)), 3)
  end
  a:led(n, chromatic_pos(lane_note_at(v, 0)), 15)
end

local function draw_arc()
  if a == nil then
    return
  end
  a:all(0)
  for v = 1, NUM_VOICES do
    draw_pitch_ring(v)
    draw_transpose_ring(v)
  end
end

-- ---------------------------------------------------------------------------
-- Norns hardware callbacks
-- ---------------------------------------------------------------------------

-- K1 is reserved by norns (a quick tap exits the script to the menu),
-- so we never bind K1 here. K2 / K3 each do exactly one thing on press.
function key(n, z)
  if z ~= 1 then
    return
  end
  if n == 2 then
    regen_pitch_lanes()
  elseif n == 3 then
    regen_rhythms()
  end
  screen_dirty = true
end

function enc(n, d)
  if n == 1 then
    params:delta("root", d)
  elseif n == 2 then
    params:delta("scale", d)
  elseif n == 3 then
    params:delta("lane_len", d)
  end
  screen_dirty = true
end

local function speed_glyph(speed)
  if speed == 0 then
    return "."
  end
  local mag = math.min(math.abs(speed), SPEED_CLAMP)
  local bars = math.ceil(mag / (SPEED_CLAMP / 3))
  return string.rep((speed > 0) and ">" or "<", bars)
end

local function draw_voice_row(v, y)
  local voice = voices[v]
  local note = voice_note(v)
  local note_str = note and musicutil.note_num_to_name(note, true) or "--"
  local gate_str = voice.gate_high and "*" or "-"

  screen.level(15)
  screen.move(2, y)
  screen.text("v" .. v .. " ch" .. params:get("v" .. v .. "_ch"))

  screen.level(10)
  screen.move(36, y)
  screen.text(note_str)

  screen.level(voice.gate_high and 15 or 4)
  screen.move(64, y)
  screen.text(gate_str)

  screen.level(6)
  screen.move(72, y)
  screen.text("s:" .. speed_glyph(phasors[v].speed))
  screen.move(98, y)
  local off = voice.offset
  local off_str = (off >= 0) and ("t:+" .. off) or ("t:" .. off)
  screen.text(off_str)
end

function redraw()
  screen.clear()
  screen.font_face(1)
  screen.font_size(8)

  screen.level(6)
  screen.move(2, 10)
  screen.text("squircle")
  screen.level(10)
  screen.move(60, 10)
  screen.text(musicutil.NOTE_NAMES[params:get("root")] .. " " .. scale_names[params:get("scale")])

  draw_voice_row(1, 30)
  draw_voice_row(2, 44)

  screen.level(3)
  screen.move(2, 62)
  screen.text("arc 2/4 transpose   k2/3 regen")

  screen.update()
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

local tick_clock_id
local screen_clock_id

local function tick_loop()
  while true do
    clock.sleep(1 / TICK_HZ)
    tick_step()
    if dirty then
      draw_arc()
      if a then
        a:refresh()
      end
      dirty = false
    end
  end
end

local function screen_loop()
  while true do
    clock.sleep(1 / 15)
    if screen_dirty then
      redraw()
      screen_dirty = false
    end
  end
end

function init()
  setup_params()
  refresh_midi_target()
  setup_arc()

  regen_pitch_lanes()
  regen_rhythms()

  tick_clock_id = clock.run(tick_loop)
  screen_clock_id = clock.run(screen_loop)

  redraw()
  draw_arc()
  if a then
    a:refresh()
  end
end

function cleanup()
  if tick_clock_id then
    clock.cancel(tick_clock_id)
    tick_clock_id = nil
  end
  if screen_clock_id then
    clock.cancel(screen_clock_id)
    screen_clock_id = nil
  end
  panic()
end
