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
                                                                 concert arena
 thunder chapel                                                  Around arena
 (north-northwest)                                              (north-northeast)
  | laser serpent -- smoke caldera  [ theater ]    z = 34..62    |    crystal bazaar -- mirror hall
  |  (west, via the   (northwest)       |                        |     (northeast)    (east, via the
  |   caldera's tube)  |                |                        |          |         arcade's end)
  |   |    [ library ]--[ courtyard ]--[ gallery ]   z = 4..32   |          |
  '---+----------------.    |    .-------------------------------'          |
                       |    |    |  .---------------------------------------'
 Halloween --------------[ plaza ]-------------- fruit garden -- Christmas village
   (west)            |       |     |                (east)       (east, off the end
                     |       |     '---------.                    of the garden's path)
 WoF Christmas       |  snow mountain        |
 (spur off the laser |    (south)  |         |
  serpent's south)   |             |         |
 lighthouse tide ----'             |         '--- rainbow storm
  (southwest)                      |              (southeast)
                          waterfall cascade
                       (far south, through the
                        mountain's tunnel)

 cabaret club (west-southwest): west of the lighthouse, by its own causeway
 from the plaza's south-west corner

 Weeks on Fire: the laser serpent is a spur off the smoke caldera, out of its
 basalt tube; the mirror hall is a spur off the crystal bazaar, out of the
 end of its arcade

 waterfall cascade: a spur off the snow mountain, out of the south mouth of
 its tunnel

 Christmas: the Christmas village is a spur off the fruit garden, off the
 east end of its path; the Weeks on Fire Christmas is a spur off the laser
 serpent, off the south side of its field
```

The plaza is the hub. The showcase tour runs north from it; ten causeways
leave it for the [themed maps](docs/maps.md) — straight out west, south and
east, and turning in the open water for the four diagonals, the arena, the
chapel and the cabaret club (west of the lighthouse, by a causeway from the
plaza's south-west corner), so none of them crosses the tour.

1. **Spawn plaza** — fountain, colonnade, and a gate whose banner spells
   `LUANTI WEB` out of wool. Walk north through the arch.
2. **Material library** (west) — every palette node on a labelled pedestal.
   Point at one to read its description and item name.
3. **Pixel-art gallery** (east) — three framed wool artworks, uplit, with a
   partition wall so each piece has its own wall.
4. **Kinetic courtyard** (centre) — an animated LED ticker wall, an animated
   water channel, a campfire, a node-timer light chase and hourglass, a cart
   and floating title card, and a six-frame living pavilion inside the cart
   loop. All engine-native: no shaders, no video.
5. **Theater** (north) — marquee, curtains, raked seating, and a 6x4 screen.
6. **Themed maps** (all round the plaza) — a dusk Halloween lane, a snowy
   mountain you can climb and tunnel through, a garden of giant fruit, a
   lighthouse on a blue-hour lagoon with a tunnel under it, a crystal bazaar at
   night with a dome you walk onto, a volcano you climb, look into and
   leave through its far side, a walk over rainbows in a thunderstorm, and
   Lace Waterfall's two arenas: the Around arena, where lights race round
   the truss and lasers sweep the floor, and beyond it the larger concert
   arena, where "Around" starts as you walk in and the band plays; a ruined
   chapel under a Halloween thunderstorm, where lightning strikes the spire
   and thunder rolls after it; and a cabaret club with a velvet stage where
   Rubella and Lillith perform. Two more islands are from Weeks on Fire: a
   laser serpent coiled on a night ash field, whose beams sweep the walk past
   it in a pattern you change at its console, and a mirror hall with a crystal
   skull under a vault of mirror tiles and a gallery of chasing crystals.
   Beyond the snow mountain, through its tunnel, is a waterfall cascade at
   misty twilight: five tiers of glowing falls under clouds hung with
   morning glories that shed petals, glowing mushrooms and trees, a volcano
   that erupts flowers, bikes to ride until they break down, and geodes that
   give gems you can fuse and push about. Two Christmas islands close the
   tour: a snowed-in village with a tree whose garland chases up it, presents,
   a workshop cabin with a fire, a sleigh and reindeer, beyond the fruit
   garden; and, beyond the laser serpent, a Weeks on Fire Christmas where the
   tree is on fire and festive anyway, lasers spiral up it, and a cabaret
   stage is set for a holiday revue. Walk a causeway or use `/maps`. Full
   footprints, spawns and intended time of day are in
   [`docs/maps.md`](docs/maps.md).

## Mods

| Mod | What it owns |
|-----|--------------|
| `lw_nodes` | the 45-node core palette (the theater adds 6 more) and the mapgen aliases |
| `lw_core` | the hand, privileges, the palette inventory, the starter kit |
| `lw_dance` | the player character mesh, dance mode, the six-move dance pad, the stage hint, the routine director that dances NPCs to the same catalog, and the Lace Waterfall band and crowd rigs |
| `lw_amps` | stage amp cabs that play a song as a left/right pair of positional mono sources, `/amp`, the song events the director dances to, map stages and playlists, and the cabaret's song slot (see `docs/amps.md`) |
| `lw_theater` | screen nodes, seats, marquee, the remote, both theater tiers |
| `lw_maps` | the themed map pack: its props, the map registry, the per-player atmosphere and storms (rain, lightning, thunder), the laser shows and their patterns, the HOA memo boards, the optional organ slot, `/maps` |
| `lw_cascade` | the waterfall cascade's bike racks and bikes (which break down, and are never saved), its geodes, the gems they give and fusing them, gems on the ground you can push, `/bike`, `/gems` |
| `lw_tools` | visitor authoring tools: Param2, paint, clone, light wand, schematic stamp, Laser Wand, Ember Tool |
| `lw_world` | the authored world and its schematics, stamped onto a singlenode mapgen; `/lw_schem` authoring tools |

## Controls worth knowing

* `i` opens the **palette inventory**: every node, paged, infinite. Taking from
  it never empties it.
* `/stuff` re-gives the starter kit, `/palette` reopens the palette.
* `/maps` lists the themed maps; `/maps halloween` travels to one.
* **Hold sneak+zoom** (`Shift`+`Z`) or `/dance` toggles **dance mode**. While it
  is on, the number keys are the moves — `1` groove, `2` spin, `3` wave,
  `4` stomp, `5` robot, `6` bow, `7` random, `8` stop — and your hotbar slot and
  wielded item come back when you leave. `/dance help` lists the binds,
  `/dance pad` opens a tap pad, and `F7` is how you watch yourself.
  Full details in [`docs/dance.md`](docs/dance.md).
* **Punch a Stage Director** — the violet post by the theater stage, at the back
  of the Halloween porch, and on the path by the melon bowl — to start a
  scripted routine, and punch it again to stop. `/routine list` shows them all,
  `/routine join` dances you along with one without taking a key off you.
  Full details in [`docs/routines.md`](docs/routines.md).
* **Param2 Tool** — punch/place nudge a node's param2 (+1 / -1, sneak for ±8). Same gestures as devtest's Param2 tool.
* **Paint Tool** — sneak+use samples a node; use stamps that type onto pointed nodes; right click cycles the wool palette.
* **Clone Stick** — left click pos1, right click pos2, sneak+left copy, sneak+right paste. Volume is capped at 32³.
* **Light Wand** — use places a hidden light; sneak+use or right click removes one.
* **Screen Remote** — the only item that talks to the theater. Left click next reel, sneak+left pause, right click play (browser video overlay, or the animated wall).
* **Schematic Stamp** — one-click seat row, column, or picture frame. Sneak+use cycles the stamp.
* **Laser Wand** — use fires a laser beam at the pointed node for 4 s; right click two nodes to string a beam between them for 12 s; sneak+use puts all your beams out. At most eight at a time per visitor, and none are saved.
* **Ember Tool** — use lights an ember on the pointed face. It burns, sputters and goes out by itself after about 7 s. Use it on an ember, or sneak+use, to put it out. No damage and no spread.
* Punch an **HOA memo** board (the laser serpent and the mirror hall each have one) to read the next notice. The two Christmas islands have red-and-green **holiday** boards with memos of their own.
* Punch the **serpent console** at the end of the laser serpent's walk to change the beams' pattern: coil, sweep, fan. The Weeks on Fire Christmas stage has one too: coil (up the tree) and sweep.
* On the **waterfall cascade**, punch or right click a **bike** at a bike rack to ride it: forward pedals, back brakes, jump hops, steer by looking, sneak to get off. Every bike breaks down after a while, and its rack takes 45 s to get another, so find the next rack. `/bike` shows how your ride is going, or where the nearest bike is.
* Dig a **geode** on the waterfall cascade for a red, yellow or blue **gem**. Right click with a gem to fuse it with one in your pockets (red + yellow = orange, and so on, up to a prism), or drop gems with `Q` and punch or walk them into each other to fuse them on the ground. Right click a gem on the ground to pick it up. `/gems` lists the recipes.
* Punch the red reel button on the east theater pedestal to cycle reels without opening the inventory.
* Right click a theater seat to sit in it facing the screen (or `/sit` anywhere). Jump to stand up.
* Punch a chandelier to dim or raise the house lights.
* `/reel off|title|show|bars` switches the screen from chat, and brings the house
  lights back up when it is off.

Fly, fast and noclip are on for everyone. There is no damage, no hunger, no
combat and no crafting: the cascade's gems fuse by right click or on the
ground, not in a craft grid.

Visitors have a body: `lw_dance` gives the player the classic character mesh,
which is what `set_animation` and the dance poses act on (and what the theater
seats were already written for). The same mesh, driver and move catalog run the
scripted dancers, so a visitor can fall in step with a routine instead of
watching one.

## The theater, in tiers

**Tier A — animated tiles (everywhere, including native builds).** The screen is
a wall of 24 nodes. Each node owns one cell of the picture and animates through
that cell's own filmstrip, so the wall shows a single large moving image rather
than 24 copies of a thumbnail. Three reels ship: a looping film-leader title
card, a sunrise clip, and a broadcast test pattern. Fresh worlds start on the
title card so walking in shows motion with no JavaScript. House lights follow
the remote, the wall button, and the chandeliers. A short `.ogg` sting plays
when a reel starts if sound is compiled in, and degrades to silence otherwise.

**Tier B — HTML5 video overlay (browser only).** Luanti cannot bind an MP4 to a
node tile, but the WASM client's page owns a real `<video>` element. The remote
calls `core.set_web_video{clip = "..."}`, which exists only under Emscripten;
`client/web/theater.js` raises the element over the canvas, releases pointer
lock so its controls are clickable, and hands pointer lock back on close.

Clips are fetched at runtime from `media/` on the page's own origin and are
never baked into an asset package; see `client/web/media/README.md`. If the clip is
missing, the API is absent (native build, or a remote server), or the browser
refuses to decode, Tier A keeps playing and the visitor still sees motion on the
wall.

## Regenerating the art

Every texture, the menu art and the shared pixel font are generated:

```sh
python3 util/content/generate_luanti_web_textures.py
```

That covers the Lace Waterfall band and crowd skins as well (64×32, in the
character mesh's layout) and the amp cabs. The one texture it does not generate
is the player skin `lw_dance_character.png`, which is devtest's Sam.

It uses only the Python standard library and is deterministic — running it on an
unchanged tree produces an empty diff. Sizes, cell counts and frame counts are
constants at the top of that script and are mirrored by
`lw_theater/init.lua`; change them together.

Frame-strip authoring from real footage (ffmpeg → vertical PNG), including the
exact `tile=1x16` recipe the theater cells expect, is in
[`docs/filmstrips.md`](docs/filmstrips.md). The short form:

```sh
ffmpeg -y -i clip.mp4 \
	-vf "fps=12,scale=32:32:flags=neighbor,tile=1x24" \
	-frames:v 1 strip.png
```

The living pavilion's six schematic frames and the themed maps are
generated separately:

```sh
python3 util/content/generate_luanti_web_living.py
python3 util/content/generate_luanti_web_maps.py
```

## Editing the world

The world is not a committed map database. It is stamped onto a singlenode
mapgen from two sources, both in git, the first time each chunk is generated:

* `lw_world/init.lua` — a build order of box operations, plus everything
  derived from data: the lettering, the pixel art, the library pedestals.
* `lw_world/schems/*.mts` — buildings authored in game: the theater (seats,
  raked floor, screen and all), the plaza fountain, the colonnade column, the
  gallery frame, and the six living-pavilion frames. `init.lua` says where
  each one goes with `schem()`.
* `lw_world/maps.lua` — the atlas: the themed islands in one sea, the
  causeways out of the plaza and the gates at the hub end. It reads the
  registry in `lw_maps` for each map's footprint and spawn, and places
  `schems/map_*.mts` (generated, not hand-authored) the same way. See
  [`docs/maps.md`](docs/maps.md).

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
`worldmods/` on a native build. Bundling it would add it to the `luanti_web` package for
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
