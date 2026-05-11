# squircle

> dual midi sequencer for arc

Four free-running phasors, two MIDI voices. Each pitch ring advances through a scale lane; each rhythm ring fires gates from a Euclidean pattern. Voice 1 lands on MIDI ch 1, voice 2 on ch 2 (configurable in PARAMETERS).

UI inspired by [snows.lua](https://codeberg.org/tehn/iii-scripts/raw/branch/main/arc/snows.lua) and [ribbons](https://github.com/tehn/ribbons). Designed for [Music Thing 98-duo-midi](https://tomwhitwell.github.io/Workshop_Computer/programs/98-duo-midi/index.html) and [ALM mmMidi](https://busycircuits.com/pages/alm023), but works with any MIDI destination.

## requirements

- [norns](https://monome.org/docs/norns/) (any version with arc support)
- [arc](https://monome.org/docs/arc/) (4 ring)
- a MIDI destination (hardware module, synth, or another norns)

## install

In maiden:

```
;install https://github.com/icco/squircle
```

## controls

```
arc 1 / 3 : pitch phasor speed   (v1 / v2)
arc 2 / 4 : rhythm phasor speed  (v1 / v2)
arc key   : freeze (zero all four speeds)

enc 1 : root           enc 2 : scale         enc 3 : pitch lane length
key 2 : regen pitches  key 3 : regen rhythms (hold: panic)
```

Crossing a step boundary on a pitch ring advances the armed note in that voice's lane. Crossing a step on a rhythm ring evaluates the next gate slot — rising edges send `note_on` of the armed pitch, falling edges send `note_off`. Two phasors per voice running at independent rates produces snows-y phasing patterns.

## parameters

- **midi out** — destination MIDI port
- **voice 1 / 2 channel** — MIDI channels (default 1 and 2)
- **velocity** — note-on velocity for both voices
- **root**, **scale**, **pitch lane length** — drives both pitch lanes
- **v1 / v2 rhythm steps** and **pulses** — Euclidean pattern per voice

## hardware notes

Both [mmMidi](https://busycircuits.com/pages/alm023) and [98-duo-midi](https://tomwhitwell.github.io/Workshop_Computer/programs/98-duo-midi/index.html) end up with two independent V/oct + gate pairs from squircle's two voices. mmMidi routes by MIDI channel; 98-duo-midi receives on all channels and allocates by nearest pitch, which lands cleanly because the two voices default to different octaves.

## license

[GPL-3.0](https://github.com/icco/squircle/blob/main/LICENSE)
