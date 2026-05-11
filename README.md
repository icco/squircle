# squircle

> dual midi sequencer for arc

Two voices, one phasor each, snows-style arc UI. Per voice: arc 1/3 sets phasor speed and shows the pitch lane, arc 2/4 sets Euclidean rhythm density (0% silence, 100% every step).

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
arc 1 / 3 : voice phasor speed     (snows-style sequence + cursor)
arc 2 / 4 : voice rhythm density   (Euclidean pulses, 0..100%)
arc key   : freeze speeds

enc 1 root   enc 2 scale   enc 3 velocity
key 2 regen pitches   key 3 regen rhythms
```

K1 is reserved by norns (quick tap exits to menu), so it isn't bound. Panic, per-voice lane length, MIDI channels, and rhythm step count live in PARAMETERS. Arc feel matches snows via the **arc sensitivity** param (default `4`, mirrors `arc_res(i, 4)` in software).

## parameters

- **midi out** — destination MIDI port
- **arc sensitivity** — `1` most sensitive … `16` slowest
- **panic** — trigger; sends all-notes-off on every voice channel
- **voice 1 / 2 channel** — MIDI channels (default 1, 2)
- **v1 / v2 lane length** — pitch slots per voice (3..12)
- **velocity** — note-on velocity (also e3)
- **root**, **scale** — both lanes (e1 / e2)
- **v1 / v2 rhythm steps** — Euclidean step count
- **v1 / v2 rhythm pulses** — Euclidean pulse count (also arc 2 / 4)

## references

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
