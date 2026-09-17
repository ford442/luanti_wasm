<!--
Luanti
SPDX-License-Identifier: LGPL-2.1-or-later
Copyright (C) 2026 The Luanti Contributors
-->

# Frame-strip authoring (Theater Tier A)

Luanti's `vertical_frames` animation is a **single PNG**: N square frames
stacked top to bottom. The theater screen, the courtyard ticker, the campfire
and the water channel all use this layout. There is no atlas, no sprite sheet
in rows-and-columns, and nothing GLES2-unfriendly.

```
+--------+
| frame 0|   height = aspect_h
+--------+
| frame 1|
+--------+
|  ...   |
+--------+
| frame N-1
+--------+
 width = aspect_w
```

The node definition names the strip and the size of one frame:

```lua
tiles = {{
	name = "lw_screen_show_0_0.png",
	animation = {
		type = "vertical_frames",
		aspect_w = 32,   -- one cell
		aspect_h = 32,
		length = 24 / 12, -- frames / fps
	},
}}
```

Keep strips small. The showcase budget is 16×16 tiles (8–16 frames) for
world nodes and 32×32 cells (24 frames) for the cinema wall. A 512×512 source
decoded onto one node will hitch the WASM worker for no visual gain. Whole-frame
footage at 256×144 should be scaled to 192×128 (6×32 by 4×32) and sliced; do
not bind one 256-wide strip to every cell.

## ffmpeg: clip → vertical strip

`ffmpeg`'s `tile` filter *is* the montage. One command:

```sh
# 24 frames at 12 fps, 32×32 cells — the theater reel contract.
ffmpeg -y -i clip.mp4 \
	-vf "fps=12,scale=32:32:flags=neighbor,tile=1x24" \
	-frames:v 1 strip.png
```

`tile=1x16` means 1 column and 16 rows, i.e. a vertical strip. `flags=neighbor`
keeps pixel-art edges; drop it for photographic footage (the default bilinear
scale is then correct).

Other sizes used in this game:

| Surface | Command fragment | `aspect_*` / `length` |
|---------|------------------|------------------------|
| Theater cell | `fps=12,scale=32:32,tile=1x24` | 32 / 24÷12 |
| Water | `fps=8,scale=16:16,tile=1x8` | 16 / 8÷8 = 1.0… the shipped strip uses length 2.0 |
| Fire | `fps=8,scale=16:16,tile=1x8` | 16 / 1.0 |
| LED ticker | `fps=10,scale=16:16,tile=1x16` | 16 / 1.6 |

To take the first N frames of a longer clip, add `-frames:v 1` after `tile`
(the filter already collapsed the stream to one image) and cap the input with
`-t`:

```sh
ffmpeg -y -t 2.0 -i clip.mp4 \
	-vf "fps=12,scale=32:32:flags=neighbor,tile=1x24" \
	-frames:v 1 strip.png
```

2.0 s × 12 fps = 24 frames.

## ffmpeg + ImageMagick (when `tile` is unavailable)

```sh
mkdir -p /tmp/frames
ffmpeg -y -i clip.mp4 -vf "fps=12,scale=32:32:flags=neighbor" -frames:v 24 \
	/tmp/frames/frame%02d.png
magick montage /tmp/frames/frame*.png -tile 1x24 -geometry +0+0 strip.png
```

`convert` (ImageMagick 6) is the same binary as `magick montage` on older
distros.

## Slicing a large picture into theater cells

Tier A is a **6×4 wall**. Each node owns one cell of the picture and animates
through that cell's own strip, so the wall shows one moving image instead of
24 copies of a thumbnail.

The shipped reels are produced by
`util/content/generate_luanti_web_textures.py` (`reel_cell_strips()`). Prefer
that path for anything that should stay deterministic in git. Use ffmpeg when
the source is real footage: build one 192×128 frame (6×32 by 4×32), stack 24
of those into a 192×3072 strip, then crop each 32×3072 column-slice and each
32-pixel row of that column into a per-cell filmstrip. The Python helper already
does the bookkeeping; duplicating it as a nested ffmpeg crop is how cells
drift out of sync with `SCREEN_COLS` / `SCREEN_ROWS`. The shipped reels are
procedural (a film-leader countdown, a sunrise loop, a test pattern) rather
than a baked MP4, which keeps the generator deterministic and the WASM texture
budget small.

Constants that must stay in sync:

| Name | Value | Files |
|------|-------|-------|
| `SCREEN_COLS` | 6 | `generate_luanti_web_textures.py`, `lw_theater/init.lua` |
| `SCREEN_ROWS` | 4 | same |
| `CELL` | 32 | same |
| `REEL_FRAMES` | 24 | same |
| fps | 12 | `length = FRAMES / FPS` in `lw_theater` |

## What not to do

* Horizontal strips (`tile=16x1`). The engine will read them as one very
  wide frame and the animation will not play.
* Atlases larger than the cell. WebGL has to upload the whole strip for
  every node that uses it; 24 nodes × a 1024-tall strip is how the canvas
  stalls.
* `sheet_2d` animations. They work on desktop OpenGL and are not the
  path this port has budgeted for.
* MP4 on a node tile. That is Theater Tier B (`core.set_web_video`), a
  browser overlay, not an engine texture.

## Regenerating the shipped art

```sh
python3 util/content/generate_luanti_web_textures.py
```

No ffmpeg required. The script writes vertical filmstrips with the Python
standard library and is deterministic: rerunning it on an unchanged tree
produces an empty diff.
