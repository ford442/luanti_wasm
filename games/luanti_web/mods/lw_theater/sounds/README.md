<!--
Luanti
SPDX-License-Identifier: LGPL-2.1-or-later
Copyright (C) 2026 The Luanti Contributors
-->

# Theater reel sting

`lw_reel.ogg` is a short, original projector-start tone played when a Tier A
reel begins. It is not a soundtrack and it is not required: `lw_theater`
feature-detects `core.sound_play` and degrades to a silent wall when OpenAL is
missing, the file is missing, or WASM sound (#8) is not ready.

Regenerate (mono Vorbis, under 12 KiB):

```sh
mkdir -p games/luanti_web/mods/lw_theater/sounds
ffmpeg -y \
	-f lavfi -i "sine=frequency=90:duration=1.6:sample_rate=22050" \
	-f lavfi -i "sine=frequency=1760:duration=0.07:sample_rate=22050" \
	-filter_complex \
	"[0]volume=0.35,afade=t=in:d=0.05,afade=t=out:st=1.2:d=0.4[a]; \
	 [1]adelay=80|80,volume=0.22[b]; \
	 [a][b]amix=inputs=2:duration=longest[out]" \
	-map "[out]" -c:a libvorbis -q:a 0 -ac 1 \
	games/luanti_web/mods/lw_theater/sounds/lw_reel.ogg
```
