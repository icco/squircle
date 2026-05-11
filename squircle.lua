-- squircle: dual midi sequencer for arc
-- v0.3.0 @icco
--
-- snows-mode: a slowly moving sequencer per voice. Each voice has its
-- own root, scale, octave, and lane of N slots (3..32). Arc 2 / 4
-- chooses how many slots are pulses (Euclidean), so dots light up on
-- the matching arc 1 / 3 cluster as you turn it up.
--
-- arc 1 / 3 : voice phasor speed   (snows cluster: pulse / rest / armed)
-- arc 2 / 4 : voice density        (Euclidean pulses, 0..100% of lane)
-- arc key   : freeze speeds
--
-- enc1 velocity   enc2 v1 octave   enc3 v2 octave
-- key2 cycle v1 scale   key3 cycle v2 scale
-- per-voice root / lane length / panic live in PARAMETERS

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

-- ring layout: voice v owns rings (v*2 - 1) sequence and (v*2) density
local SEQ_RING = { 1, 3 }
local PULSE_RING = { 2, 4 }

local LANE_LEN_MIN = 3
local LANE_LEN_MAX = 32

-- Pulses share lane bounds: 0 = silence, lane_len = every slot fires.
local LANE_LEN_MIN_PULSES = 0

local OCTAVE_MIN = 0
local OCTAVE_MAX = 8

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

local phasors = {}
for v = 1, NUM_VOICES do
  phasors[v] = { speed = 0, phase = 0 }
end

local voices = {}
for v = 1, NUM_VOICES do
  voices[v] = {
    ch = v,
    pitch_lane = {}, -- length = lane_len, MIDI notes
    rhythm = {}, -- same length, true = pulse, false = rest
    pitch_idx = 1,
    last_note = nil,
    gate_high = false,
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
local regen_rhythm

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

  -- Raw deltas per emitted step (snows arc_res(i, 4) feel at 4).
  params:add_number("arc_sens", "arc sensitivity", 1, 16, 4)

  params:add_trigger("panic", "panic (all notes off)")
  params:set_action("panic", panic)

  params:add_number("velocity", "velocity", 1, 127, 100)

  for v = 1, NUM_VOICES do
    local default_octave = (v == 1) and 5 or 4
    params:add_group("voice " .. v, 6)
    params:add_number("v" .. v .. "_ch", "channel", 1, 16, v)
    params:add_option("v" .. v .. "_root", "root", musicutil.NOTE_NAMES, 1)
    params:set_action("v" .. v .. "_root", function()
      regen_pitch_lane(v)
    end)
    params:add_option("v" .. v .. "_scale", "scale", scale_names, scale_index("Natural Minor"))
    params:set_action("v" .. v .. "_scale", function()
      regen_pitch_lane(v)
    end)
    params:add_number("v" .. v .. "_octave", "octave", OCTAVE_MIN, OCTAVE_MAX, default_octave)
    params:set_action("v" .. v .. "_octave", function()
      regen_pitch_lane(v)
    end)
    params:add_number("v" .. v .. "_lane_len", "lane length", LANE_LEN_MIN, LANE_LEN_MAX, 16)
    params:set_action("v" .. v .. "_lane_len", function()
      regen_pitch_lane(v)
      regen_rhythm(v)
    end)
    params:add_number("v" .. v .. "_pulses", "pulses", LANE_LEN_MIN_PULSES, LANE_LEN_MAX, 1)
    params:set_action("v" .. v .. "_pulses", function(p)
      local len = params:get("v" .. v .. "_lane_len")
      if p > len then
        params:set("v" .. v .. "_pulses", len)
        return
      end
      regen_rhythm(v)
    end)
  end

  params:bang()
end

-- ---------------------------------------------------------------------------
-- Pattern generation
-- ---------------------------------------------------------------------------

function regen_pitch_lane(v)
  local root_idx = params:get("v" .. v .. "_root")
  local octave = params:get("v" .. v .. "_octave")
  local root = (root_idx - 1) + octave * 12
  local scale_name = scale_names[params:get("v" .. v .. "_scale")]
  local len = params:get("v" .. v .. "_lane_len")
  voices[v].pitch_lane = musicutil.generate_scale_of_length(root, scale_name, len)
  if voices[v].pitch_idx > #voices[v].pitch_lane then
    voices[v].pitch_idx = 1
  end
  dirty = true
  screen_dirty = true
end

function regen_rhythm(v)
  local len = params:get("v" .. v .. "_lane_len")
  local pulses = math.min(params:get("v" .. v .. "_pulses"), len)
  local rhythm = {}
  if pulses <= 0 then
    for i = 1, len do
      rhythm[i] = false
    end
  else
    rhythm = er.gen(pulses, len)
  end
  voices[v].rhythm = rhythm
  dirty = true
  screen_dirty = true
end

-- ---------------------------------------------------------------------------
-- Arc input
-- ---------------------------------------------------------------------------

-- snows arc_res(i, 4) emulated in software (no hardware-res arc API on norns).
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
    params:delta("v" .. v .. "_pulses", val)
  end
  dirty = true
  screen_dirty = true
end

-- Arc key freezes both voice phasors.
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

local function voice_note(v)
  local lane = voices[v].pitch_lane
  if #lane == 0 then
    return nil
  end
  return lane[voices[v].pitch_idx]
end

-- One slot crossing: kill any held note, then fire a new note iff the
-- newly armed slot is a pulse. Walked one slot at a time so high speed
-- still emits every step.
local function step_voice(v, prev_phase, cur_phase, dir)
  local voice = voices[v]
  local lane = voice.pitch_lane
  local len = #lane
  if len == 0 then
    return
  end
  local slot_w = PHASE_MAX / len
  local crossings =
    steps_between(math.floor(prev_phase / slot_w), math.floor(cur_phase / slot_w), len, dir)
  for _ = 1, crossings do
    if dir > 0 then
      voice.pitch_idx = (voice.pitch_idx % len) + 1
    else
      voice.pitch_idx = ((voice.pitch_idx - 2) % len) + 1
    end
    if voice.last_note and m then
      m:note_off(voice.last_note, 0, params:get("v" .. v .. "_ch"))
    end
    voice.last_note = nil
    voice.gate_high = false
    if voice.rhythm[voice.pitch_idx] and m then
      local note = lane[voice.pitch_idx]
      if note then
        m:note_on(note, params:get("velocity"), params:get("v" .. v .. "_ch"))
        voice.last_note = note
        voice.gate_high = true
      end
    end
  end
end

local function tick_step()
  for v = 1, NUM_VOICES do
    local p = phasors[v]
    if p.speed ~= 0 then
      local prev = p.phase
      local cur = (prev + p.speed) % PHASE_MAX
      p.phase = cur
      step_voice(v, prev, cur, p.speed > 0 and 1 or -1)
      dirty = true
      screen_dirty = true
    end
  end
end

-- ---------------------------------------------------------------------------
-- Arc drawing
-- ---------------------------------------------------------------------------

-- snows.lua triple-LED interpolated cursor.
local function point(ring, x)
  local xi = math.floor(x)
  local c = xi >> 4
  a:led(ring, c % 64 + 1, 15)
  a:led(ring, (c + 1) % 64 + 1, xi % 16)
  a:led(ring, (c + 63) % 64 + 1, 15 - (xi % 16))
end

-- snows-style cluster: rest = level 1, pulse = level 5, armed slot = 12.
-- Cluster anchors at LED 32, with adaptive spacing so up to 32 slots
-- still fit on the 64-LED ring (spacing 2 like snows for short lanes,
-- collapsing to 1 once the lane gets long enough to need it).
local function draw_seq_ring(v)
  local n = SEQ_RING[v]
  local voice = voices[v]
  local len = #voice.pitch_lane
  if len == 0 then
    return
  end
  local spacing = math.max(1, math.min(2, math.floor(RING_LEDS / 2 / len)))
  for i = 1, len do
    local pos = ((32 + i * spacing - 1) % RING_LEDS) + 1
    local level = voice.rhythm[i] and 5 or 1
    if i == voice.pitch_idx then
      level = 12
    end
    a:led(n, pos, level)
  end
  point(n, phasors[v].phase)
end

-- Hard on/off fill 0..100% (silent at 0, full ring at pulses == lane_len).
local function draw_pulse_ring(v)
  local n = PULSE_RING[v]
  local len = params:get("v" .. v .. "_lane_len")
  local pulses = math.min(params:get("v" .. v .. "_pulses"), len)
  if len <= 0 then
    return
  end
  local fill = math.floor(pulses / len * RING_LEDS + 0.5)
  for i = 1, fill do
    a:led(n, i, 15)
  end
end

local function draw_arc()
  if a == nil then
    return
  end
  a:all(0)
  for v = 1, NUM_VOICES do
    draw_seq_ring(v)
    draw_pulse_ring(v)
  end
end

-- ---------------------------------------------------------------------------
-- Norns hardware callbacks
-- ---------------------------------------------------------------------------

-- K1 is reserved (quick tap exits to menu). K2 / K3 cycle each voice's
-- scale forward (wraps at the end of musicutil.SCALES).
local function cycle_scale(v)
  local id = "v" .. v .. "_scale"
  params:set(id, (params:get(id) % #scale_names) + 1)
end

function key(n, z)
  if z ~= 1 then
    return
  end
  if n == 2 then
    cycle_scale(1)
  elseif n == 3 then
    cycle_scale(2)
  end
  screen_dirty = true
end

function enc(n, d)
  if n == 1 then
    params:delta("velocity", d)
  elseif n == 2 then
    params:delta("v1_octave", d)
  elseif n == 3 then
    params:delta("v2_octave", d)
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

local function scale_short(name)
  return string.upper(string.sub(name, 1, 3))
end

local function draw_voice_row(v, y)
  local voice = voices[v]
  local note = voice_note(v)
  local note_str = note and musicutil.note_num_to_name(note, true) or "--"
  local gate_str = voice.gate_high and "*" or "-"
  local root_idx = params:get("v" .. v .. "_root")
  local octave = params:get("v" .. v .. "_octave")
  local scale_str = scale_short(scale_names[params:get("v" .. v .. "_scale")])
  local key_str = musicutil.NOTE_NAMES[root_idx] .. scale_str .. octave
  local len = params:get("v" .. v .. "_lane_len")
  local pulses = math.min(params:get("v" .. v .. "_pulses"), len)

  screen.level(15)
  screen.move(2, y)
  screen.text("v" .. v)

  screen.level(8)
  screen.move(15, y)
  screen.text(key_str)

  screen.level(10)
  screen.move(54, y)
  screen.text(note_str)

  screen.level(voice.gate_high and 15 or 4)
  screen.move(78, y)
  screen.text(gate_str)

  screen.level(6)
  screen.move(86, y)
  screen.text(speed_glyph(phasors[v].speed))

  screen.level(6)
  screen.move(108, y)
  screen.text(pulses .. "/" .. len)
end

function redraw()
  screen.clear()
  screen.font_face(1)
  screen.font_size(8)

  screen.level(6)
  screen.move(2, 10)
  screen.text("squircle")
  screen.level(4)
  screen.move(126, 10)
  screen.text_right("vel " .. params:get("velocity"))

  draw_voice_row(1, 28)
  draw_voice_row(2, 44)

  screen.level(3)
  screen.move(2, 62)
  screen.text("e1 vel  e2/3 oct  k2/3 scale")

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
