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
| `lw_nodes` | the 45-node core palette (the theater adds 4 more) and the mapgen aliases |
| `lw_core` | the hand, privileges, the palette inventory, the starter kit |
| `lw_theater` | screen nodes, seats, marquee, the remote, both theater tiers |
| `lw_world` | the authored world and its schematics, stamped onto a singlenode mapgen; `/lw_schem` authoring tools |

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

The world is not a committed map database. It is stamped onto a singlenode
mapgen from two sources, both in git, the first time each chunk is generated:

* `lw_world/init.lua` — a build order of box operations, plus everything
  derived from data: the lettering, the pixel art, the library pedestals.
* `lw_world/schems/*.mts` — buildings authored in game: the theater (seats,
  raked floor, screen and all), the plaza fountain, the colonnade column, and
  the gallery frame. `init.lua` says where each one goes with `schem()`.

An edit to either changes the landing world on the next *fresh* world. An
existing world keeps whatever was already generated — delete it, visit new
chunks, or `/lw_schem place <name>` to see changes.

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

### Buildings as schematics

**Source of truth: `.mts`, through the engine's own schematic API.** It needs no
mod to load, keeps `param2` (so a seat stays facing the screen), supports "never
place" nodes (so a frame does not erase the art inside it), and is small: the
whole theater is under 1 KB. WorldEdit's `.we` is not used — reading it back
would make WorldEdit a runtime dependency of the demo. `.mts` does not store
node metadata, so infotext stays in `init.lua` as `label()` calls, and
`lw_world` runs `on_construct` for stamped nodes itself (the chase light needs
it to start its timer).

Everything below needs the `server` privilege, which the singleplayer host has.

| Command | Does |
|---------|------|
| `/lw_schem wand` | gives the Schematic Wand: left click a node = pos1, right click = pos2 |
| `/lw_schem pos1`, `pos2` | set a corner to where you stand |
| `/lw_schem save <name> [skip=air,group:x]` | write the selection to `<world>/schems/<name>.mts`; `skip` nodes become "never place" |
| `/lw_schem save <name>` | with no selection, for a piece `init.lua` places: re-export its own footprint and skip list |
| `/lw_schem place <name>` | stamp the committed file over every placement of that piece in *this* world, edits included |
| `/lw_schem list` | pieces, their sizes and placement counts, and this world's exports |

From Lua, `lw_world.schems.save(p1, p2, name, skip, done)` does the same as the
chat command.

**Edit an existing building** (e.g. the theater):

1. Run a native build (`./bin/luanti`), enter a `luanti_web` world, change the
   theater.
2. `/lw_schem save theater`
3. `cp <world>/schems/theater.mts games/luanti_web/mods/lw_world/schems/`
4. Review with `git diff` (see below) and commit. A fresh world has the change.

**Add a new building:** build it, select it with the wand, `/lw_schem save
<name>`, copy the file into `schems/`, and add `schem(x, y, z, "<name>")` to the
right `build_*` function in `init.lua`. Its position in the build order matters:
later ops overwrite it, and it overwrites earlier ones. A missing or unreadable
file is a load-time error, not a hole in the world.

In the browser the export lands on IDBFS, not on your disk, so author on a
native build.

**Reviewing a schematic change.** `.gitattributes` routes `*.mts` through a text
dump; enable it once per clone:

```sh
git config diff.mts.textconv "python3 util/content/mts_to_text.py"
```

`git diff` then shows each layer as a character map, so moving one seat is a
one-line diff. The script also runs on its own.

**WorldEdit** is fine for authoring — `//pos1`, `//pos2`, `//mtschemcreate
<name>` writes the same format to the same `<world>/schems/` directory — but it
is not part of this game and must not become one. Put it in the author world's
`worldmods/` on a native build. Bundling it would add it to `luanti.data` for
every visitor, and `worldedit_gui` expects an inventory mod (Unified Inventory,
sfinv) that this game does not ship. If an
in-game editor is ever preloaded, keep it to a dedicated author world.

`/lw_export` snapshots the whole showcase area to
`<world>/schems/lw_showcase.mts`, for diffing a world against a fresh one. It is
not loaded by anything.

Adding a node to `lw_nodes` with the `lw_palette` group is enough to get it a
labelled pedestal in the material library; the room is built from the group, not
from a hardcoded list. It logs a warning if the palette outgrows the 54
pedestals.
