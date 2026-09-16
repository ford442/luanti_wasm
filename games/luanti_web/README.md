<!--
Luanti
SPDX-License-Identifier: LGPL-2.1-or-later
Copyright (C) 2026 The Luanti Contributors
-->

# Luanti Web Showcase

The default game for the browser client. A first-time visitor should land in a
designed space, not in raw mapgen wilderness, and should be able to walk the
whole thing in about a minute.

`games/devtest` is still in the tree and still selectable — it is the engine's
QA sandbox and this game is not a replacement for it.

## The tour

```
             [ theater ]                 z = 34..62
                  |
 [ library ]--[ courtyard ]--[ gallery ]   z = 4..32
                  |
             [ plaza ]                    z = -18..4   (spawn at 0, 10, -14)
```

1. **Spawn plaza** — fountain, colonnade, and a gate whose banner spells
   `LUANTI WEB` out of wool. Walk north through the arch.
2. **Material library** (west) — every palette node on a labelled pedestal.
   Point at one to read its description and item name.
3. **Pixel-art gallery** (east) — three framed wool artworks, uplit, with a
   partition wall so each piece has its own wall.
4. **Kinetic courtyard** (centre) — an animated LED ticker wall, an animated
   water channel, a node-timer light chase, and a cart entity on a plank loop.
   All engine-native: no shaders, no video.
5. **Theater** (north) — marquee, curtains, raked seating, and a 6x4 screen.

## Mods

| Mod | What it owns |
|-----|--------------|
| `lw_nodes` | the 45-node palette and the mapgen aliases |
| `lw_core` | the hand, privileges, the palette inventory, the starter kit |
| `lw_theater` | screen nodes, seats, marquee, the remote, both theater tiers |
| `lw_world` | the authored world, stamped onto a singlenode mapgen |

## Controls worth knowing

* `i` opens the **palette inventory**: every node, paged, infinite. Taking from
  it never empties it.
* `/stuff` re-gives the starter kit, `/palette` reopens the palette.
* **Screen Remote** — left click cycles the theater reel, right click raises the
  browser video overlay (web client only).
* Right click a theater seat to sit in it facing the screen.
* `/reel off|bars|show` switches the screen from chat, and brings the house
  lights back up when it is off.

Fly, fast and noclip are on for everyone. There is no damage, no hunger, no
combat and no crafting.

## The theater, in tiers

**Tier A — animated tiles (everywhere, including native builds).** The screen is
a wall of 24 nodes. Each node owns one cell of the picture and animates through
that cell's own filmstrip, so the wall shows a single large moving image rather
than 24 copies of a thumbnail. Two reels ship: a broadcast test pattern and a
short sunrise loop. This needs no JavaScript and no video decoder.

**Tier B — HTML5 video overlay (browser only).** Luanti cannot bind an MP4 to a
node tile, but the WASM client's page owns a real `<video>` element. The remote
calls `core.set_web_video{clip = "..."}`, which exists only under Emscripten;
`client/web/theater.js` raises the element over the canvas, releases pointer
lock so its controls are clickable, and hands pointer lock back on close.

Clips are fetched at runtime from `media/` on the page's own origin and are
never baked into `luanti.data`; see `client/web/media/README.md`. If the clip is
missing, the API is absent (native build, or a remote server), or the browser
refuses to decode, Tier A keeps playing and the visitor still sees motion on the
wall.

## Regenerating the art

Every texture, the menu art and the shared pixel font are generated:

```sh
python3 util/content/generate_luanti_web_textures.py
```

It uses only the Python standard library and is deterministic — running it on an
unchanged tree produces an empty diff. Sizes, cell counts and frame counts are
constants at the top of that script and are mirrored by
`lw_theater/init.lua`; change them together.

To author a new filmstrip from real footage, produce a vertical strip of square
frames, which is what `vertical_frames` expects:

```sh
ffmpeg -i clip.mp4 -vf "fps=12,scale=32:32" -frames:v 16 frame%02d.png
magick montage frame*.png -tile 1x16 -geometry +0+0 strip.png
```

## Editing the world

The world is not a committed map database. `lw_world/init.lua` holds a list of
box operations and stamps them into each chunk the first time it is generated,
so an edit to that file changes the landing world on the next *fresh* world.
An existing world keeps whatever was already generated — delete it, or visit
new chunks, to see changes.

World-wide defaults live in `minetest.conf` next to `game.conf`: the spawn point
(`0,10,-14`, on the plaza) and `time_speed = 0`, which freezes the clock at
midday. The engine loads that file as the game settings layer, so it never leaks
into the user's own configuration or into other games. Mods must not use
`core.settings:set()` for per-game defaults: the client writes that layer back
to the user's `minetest.conf` on exit.

Every visitor gets `fly`, `fast` and `noclip` on join, but the tour never needs
them: the plaza, the courtyard bridges, both side doors and the theater ramp
are all reachable on foot.

In the browser the launcher selects this game by default, and the world is
created at `/home/web_user/.luanti/worlds/luanti_web` on IDBFS, so it survives
a hard reload. `util/wasm/test_first_playable.py` enters this world for steps
5-7 of the First Playable Smoke Test.

### Exporting

`/lw_export` (needs the `server` privilege, which singleplayer has) generates
the whole showcase area and writes it to `<world>/schems/lw_showcase.mts`. Use
it to snapshot edits made in game, then fold them back into the op list here —
the export is an artifact for diffing and for the schematic pipeline, not
something `lw_world` loads. Run it from a native build if you want the file on
disk; in the browser it lands on IDBFS.

Adding a node to `lw_nodes` with the `lw_palette` group is enough to get it a
labelled pedestal in the material library; the room is built from the group, not
from a hardcoded list. It logs a warning if the palette outgrows the 48
pedestals.
