# squircle

Dual midi channel sequencer for norns + arc. Each of the four arc rings is a free-running phasor; pitch rings advance through a scale lane, rhythm rings fire gates on a Euclidean pattern. Designed for [98-duo-midi](https://tomwhitwell.github.io/Workshop_Computer/programs/98-duo-midi/index.html) and [ALM mmMidi](https://busycircuits.com/pages/alm023).

UI inspired by [snows.lua](https://codeberg.org/tehn/iii-scripts/raw/branch/main/arc/snows.lua) and [ribbons](https://github.com/tehn/ribbons).

## install

```
;install https://github.com/icco/squircle
```

## controls

```
arc enc 1 / 3 : pitch phasor speed   (v1 / v2)
arc enc 2 / 4 : rhythm phasor speed  (v1 / v2)
arc key       : freeze (zero all four speeds)

enc 1 : root         enc 2 : scale         enc 3 : pitch lane length
key 2 : regen pitches    key 3 : regen rhythms (hold: panic)
```

Voice 1 lands on MIDI ch 1, voice 2 on ch 2 (configurable in PARAMETERS). mmMidi splits these to independent CV+gate pairs; 98-duo-midi round-robins both into one duo allocator.

## references

- [norns scripting](https://monome.org/docs/norns/scripting/)
- [musicutil](https://monome.org/docs/norns/reference/lib/musicutil)
- [er](https://monome.org/docs/norns/reference/lib/er)
