<!--
Luanti
SPDX-License-Identifier: LGPL-2.1-or-later
Copyright (C) 2026 The Luanti Contributors
-->

# Stage amps and the Lace Waterfall band

`lw_amps` plays a song out of two amp cabinets. `lw_dance` puts Rubella,
Lillith and six fans on stage to dance to it. The first song is Lace
Waterfall's "Around", in seven mixes. The quickest way to hear it is the
**Around arena** (`/maps around_arena`, or the causeway north-east of the
plaza): it has a stage with the two cabs already on it, and the song starts
when you walk in (see [maps.md](maps.md#around-arena)). Two cabs on any
other floor work too, as below.

## Trying it

1. Take two **Amp Cabinets** from the inventory (`i`). Put them on the stage's
   two front corners, a good few nodes apart (six or more). If they are only a
   couple of nodes apart, the floor hears both at the same distance and the
   stereo collapses to mono.
2. Look at the cab on the **audience's left**, as seen from the floor facing
   the stage, and type `/amp left`. Look at the other one and type
   `/amp right`. Each sound comes from one node above the cab you pointed at.
3. **Punch either cab.** "Around" starts, and the band and crowd appear:
   Rubella by the left cab, Lillith by the right, and six fans in two rows off
   the front of the stage, facing the band.
4. Punch a cab again to stop. The band stays on stage, standing idle, until
   the song starts again.

From chat:

```
/amp                    where the cabs are, what is playing
/amp left | right       set the cab you are looking at (server privilege)
/amp play [<song>]      play a song (default: around_happy_hard)
/amp stop               stop it
/amp list               the songs
/amp hear <nodes>       how far the cabs carry (default 80; server privilege)
/amp gain <g>           source gain (default 3; server privilege)
```

`/routine start lace_waterfall_around` also works. If the cabs are set up, it
starts the song as well. `/routine stop lace_waterfall_around` stops both.

## How the song is played

Luanti only places a single-channel Ogg in the world. A stereo file plays with
no position. So each song is **two mono files**: the original left channel and
the original right channel (see `mods/lw_amps/sounds/README.md`). They are
routed so that the audience-left cab plays `_l` and the audience-right cab
plays `_r`.

For each listener the pair is two `core.sound_play` calls in the **same server
step**. Both have `loop = true`, the same `start_time` and `to_player` set to
that listener. A visitor who walks in later is given the pair at
`start_time = elapsed % length`, so they hear the same point in the song as
everyone else, and the same point the band is dancing to.

Things that are easy to get wrong:

* `max_hear_distance` only admits players who are inside it when a playback
  *starts*. So the amps check every second for anyone who has walked into
  range, and start the pair for them. A listener who walks well out of range
  (16 nodes past it) has their pair stopped, which frees two OpenAL sources in
  the browser tab. Walking back in restarts it, in time.
* Positional gain is the level at **3 nodes** from the source. It does not get
  louder inside 1 node, and OpenAL clamps the final gain at 1. So a gain above
  1 does not make the cab louder close up. It carries full volume further out.
  The default of 3 keeps the floor in front of the stage at full level.
* The song clock counts **server steps**, not wall time. In singleplayer the
  pause menu stops the server and pauses every sound, so a wall-clock song
  would come back ahead of the music.

With no sound at all (no OpenAL, a missing file, a `sound_play` that throws),
the song still "plays". The clock runs and the band dances in silence.

## The band and the dance map

The dance is `routines/lace_waterfall_around.lua`, a routine with
`songs = {...}`. When one of its songs starts, the director runs it with its
clock slaved to the song. The details are in
[routines.md](routines.md#dancing-to-a-song). In short:

* **Cast:** `rubella` and `lillith` (group `band`) on stage, and `crowd_1` …
  `crowd_6` (group `crowd`) on the floor. That is eight, the director's cap.
* **Stage:** the routine has no registered stage, so it is built from the
  cabs. The band stands one node back from the line between them, and the
  audience is on the other side. The crowd `settle`s onto the floor in front,
  even if that floor is lower than the stage. A map that registers a stage
  (`lw_dance.register_stage`) or places `lw_dance:mark_*` nodes overrides
  this.
* **Tempo:** 175 bpm. Every move is stretched so that its cycle lands on the
  beat.
* **Sections:** intro, verses, choruses, bridge, build and outro, on eight-bar
  lines. This is a **placeholder** structure until the song is timed. Each
  section is one line with its starting `beat`.
* **Moves:** the pad's `groove`, `wave`, `spin`, `stomp` and `bow`, plus the
  concert moves `sway`, `pogo`, `clap` and `headbang`.

All seven mixes share this one map. A new song only needs its pair in
`mods/lw_amps/sounds/`, a `register_song` line with the length measured from
the files, and a routine naming it in `songs`. It can reuse the same cast.

## Cost

* **Download:** the 14 files are about 26 MiB in `luanti.data`, and the client
  also caches them in IndexedDB. See the content budget in `wasm_porting.md`.
* **Audio:** one song at a time, and two streamed sources per listener in
  range.
* **Entities:** eight dancers. The director already holds that to ten pose
  keys a second, with unchanged bones dropped, and sends nothing when nobody
  is within 48 nodes. Catching up (a song starting part-way, a loop, a visitor
  walking back in) sends each dancer one move, not every step in the map.
