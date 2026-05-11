# squircle

Squircle is a dual midi channel sequencer. It uses the four circles of arc to control the notes and gates sent over midi. In particular it is designed to talk to https://tomwhitwell.github.io/Workshop_Computer/programs/98-duo-midi/index.html or https://busycircuits.com/pages/alm023 over midi. I really like the ui of https://codeberg.org/tehn/iii-scripts/raw/branch/main/arc/snows.lua and https://github.com/tehn/ribbons .

## install

From the maiden REPL:

```
;install https://github.com/icco/squircle
```

## how it works

Two voices, each made of two free-running phasors driven by two arc rings. Turning an encoder adds to that ring's signed *speed*; the LED cursor wraps continuously like a tape loop.

- **voice 1 → midi channel 1**: ring 1 = pitch lane phasor, ring 2 = rhythm/gate phasor
- **voice 2 → midi channel 2**: ring 3 = pitch lane phasor, ring 4 = rhythm/gate phasor

Crossing a step boundary on a pitch ring advances which note in that voice's pitch lane is "currently armed". Crossing a step on a rhythm ring evaluates the next gate slot — rising edges send `note_on` of the armed pitch on that voice's MIDI channel, falling edges send `note_off`. Because each phasor moves at its own rate, the two rings of a voice drift against each other, producing snows-y phasing patterns.

## controls

```
arc enc 1 / 3 : pitch phasor speed   (v1 / v2)
arc enc 2 / 4 : rhythm phasor speed  (v1 / v2)
arc key       : freeze (zero all four speeds)

enc 1 : root note
enc 2 : scale
enc 3 : pitch-lane length

key 2 : regen pitch lanes
key 3 : regen rhythm patterns (long-press: panic)
```

The pitch lane is a contiguous slice of the chosen scale starting from the root, length `lane_len`. Rhythm patterns are Euclidean distributions (`er.gen(pulses, steps)`) configurable per voice in PARAMETERS.

## hardware notes

- **ALM mmMidi (alm023)** maps cleanly to this script's dual-channel design: factory channels 1 and 2 each become an independent V/oct + gate pair. The two squircle voices land on distinct CV outputs.
- **Music Thing Workshop Computer 98-duo-midi** ignores MIDI channel and round-robins all incoming notes across its two voice allocators (or mirrors them in MONO mode). Both squircle voices still work, they just feed a single intelligent allocator instead of staying segregated — useful if you want denser note streams from one card.

You can also point `midi_target` at any DAW input and use squircle as a pure MIDI generator.

## references

- [norns scripting](https://monome.org/docs/norns/scripting/) — norns Lua API
- [norns studies](https://monome.org/docs/norns/studies/) — grid, clock, engine, params tutorials
- [musicutil](https://monome.org/docs/norns/reference/lib/musicutil) — scale generation and note conversion (`musicutil.NOTE_NAMES`, `musicutil.generate_scale`)
- [pattern_time](https://monome.org/docs/norns/reference/lib/pattern_time) — free-time event recorder used for pattern capture and looping
- [PolySub engine](https://monome.org/docs/norns/reference/engine) — built-in polyphonic subtractive synth with ADSR sustain
- [norns tutorial thread](https://llllllll.co/t/norns-tutorial/23241) — community scripting guide
