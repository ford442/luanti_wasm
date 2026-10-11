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
