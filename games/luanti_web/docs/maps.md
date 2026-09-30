<!--
Luanti
SPDX-License-Identifier: LGPL-2.1-or-later
Copyright (C) 2026 The Luanti Contributors
-->

# The themed maps

Four authored maps ship with the showcase pack, as islands around the hub
plaza. They are design pieces, not procedural terrain: each one is a single
committed schematic, compact enough for the WASM heap and short enough to walk
in about three minutes.

```
                        [ hub tour ]            north of the plaza
                             |
        [ Halloween ]---[ hub plaza ]---[ fruit garden ]
             west          |    |            east
                           |  [ snow mountain ]
                           |       south
       [ lighthouse ]------'
         southwest
```

Every causeway is walkable. Fly, fast and noclip are on for everyone, but the
tour never needs them.

## The maps

| Map | `id` | Schematic | Footprint (`size`) | Origin (min corner) | Spawn | Time of day |
|-----|------|-----------|--------------------|---------------------|-------|-------------|
| Halloween lane | `halloween` | `map_halloween.mts` | 36 × 20 × 36 | `(-88, 5, -26)` | `(-55, 9, -9)` | dusk (`day_night_ratio = 0.16`, fogged sky) |
| Snowy mountain | `snow_mountain` | `map_snow_mountain.mts` | 40 × 28 × 40 |  `(-20, 5, -74)` | `(6, 9, -37)` | bright overcast (`0.85`, pale sky) |
| Giant fruit garden | `fruit_garden` | `map_fruit_garden.mts` | 40 × 20 × 40 | `(53, 5, -28)` | `(55, 9, -7)` | the world's own midday |
| Lighthouse tide | `lighthouse_tide` | `map_lighthouse_tide.mts` | 36 × 24 × 36 | `(-66, 5, -80)` | `(-39, 9, -46)` | late blue hour (`0.28`, dark water sky, light fog) |

Local `y = 0` of every map schematic is stamped at world `y = 5`
(`lw_maps.base_y`), so local `y = 3` is the world's `GROUND` and local `y = 4`
its `FLOOR` — the same two levels the rest of the showcase is built on.

**Time of day is per player, not per world.** The hub's clock is frozen at
midday (`time_speed = 0` in `minetest.conf`), and freezing it somewhere else
would move the whole world. Instead `lw_maps` watches where each player is and
calls `override_day_night_ratio` and `set_sky` when they cross onto a map, and
resets both when they leave. That is what lets a dusk lane and a bright garden
exist in one world at the same time, and it costs nothing while nobody is on a
map.

The reset is `player:set_sky()` with no argument. `set_sky({})` looks like a
reset and is not one: the engine starts from the player's current sky and
changes only the fields the table names, so an empty table changes nothing and
a lane's fog would follow the visitor home.

### Halloween lane

A lantern-lit lane from the causeway to a porch stage, with a pumpkin patch to
the south and a graveyard and a haunted house to the north.

* The house has a hallway straight through from the front door, side rooms with
  lit windows, an attic up a plank stair, and a cellar down another — three
  levels in fourteen nodes of footprint.
* Lanterns gutter: `lw_maps:flicker` is an airlike node timer that swaps the
  jack-o'-lantern below it for an unlit pumpkin on a fixed pattern, phase-offset
  by position so the lane does not blink in unison. Dig the lantern out and the
  controller leaves the hole alone.
* A weather vane spins on the house ridge (`lw_maps:weather_vane`, an entity
  with `static_save = false`).
* No mobs. The theme is lighting, silhouette and fog.

### Snowy mountain

A flat-topped cone you can climb *and* go through.

* **Up:** a spiral shelf cut into the cone, one node of rise every four steps,
  from the trailhead to a railed overlook on the summit plateau.
* **Through:** a tunnel at trail level runs north–south under the peak and
  comes out on the far face, with a portal and a slab ramp at each mouth.
* **Ice cave:** blue glass walls and a packed-ice floor, with its own mouth on
  the west face and a link east into the through-tunnel.
* **Mineshaft:** a timbered stair climbing from the through-tunnel up to a mouth
  on the trail. Its exit is not a hard-coded position: the generator picks
  whichever tread of the spiral is nearest, so the shaft still meets the trail
  if the cone's slope ever changes.
* Lighting is `lw_maps:torch` (light 12) every few nodes, not ceiling lamps, so
  the caves read as caves.

### Giant fruit garden

Oversized produce as architecture.

* A **walk-in watermelon**, 13 × 11 × 13: striped rind, a course of flesh, seed
  blocks, a hollow room with a doorway on the path side and hidden lights
  inside.
* A **sliced melon** set into the lawn as an amphitheatre: terraces that step
  one node every 2.2 of radius, seeds pressed into them, and two pairs of
  theater seats.
* Giant apple, grape cluster under a canopy, banana, citrus and strawberry.
* A juice channel of translucent nodes from the bowl to a basin.

Every fruit here is dyed wool from the core palette. The map adds no fruit
nodes at all.

### Lighthouse tide

A lagoon at blue hour, with land round three sides of it: the causeway lands on
the north shore, a spine runs down the west side to a headland with the
lighthouse on it, and a rocky ledge runs down the east side.

* **The lighthouse** is a hollow shell, thirteen nodes across, painted in
  bands of white and red. A spiral stair winds round a solid core from the
  door to the lantern: a helicoid, one rise every few treads, each turn four
  nodes above the last, and stair nodes wherever a tread has the next one up
  beside it, so the climb is half steps. The last two rises come up through a
  hatch in the gallery rather than through the lantern's floor.
* **The lantern room** is a ring of glass on the gallery deck with a door on
  the seaward side and the lamp in the middle. The beam is one entity
  (`lw_maps:lighthouse_beam`): a long glowing translucent sprite that turns
  about the lamp, `static_save = false` like the Halloween vane.
* **The jetty** stands on piles one node proud of the lagoon, with two tide
  pools set into its deck: water on glass, so you look straight down into the
  lagoon.
* **The tunnel** runs along the lagoon bed from a stairwell on the west spine,
  under the lagoon and under the jetty, to a stairwell on the east ledge — the
  far side of the jetty. Its walls and roof are glass wherever there is water
  outside them, and the first tide pool's glass floor is its roof, so from the
  tunnel you look up into the pool and from the jetty down into the tunnel.
  The lagoon's surface is level with the shore, so a visitor's head in the
  tunnel is below the waterline.

No boats, no flowing water, no mobs: the water is the pack's still
`lw_nodes:water`, and the map adds no nodes.

## Getting there

* Walk. A causeway leaves the plaza for every map, each with a gate whose
  posts are topped with something from the map it points at, and a poster that
  says what is over there. The islands sit in one sea, so between them there is
  water rather than a view of the void.
* `/maps` lists the maps; `/maps <id>` travels to one. It emerges the area
  around the spawn first and moves the visitor only once that is done, because
  the islands are far enough out that a visitor moved straight away can arrive
  before the chunk does and fall through the place it will be.

The islands are placed when their chunks are first generated, like the rest of
the showcase, so an island added to the pack appears in worlds created after
it. A world that already generated that stretch of sea keeps it;
`/lw_schem place map_<id>` stamps the committed schematic there anyway.

## Editing them

The maps are generated, not authored in game:

```sh
python3 util/content/generate_luanti_web_maps.py
python3 util/content/generate_luanti_web_maps.py --dump map_halloween   # character map
```

It is deterministic and uses only the standard library, like every other asset
in the pack; rerunning it on an unchanged tree produces an empty diff.

Geometry is why: the maps are cones, ellipsoids and a helical ramp, and doing
that arithmetic once at build time keeps it off the browser's application
worker, where chunk generation competes with the compositor. `.mts` is the
committed form because it keeps `param2` (a theater seat still faces the stage)
and compresses the three maps to under 7 KiB.

Once they are stamped into a world, `/lw_schem place map_halloween` puts the
committed file back over an existing world, the same as any other piece.

`util/content/test_luanti_web_maps.py` flood-fills each map from its spawn
under a player's movement rules and asserts that every landmark is standable
and connected — the tunnel mouths, the cellar, the attic, the summit, the
inside of the watermelon. If a change walls off a route, that test says so.

## Adding a map

A new map is a generator function and a registry row; nothing else in the pack
has to learn about it. In order:

1. **Generator.** Write `build_<name>() -> Build` in
   `util/content/generate_luanti_web_maps.py` and add a `MapSpec` for it to
   `SPECS` with its size and local spawn. Build from `lw_nodes` tiles and the
   `lw_maps` props; a new node goes in `lw_maps`, never in the `lw_palette`
   group (see below). Keep the box at or under 32,768 cells unless it is the
   one dense map the pack can afford (see Budget).
2. **Schematic.** Run the generator and commit `map_<id>.mts`. Rerunning it on
   an unchanged tree must be an empty diff.
3. **Registry.** One `lw_maps.register` row in `mods/lw_maps/init.lua`, in the
   same order as `SPECS`: `id`, `size`, `origin` (the footprint's minimum
   corner, at `y = BASE`) and `spawn` are all it needs. Atmosphere is optional
   — `day_night_ratio` plus a `sky = lw_maps.sky({...})` built from a handful
   of colours and a fog distance. Moving props go in `entities` with map-local
   positions. The schematic defaults to `map_<id>`.
4. **Causeway.** A `maps.causeways()` entry in `mods/lw_world/maps.lua`: a list
   of legs from the plaza's edge to the map's, a gate inside the plaza, a post
   and a poster. The north side of the plaza is the hub tour, so a map that is
   not due west, south or east leaves by a side of the plaza and turns in open
   water. The water, the beach and the rails follow from the legs.
5. **`/maps`.** Nothing to do: it lists every registered map and emerges the
   spawn's neighbourhood before it moves anyone.
6. **Landmarks.** An entry in `LANDMARKS` in `test_luanti_web_maps.py` naming
   every place a visitor has to be able to walk to from the spawn. The test
   refuses a map without one.
7. **Budget.** `python3 util/content/test_luanti_web_maps.py` prints the pack's
   nodes and the Lua heap it keeps, and fails past the budget.
8. **Docs.** A row in the table above and a walkthrough.

The harness `util/content/test_luanti_web_maps.lua` then checks the registry
(spawn inside the footprint, no overlaps with other islands or the hub) and
walks the causeway: it has to reach the spawn from the plaza without crossing
another island, another causeway, a hub building or the hub tour, and every
deck cell has to be paved with head room once the whole atlas is built.

## Not in this pack

`games/rollercoaster` and `games/log_ride` stay their own games, with their
own `game.conf` and singlenode worlds, and so do `games/spire_tunnel` and
`games/flower_island`. None of them is stamped into this atlas and `lw_maps`
registers no track, cart or flume nodes.

Carts and flowing water are whole-system demos. As plaza islands they would
fight all three of the rules the maps are built to: the node budget below, a
walk of about three minutes, and no new systems on an island. `/maps` does not
reach them either: travelling into another game is world switching, which is a
launcher feature, not a teleport.

## Nodes the pack adds

`lw_maps` registers twenty nodes. They are deliberately **not** in the
`lw_palette` group — that group builds the material library's pedestals and the
room is full — so they appear in the palette inventory (`i`) but not in the
library. Everything else the maps are built from is a `lw_nodes` tile.

| Node | For |
|------|-----|
| `pumpkin`, `jack_o_lantern` | the lane, the patch, the gate posts |
| `hay` | bales in the patch and the attic |
| `cobweb` | corners, branches, the cellar |
| `bone` | gravestones |
| `dead_wood` | bare trees, lantern posts, the entrance arch |
| `flicker`, `chase` | lamp controllers (not in the inventory) |
| `snow`, `packed_snow`, `slab_packed_snow`, `stair_packed_snow` | the mountain, the trail, the ramps |
| `ice`, `packed_ice` | the ice cave |
| `torch` | cave lighting |
| `leaves`, `pine_leaves` | the garden canopy and the pines |
| `vine` | the patch and the canopy |
| `juice_red`, `juice_green` | the juice channel |

Ten new textures cover all of it: the rest are the existing tiles re-tinted
with `[multiply`, the same trick the sixteen wool cubes use. They are
regenerated by `util/content/generate_luanti_web_textures.py` along with
everything else.

### Lamp controllers

Both controllers are airlike nodes that drive the lamp one node below them,
from a node timer, which only runs while the block is loaded — a map nobody is
on costs nothing. They switch a lamp for its twin from a registered pair
(`lw_maps.register_lamp_pair(lit, unlit)`); the jack-o'-lantern and the
pumpkin are the first pair, and a map that wants its own kind of lamp registers
two nodes and reuses both controllers. Neither will grow a lamp where a visitor
dug one out.

* `flicker` gutters on a fixed pattern, phase-offset by position.
* `chase` lights lamps one after another round a loop. A controller's place in
  the loop is its `param2`, which the schematic keeps, and every controller
  reads the same clock, so lamps in different map blocks agree on whose turn it
  is without any wiring between them.

## Budget

A map's cost is its box, not its nodes. `lw_world` loads each schematic into two
Lua arrays — node and `param2` — with a slot for every cell, air included, and
keeps them in the WASM heap for the session. Lua sizes an array to a power of
two, so a map keeps **1 MiB up to 32,768 cells and 2 MiB up to 65,536**:
halloween (25,920 cells), the fruit garden (32,000) and the lighthouse
(31,104) cost 1 MiB each, the snow mountain (44,800) costs 2 MiB. While a map loads, the engine's
`read_schematic` table exists alongside it — one small table per cell, about
290 bytes each — and that peaks at 12.6 MiB for the mountain before the
collector takes it back.

`util/content/test_luanti_web_maps.py` measures both, by running `lw_world`'s
own loader over every committed map under Lua 5.1
(`measure_luanti_web_maps_heap.lua`; a TValue is sixteen bytes on wasm32 as on
x86-64, so the arrays weigh the same in the browser). It fails when:

* the maps keep more than **8 MiB** between them, or loading one peaks past
  **16 MiB**;
* the pack's total box volume passes **200,000** cells;
* more than one map is over 32,768 cells. The snow mountain is the pack's one
  dense map; a new map fits in 32,768 or it costs what two do.

The cap used to be 120,000 cells of volume, set before the cost was measured.
It is now set from the measurement: eight maps' worth of 1 MiB against a
256 MiB initial heap. The schematics themselves are 6.9 KiB on disk and the
ten textures under 6 KiB. See the content budget in `wasm_porting.md`.
