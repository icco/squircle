# squircle

> dual midi sequencer for arc

Two voices, each with one phasor and a scale-degree transpose wheel. The phasor advances both a pitch lane and a Euclidean rhythm; the transpose wheel rotates the lane through octaves.

UI inspired by [snows.lua](https://codeberg.org/tehn/iii-scripts/raw/branch/main/arc/snows.lua) and [ribbons](https://github.com/tehn/ribbons). Designed for [Music Thing 98-duo-midi](https://tomwhitwell.github.io/Workshop_Computer/programs/98-duo-midi/index.html) and [ALM mmMidi](https://busycircuits.com/pages/alm023), but works with any MIDI destination.

## requirements

- [norns](https://monome.org/docs/norns/) (any version with arc support)
- [arc](https://monome.org/docs/arc/) (4 ring)
- a MIDI destination

## install

In maiden:

```
;install https://github.com/icco/squircle
```

## controls

```
arc 1 / 3 : phasor speed   (v1 / v2, drives pitch + rhythm)
arc 2 / 4 : transpose      (v1 / v2, scale-degree, wraps octaves)
arc key   : freeze speeds

enc 1 root   enc 2 scale   enc 3 lane length
key 2 regen pitches   key 3 regen rhythms

hold key 1 for alt:
  k1+e1 velocity   k1+e2 v1 pulses   k1+e3 v2 pulses
  k1+k2 panic      k1+k3 regen all
```

Arc encoder feel matches snows: the **arc sensitivity** param (default `4`) sets raw arc deltas per emitted step, mirroring `arc_res(i, 4)` in software.

## parameters

- **midi out** — destination MIDI port
- **arc sensitivity** — `1` most sensitive … `16` slowest
- **voice 1 / 2 channel** — MIDI channels (default 1, 2)
- **velocity** — note-on velocity (also k1+e1)
- **root**, **scale**, **pitch lane length** — both lanes
- **v1 / v2 rhythm steps + pulses** — Euclidean per voice (pulses also k1+e2 / k1+e3)

## references

Read these before changing arc input, encoder feel, or norns key/encoder UX.

Reference scripts:

- [snows.lua](https://codeberg.org/tehn/iii-scripts/raw/branch/main/arc/snows.lua) — arc phasors + `arc_res(i, 4)` feel
- [ribbons](https://github.com/tehn/ribbons) — arc delta accumulator pattern (`a.delta`, `SENS = 32`)

Norns API:

- [reference index](https://monome.org/docs/norns/reference/) and [arc](https://monome.org/docs/norns/reference/arc) — note: arc has no hardware-resolution API
- [encoders](https://monome.org/docs/norns/reference/encoders), [paramset](https://monome.org/docs/norns/reference/params), [midi](https://monome.org/docs/norns/reference/midi), [clock](https://monome.org/docs/norns/reference/clock), [screen](https://monome.org/docs/norns/api/modules/screen.html)
- [musicutil](https://monome.org/docs/norns/reference/lib/musicutil), [er](https://monome.org/docs/norns/reference/lib/er)

UX:

- [play](https://monome.org/docs/norns/play) — K1/K2/K3 + E1/E2/E3 conventions, K1+ alt combos
- [norns scripting best practices](https://llllllll.co/t/norns-scripting-best-practices/23606)
- [coding style (wiki)](https://github.com/monome/norns/wiki/coding-style-(lua))

## license

[GPL-3.0](https://github.com/icco/squircle/blob/main/LICENSE)
