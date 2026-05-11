# squircle

Squircle is a dual midi channel sequencer. It uses the four circles of arc to control the notes and gates sent over midi. In particular it is designed to talk to https://tomwhitwell.github.io/Workshop_Computer/programs/98-duo-midi/index.html or https://busycircuits.com/pages/alm023 over midi. I really like the ui of https://codeberg.org/tehn/iii-scripts/raw/branch/main/arc/snows.lua and https://github.com/tehn/ribbons .

## references

- [norns scripting](https://monome.org/docs/norns/scripting/) — norns Lua API
- [norns studies](https://monome.org/docs/norns/studies/) — grid, clock, engine, params tutorials
- [musicutil](https://monome.org/docs/norns/reference/lib/musicutil) — scale generation and note conversion (`musicutil.NOTE_NAMES`, `musicutil.generate_scale`)
- [pattern_time](https://monome.org/docs/norns/reference/lib/pattern_time) — free-time event recorder used for pattern capture and looping
- [PolySub engine](https://monome.org/docs/norns/reference/engine) — built-in polyphonic subtractive synth with ADSR sustain
- [norns tutorial thread](https://llllllll.co/t/norns-tutorial/23241) — community scripting guide
