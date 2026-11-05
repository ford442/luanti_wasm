<!--
Luanti
SPDX-License-Identifier: LGPL-2.1-or-later
Copyright (C) 2026 The Luanti Contributors
-->

# Thunder chapel organ slot

This folder is the thunder chapel's (`halloween_storm`) optional soundtrack
slot. It ships empty on purpose. Drop one file here and the chapel plays it;
leave it empty and the chapel is quiet apart from its thunder.

## Adding the track

1. Make the file **mono Ogg Vorbis**. Luanti only places a sound in the world
   when it has one channel. A stereo file plays with no position at all, and
   the engine warns "Creating positional stereo sound". No FLAC, MP3 or WAV:
   the engine decodes Ogg Vorbis only.

   ```sh
   ffmpeg -i pipe_organ_master.wav -ac 1 -ar 44100 -c:a libvorbis -q:a 3 \
   	lw_maps_halloween_storm_organ.ogg
   ```

2. Save it under exactly this name, in this folder:

   ```
   games/luanti_web/mods/lw_maps/organ/lw_maps_halloween_storm_organ.ogg
   ```

   Do not put it in `lw_maps/sounds/`. That folder is join-time media (see
   below).

3. Restart the server. In the browser, rebuild and reload the page. No code
   change and no register call: the slot is already registered. It is the
   `organ = {...}` field of the `halloween_storm` row in
   `games/luanti_web/mods/lw_maps/init.lua`:

   ```lua
   organ = {
   	at = {x = 19, y = 12, z = 28},              -- map-local: over the loft console
   	sound = "lw_maps_halloween_storm_organ",    -- this folder's <sound>.ogg
   	gain = 0.6,
   	max_hear_distance = 48,
   },
   ```

   If you want a different file name, change `sound` to match it, without the
   `.ogg`. Do not end the name in `.<digit>` (`organ.1`). Luanti reads that as
   a random sound group. `gain` and `max_hear_distance` are the usual
   `core.sound_play` parameters. At 48 the organ can be heard across the
   island but not from the causeway.

`lw_maps` checks for the file once per server start.

## What happens when it is there

* A visitor walks onto the chapel. `lw_maps` pushes the file to that one
  player with `core.dynamic_add_media` (`to_player`, not ephemeral,
  `client_cache = false`).
* When their client says it has the file, the organ starts. It is one looping,
  positional sound (`loop = true`), placed over the organ console in the loft
  and played to that player only (`to_player`).
* The visitor walks off. Their loop fades out over about half a second. The
  next time they arrive it starts again, and the file is not sent a second
  time.
* Each visitor gets their own loop. A missing file, a build without OpenAL,
  or an engine without dynamic media means no organ, and no error either.

The loop restarts from the top on each visit. It is not synced between
visitors the way the stage amps are. Write the track to loop cleanly: no
silence at either end, and an end that leads back into its start.

## Why not `sounds/`

Everything in a mod's `sounds/` (and `textures/`, `models/`, `media/`)
folder goes into the media list. Every client downloads that list and checks
its hashes before the world loads, whether or not it ever visits the chapel.
`organ/` is not one of those folders, so the track is outside that set. Only
visitors to the chapel receive it, and only when they arrive.

## The web download

That covers the engine's media. The web build has a second, separate cost:
`src/CMakeLists.txt` preloads the whole of `games/luanti_web` into
`luanti.data`, the file every visitor downloads before the engine starts. A
track committed here makes that file bigger by the track's size. See the
content budget in `wasm_porting.md`. `luanti.data` is meant to stay under
about 40 MB, and the stage amps' songs already take most of that.

So keep it small:

* Make the loop one to two minutes long, mono, at Vorbis `-q:a 2` or `-q:a 3`
  (about 0.5 to 1.5 MiB).
* For a long or high-quality track, keep the file out of the repository.
  Copy it into this folder only in the build or server that should have it.
  A dedicated or native server reads it from disk and sends it only to
  visitors of the chapel.
* Say how much the file adds in the pull request, as the PR template asks.

## Rights

The recording is the contributor's. If you commit a track, add its source and
licence to this file. Media is not covered by the LGPL that covers the code.
