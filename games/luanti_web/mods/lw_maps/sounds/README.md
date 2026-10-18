<!--
Luanti
SPDX-License-Identifier: LGPL-2.1-or-later
Copyright (C) 2026 The Luanti Contributors
-->

# Lighthouse lamp sting

`lw_lighthouse.ogg` is a short, original horn played when the lantern-room
lamp is punched. It is not a soundtrack and it is not required: `lw_maps`
feature-detects `core.sound_play` and stays silent when OpenAL is missing or
the file is missing.

Regenerate (mono Vorbis, under 8 KiB):

```sh
mkdir -p games/luanti_web/mods/lw_maps/sounds
ffmpeg -y \
	-f lavfi -i "sine=frequency=110:duration=0.9:sample_rate=22050" \
	-f lavfi -i "sine=frequency=165:duration=0.9:sample_rate=22050" \
	-f lavfi -i "sine=frequency=880:duration=0.05:sample_rate=22050" \
	-filter_complex \
	"[0]volume=0.4,afade=t=in:d=0.02,afade=t=out:st=0.55:d=0.35[a]; \
	 [1]volume=0.22,afade=t=in:d=0.04,afade=t=out:st=0.5:d=0.4[b]; \
	 [2]adelay=20|20,volume=0.12[c]; \
	 [a][b][c]amix=inputs=3:duration=longest[out]" \
	-map "[out]" -c:a libvorbis -q:a 0 -ac 1 \
	games/luanti_web/mods/lw_maps/sounds/lw_lighthouse.ogg
```

# Thunder

`lw_thunder.1.ogg`, `lw_thunder.2.ogg` and `lw_thunder.3.ogg` are the thunder
chapel's (`halloween_storm`) thunder. Each one is an original, synthesised
roll of thunder: a short crack, then brown-noise rumble, 2.4 to 2.8 s, mono,
about 8 KiB. The three of them come to under 24 KiB of join-time media.

Together they are one sound, `lw_thunder`. Luanti reads `<name>.<digit>.ogg`
as a random group and picks one file each time, so no two strikes have to
sound the same. `lw_maps` plays one positionally at the rod a bolt hits,
0.25 to 1.5 s after the flash depending on how far the visitor stands from
it, and only to that visitor. As with the lighthouse horn, a build without
OpenAL, or a browser whose audio has not been unlocked by a click or a key
yet, gets a silent storm instead of an error.

Each file is under 3 s, so the engine decodes it whole rather than streaming
it (`SOUND_DURATION_MAX_SINGLE` in `src/client/sound/sound_constants.h`).

Regenerate (mono Vorbis, deterministic):

```sh
cd games/luanti_web/mods/lw_maps/sounds
# variant  length  seed  rumble cutoff (Hz)  crack delay (s)
for spec in "1 2.6 11 380 0.05" "2 2.8 23 300 0.12" "3 2.4 37 460 0.02"; do
	set -- $spec
	ffmpeg -v error -y \
		-f lavfi -i "anoisesrc=color=brown:duration=$2:sample_rate=22050:seed=$3" \
		-f lavfi -i "anoisesrc=color=pink:duration=0.35:sample_rate=22050:seed=$3" \
		-filter_complex \
		"[0]lowpass=f=$4,lowpass=f=$4,volume=1.6,afade=t=in:st=$5:d=0.15, \
		  afade=t=out:st=0.5:d=$(echo "$2 - 0.5" | bc):curve=exp[rumble]; \
		 [1]highpass=f=900,volume=0.3,adelay=$(echo "$5 * 1000 / 1" | bc), \
		  afade=t=out:st=0.02:d=0.3[crack]; \
		 [rumble][crack]amix=inputs=2:duration=longest:normalize=0, \
		  alimiter=limit=0.7:level=disabled[out]" \
		-map "[out]" -c:a libvorbis -q:a -1 -ac 1 \
		-map_metadata -1 -fflags +bitexact -flags:a +bitexact \
		lw_thunder.$1.ogg
done
```

The chapel's optional pipe-organ soundtrack does **not** go in this folder:
see `../organ/README.md`.
