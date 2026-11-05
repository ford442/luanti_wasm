<!--
Luanti
SPDX-License-Identifier: LGPL-2.1-or-later
Copyright (C) 2026 The Luanti Contributors
-->

# Lace Waterfall — "Around"

The song the stage amps play, and the one the Lace Waterfall band and crowd
dance to (`games/luanti_web/routines/lace_waterfall_around.lua`). There are seven
mixes: the main "happy hard" mix and six alternate takes.

| Song (`/amp play <song>`) | Length |
|---------------------------|--------|
| `around_happy_hard`       | 159.02 s |
| `around_happy_hard_1`     | 199.33 s |
| `around_happy_hard_2`     | 152.23 s |
| `around_happy_hard_3`     | 162.84 s |
| `around_happy_hard_4`     | 152.93 s |
| `around_happy_hard_5`     | 155.52 s |
| `around_happy_hard_6`     | 160.46 s |

All of them are 175 bpm. The lengths in `lw_amps/init.lua` are measured from
these files. Late arrivals are synced with `start_time = elapsed % length`, so
if a file is replaced, its length has to be re-measured too:

```sh
ffprobe -v error -show_entries format=duration -of csv=p=0 lw_amps_around_happy_hard_l.ogg
```

## Source and rights

The original MP3s and the ogg conversions were supplied by the repository owner
for this showcase. The rights to the recording belong to its owner. These files
are **not** covered by the LGPL that covers the code. The licence for
redistributing them is still to be confirmed by the rights holder; do not reuse
them outside this pack until it is.

## Why `songs/` and not `sounds/`

Everything in a mod's `sounds/` is game media: the server hashes it at
start-up and every client is told about it on join, whether or not a song
ever plays. These files are kept here instead and sent on demand by
`lw_amps` with `core.dynamic_add_media` (see the top of `../init.lua`), so
only a visit to the concert arena pays for them. Do not move them back, and
put any future song (or a lossless experiment) here too.
`util/content/test_luanti_web_amps.py` fails if a song file turns up under a
media folder.

## Why two mono files per song

Luanti only places a sound in the world if it is a single-channel Ogg Vorbis.
A stereo file is played with no position at all, and the engine warns
"Creating positional stereo sound". So every song is split into its two
original channels, and each channel plays from its own cab:

* `lw_amps_<song>_l.ogg` is the original **left** channel only. It plays from
  the **audience-left** cab.
* `lw_amps_<song>_r.ogg` is the original **right** channel only. It plays from
  the **audience-right** cab.

Levels are not cut by 6 dB. Both files of a pair are the same length. L−R is
not silence, so the stereo image is still there when you stand between the
cabs.

The files are named `_l` / `_r` and not `.1` / `.2`. Luanti treats
`<name>.<digit>.ogg` as a random sound group and would play only one file of
the pair. The `lw_amps_` prefix is the mod's own: sound `lw_amps_<song>_l` is
the file `lw_amps_<song>_l.ogg`.

Regenerate from a stereo master (Vorbis q6, 44.1 kHz):

```sh
ffmpeg -i around_happy_hard.mp3 -af "pan=mono|c0=c0" -ar 44100 -c:a libvorbis -q:a 6 \
	lw_amps_around_happy_hard_l.ogg
ffmpeg -i around_happy_hard.mp3 -af "pan=mono|c0=c1" -ar 44100 -c:a libvorbis -q:a 6 \
	lw_amps_around_happy_hard_r.ogg
```

Do **not** downmix to `(L+R)/2` on both channels of a stereo file. That
centres the bed, but it throws away the stereo difference, and Luanti still
will not place a stereo file on the amps.

## Budget

The 14 files are about 26 MiB, which is most of what the web pack downloads
before the first frame (the build still preloads the whole game folder into
`luanti.data`; they are only kept out of the media set). See the content budget in `wasm_porting.md` (it was
raised for these) and `util/content/test_luanti_web_amps.py`, which fails the
build past 30 MiB.
