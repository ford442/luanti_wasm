<!--
Luanti
SPDX-License-Identifier: LGPL-2.1-or-later
Copyright (C) 2026 The Luanti Contributors
-->

# Cabaret songs

This folder holds the cabaret club's songs (the `cabaret` map; see
`docs/maps.md`). It ships with no audio. The cabs, the stage and Rubella and
Lillith are already there, waiting for the songs.

## Adding a song

1. **Cut the stereo master into two mono Ogg Vorbis files.** Luanti only
   places a sound in the world when it has one channel. The left channel
   plays from the audience-left cab and the right channel from the
   audience-right one, as with the stage amps' "Around" (see
   `../sounds/README.md`). Pick a name of lowercase letters, digits and `_`,
   starting with `cabaret_`, for example `cabaret_velvet`:

   ```sh
   cd games/luanti_web/mods/lw_amps/cabaret
   ffmpeg -i velvet.wav -af "pan=mono|c0=c0" -ar 44100 -c:a libvorbis -q:a 4 \
   	lw_amps_cabaret_velvet_l.ogg
   ffmpeg -i velvet.wav -af "pan=mono|c0=c1" -ar 44100 -c:a libvorbis -q:a 4 \
   	lw_amps_cabaret_velvet_r.ogg
   ```

   The files must be named `lw_amps_<name>_l.ogg` and `lw_amps_<name>_r.ogg`.
   Do not use `.1` / `.2`: Luanti reads `<name>.<digit>.ogg` as a random
   group and would play only one of the two. No FLAC, MP3 or WAV: the engine
   decodes Ogg Vorbis only.

2. **Measure the length.** Late arrivals are synced with
   `start_time = elapsed % length`, so the length has to come from the
   files, not from a guess:

   ```sh
   ffprobe -v error -show_entries format=duration -of csv=p=0 lw_amps_cabaret_velvet_l.ogg
   ```

3. **Register it**: add one line at the bottom of `songs.lua` in this folder:

   ```lua
   cabaret("cabaret_velvet", {title = "Velvet", length = 183.42, bpm = 112})
   ```

   `cabaret()` is a small helper in that file. It calls
   `lw_amps.register_song` with `media_dir = "cabaret"` (the files are in
   this folder) and `playlist = "cabaret"` (they belong to the cabaret's
   stage). It sets `artist` to Lace Waterfall unless you pass another.

4. **Restart the server.** On the web, rebuild and reload.

That is all. There is nothing to edit in `lw_maps`, `lw_dance` or the
routine:

* Walking into the cabaret plays the first song in `songs.lua` from its cabs,
  if nothing else is playing anywhere. Punching either cab stops it, or plays
  the first song again.
* `/amp list` lists every song and `/amp play <name>` plays any of them.
  Once the cabaret's cabs have been played from, they stay the amps until
  another stage is played.
* `routines/cabaret_revue.lua` picks up every song in the playlist when the
  server starts. Rubella and Lillith go on the cabaret stage, with four fans on
  the dance floor, and dance on the song's clock.

If a line's two files are not both here, that song is skipped and a warning
names the missing file in the log. A song registered without its files would
otherwise play silence with the band dancing to it.

## Why this folder and not `../sounds/`

Everything in a mod's `sounds/` folder is in the media list. Every client
downloads that list and checks its hashes before the world loads, and the
"Around" songs there are already about 26 MiB. This folder is not one the
engine collects media from. A cabaret song is sent with
`core.dynamic_add_media`, once per visitor, when that visitor first comes
within earshot of the cabaret's cabs. It is sent with `client_cache = false`,
so a browser does not also write it to IndexedDB. Visitors who never go to
the cabaret never download it. Until a listener's client has both files, that
listener is not started. Once it has them, the amps' once-a-second sweep
starts the pair in time with the song.

## The web download

That keeps the songs out of the engine's join-time media. The web build is a
separate matter: `src/CMakeLists.txt` preloads all of `games/luanti_web`
into `luanti.data`, the file every visitor downloads before the engine
starts. A song committed here adds its size to that file.

`luanti.data` is budgeted at about 40 MB and is already at about 38 MB (see
the content budget in `wasm_porting.md`). So:

* For the web build, keep the cabaret songs few and small: mono pairs at
  `-q:a 2` to `-q:a 4`, and say how much they add in the pull request.
* Or keep them out of the repository and copy them in only for the builds or
  servers that should have them. A native or dedicated server reads them from
  disk and sends them only to cabaret visitors.

## Rights

The recordings are their owners'. They are not covered by the LGPL that
covers the code. Note each song's source and licence here when you add it.
