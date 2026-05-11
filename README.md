# squircle

> dual midi sequencer for arc

Two free-running voices, each with its own phasor and a scale-degree transpose wheel. The phasor advances both a pitch lane and a Euclidean rhythm pattern; the transpose wheel rotates the lane through octaves. Voice 1 lands on MIDI ch 1, voice 2 on ch 2 (configurable in PARAMETERS).

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
arc 1 / 3 : voice phasor speed   (v1 / v2)   -- drives both pitch + rhythm
arc 2 / 4 : voice pitch offset   (v1 / v2)   -- scale-degree transpose, wraps octaves
arc key   : freeze (zero both speeds)

enc 1 : root           enc 2 : scale         enc 3 : pitch lane length
key 2 : regen pitches  key 3 : regen rhythms

hold key 1 for alt:
  k1+e1 velocity   k1+e2 v1 pulses   k1+e3 v2 pulses
  k1+k2 panic      k1+k3 regen all
```

Each voice has one shared phasor. As its phase advances, crossing a pitch slot moves the armed note in that voice's lane; crossing a rhythm slot evaluates the next Euclidean gate (rising edge → `note_on` of the armed pitch, falling edge → `note_off`). The pitch-offset wheel rotates within the lane and shifts up or down an octave each time it wraps past the lane edge — so a full revolution of the offset ring transposes by exactly one octave.

Arc encoder feel matches snows: the **arc sensitivity** parameter (default `4`) sets how many raw arc deltas are accumulated per emitted step, replicating snows' `arc_res(i, 4)` in software.

## parameters

- **midi out** — destination MIDI port
- **arc sensitivity** — raw arc deltas per emitted step (1 = most sensitive, 16 = slowest)
- **voice 1 / 2 channel** — MIDI channels (default 1 and 2)
- **velocity** — note-on velocity for both voices (also reachable via k1+e1)
- **root**, **scale**, **pitch lane length** — drives both pitch lanes
- **v1 / v2 rhythm steps** and **pulses** — Euclidean pattern per voice (pulses also via k1+e2 / k1+e3)

## license

[GPL-3.0](https://github.com/icco/squircle/blob/main/LICENSE)
