<!--
Luanti
SPDX-License-Identifier: LGPL-2.1-or-later
Copyright (C) 2026 The Luanti Contributors
-->

# The themed maps

Six authored maps ship with the showcase pack, as islands around the hub
plaza. They are design pieces, not procedural terrain: each one is a single
committed schematic, compact enough for the WASM heap and short enough to walk
in about three minutes. First-time visitors land in a designed space and every
direction out of it leads to another one.

```
      [ caldera ]                                  [ bazaar ]
          |                                            |
   [ Halloween ]------------[ hub plaza ]------------[ fruit garden ]
        west                    |     |                   east
                    [ lighthouse ]   [ snow mountain ]
                      south-west          south
```

Every causeway is walkable. Fly, fast and noclip are on for everyone, but the
tour never needs them. North of the plaza is the hub tour (library, courtyard,
gallery, theater), so the maps take the other five bearings and the sixth,
north-west, goes round the library.

## The six maps

| Map | `id` | Schematic | Footprint (`size`) | Origin (min corner) | Spawn | Time of day |
|-----|------|-----------|--------------------|---------------------|-------|-------------|
| Halloween lane | `halloween` | `map_halloween.mts` | 36 × 16 × 36 | `(-88, 5, -26)` | `(-55, 9, -9)` | dusk (`day_night_ratio = 0.16`, fogged sky) |
| Snowy mountain | `snow_mountain` | `map_snow_mountain.mts` | 40 × 28 × 40 |  `(-20, 5, -74)` | `(6, 9, -37)` | bright overcast (`0.85`, pale sky) |
| Giant fruit garden | `fruit_garden` | `map_fruit_garden.mts` | 40 × 20 × 40 | `(53, 5, -28)` | `(55, 9, -7)` | the world's own midday |
| Lighthouse tide | `lighthouse` | `map_lighthouse.mts` | 36 × 24 × 36 | `(-84, 5, -63)` | `(-51, 9, -30)` | late afternoon (`0.42`, sea haze) |
| Crystal night bazaar | `bazaar` | `map_bazaar.mts` | 36 × 20 × 36 | `(49, 5, 20)` | `(50, 9, 21)` | night (`0.1`, no clouds) |
| Volcanic smoke caldera | `caldera` | `map_caldera.mts` | 36 × 24 × 36 | `(-84, 5, 20)` | `(-50, 9, 21)` | ash haze (`0.55`, short orange fog) |

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

A square lighthouse on a rock headland, with the sea on two sides.

* **The tower** is 7 × 7 and twelve courses of banded wool. Inside, a spiral
  stair of plank treads winds round a beam spine, one rise every two cells,
  up to a hatch in the lamp-room floor. The stair is the inner ring of the
  interior because a ring of cells is the only spiral a walker can climb
  without a jump: `test_luanti_web_maps.py` walks it.
* **The lamp room** is glass all round with a lamp on a pedestal. Above the
  lamp, `lw_maps:beacon` is an airlike node timer that lights one of the four
  mid-face windows at a time (`lw_maps:beam`, light 14) and puts the glass
  back in the other three, so the beacon sweeps. Dig a window out and the
  controller leaves the hole alone, like the lanterns on the lane.
* **The gallery** is a railed walk round the outside of the lamp room, through
  a door in the west glass one cell off the middle, because the middle of
  every face is a window the beacon owns.
* **The headland** is a dome one node up per 1.5 of radius, so it is walkable
  from any side with no path cut into it. A **sea cave** runs in from the
  south shore under the tower, floored with rock pools.
* A keeper's cottage with a lit window, a boardwalk from the causeway, a jetty
  out over the lagoon with a boat tied up, and a buoy on the rocks. The sea is
  `lw_nodes:water` one node deep over stone: the tide is in the name, not in
  a liquid simulation.

### Crystal night bazaar

A walled night market. The crystals and the lanterns are the light.

* Two main lanes leave the **corner gate** where the causeway lands, and two
  cross lanes meet under a **mudbrick dome** with a doorway wherever a lane
  comes in and a crystal fountain in the middle, lit from within. An oculus
  and four lanterns at the springing.
* **Stalls**: a plank counter three wide with a lit crystal on it under a
  striped wool awning on two posts. Sixteen of them, in six stripes and four
  tints, plus rugs on the sand between.
* **The rooftop walk**: the north wall is three thick and its top is railed,
  reached by a stone-brick stair at the end of the west lane. A minaret on
  the north-east corner is the tallest thing on the island.
* **The crystal grotto**: a cellar under the south-east stalls, down three
  treads off the south lane, with every tint the market sells growing from
  its walls and floor.
* Four crystal nodes (`lw_maps:crystal_violet`, `_cyan`, `_rose`, `_amber`)
  share one faceted texture and are tinted with `[multiply`. They are solid,
  glasslike and light 10, so a stall's stock is also the stall's lamp.

### Volcanic smoke caldera

The snow mountain's shape with the opposite weather: a cinder cone you climb,
look into, and go under.

* **Up:** the same spiral shelf as the mountain (`spiral_shelf` in the
  generator, which both cones now share), cut into basalt and floored with
  ash, from the trailhead at the causeway to the **crater rim**: a walk
  right round the bowl, one course below the plateau and inside a low
  parapet of whatever the cone left standing. It is cut after the spiral,
  because the shelf's last lap crosses the plateau and a walk at plateau
  height would be broken wherever the shelf's headroom is. The test checks
  all four sides of it.
* **In:** the crater is terraced one node per quarter node of radius down to a
  **lava lake** — `lw_maps:lava`, translucent, lit and not walkable, the same
  trick as the garden's juice. There is no damage; the showcase has no combat
  and this is not the place to start. `test_caldera_lake_is_reachable` walks
  from the rim to the lava and checks the lake is level.
* **Under:** a **lava tube** in from the east face, with a brick portal, into
  a **magma chamber** under the bowl: lava seeps in the floor, each lit from
  beneath, basalt columns, torches. A timbered stair (dead wood, not beams)
  climbs from the chamber's north wall and finds the trail the way the
  mineshaft does: the generator picks whichever tread of the spiral is
  nearest, so the exit still meets the trail if the cone's slope changes.
* **Smoke:** `lw_maps:vent` is an airlike node timer in a sulphur-ringed
  vent just outside the rim walk. It drives the six cells above it, a puff (`lw_maps:smoke`,
  a translucent cube) every third node, rising. Not a particle spawner:
  particles are exactly the per-frame work the application worker cannot
  spare. A few static puffs hang over the lake and the hot spring.
* Ash field round the foot of the cone: dead trees, basalt columns, a
  sulphur-ringed hot spring in the north-west corner.

## Getting there

* Walk. Six causeways leave the plaza, each with a gate whose posts are
  topped with something from the map they point at, and a poster that says
  what is over there. The first three (west, east, south) are one straight
  leg. The diagonal three are two legs each: south then west to the
  lighthouse; east then north to the bazaar; west then north to the caldera.
  Every op in the atlas is an axis-aligned box, so a diagonal causeway is an
  L, not a diagonal.
* `/maps` lists the six maps; `/maps <id>` travels to one. It emerges the
  area around the spawn first, because the islands are far enough out that a
  visitor can otherwise arrive before the chunk does.

## Editing them

The maps are generated, not authored in game:

```sh
python3 util/content/generate_luanti_web_maps.py
python3 util/content/generate_luanti_web_maps.py --dump map_halloween   # character map
```

It is deterministic and uses only the standard library, like every other asset
in the pack; rerunning it on an unchanged tree produces an empty diff.

To add a map:

1. Write a `build_<name>()` in the generator that returns a `Build`, and add
   it to `MAPS`, `SIZES` and `SPAWNS`. Local `y = 0` is world `y = 5`, so put
   the ground at `SURFACE` and the first walkable layer at `FLOOR`. Keep the
   footprint between 36 and 40 on x and z and 16 to 28 high; the budget test
   enforces that and the node cap below.
2. Register it in `lw_maps/init.lua`: `id`, `title`, `blurb`, `schem`, `size`,
   `origin`, `spawn`, and a `day_night_ratio` and `sky` if it is not midday.
   `test_registry_agrees_with_the_schematics` checks the footprint and the
   spawn against the generator, so a spawn moved in one place fails in the
   other.
3. Give it a causeway in `lw_world/maps.lua`: one or more legs, a gate on the
   plaza, a post node and a sign. The first leg must touch the plaza and the
   last the map's beach; the Lua harness checks that, that no leg crosses
   another map, and that the moat does not reach the showcase island's sand
   shelf (keep the footprint at least 12 nodes from `x = ±36`).
4. Add its landmarks to `test_luanti_web_maps.py` and make sure the flood
   fill reaches every one of them from the spawn.
5. New props go in `lw_maps`, tinted from existing tiles where at all
   possible; a genuinely new texture goes in `MAP_NODE_TEXTURES` in
   `generate_luanti_web_textures.py`, which the budget test compares against
   the textures directory.

Geometry is why: the maps are cones, ellipsoids and a helical ramp, and doing
that arithmetic once at build time keeps it off the browser's application
worker, where chunk generation competes with the compositor. `.mts` is the
committed form because it keeps `param2` (a theater seat still faces the stage)
and compresses the six maps to under 13 KiB.

Once they are stamped into a world, `/lw_schem place map_halloween` puts the
committed file back over an existing world, the same as any other piece.

`util/content/test_luanti_web_maps.py` flood-fills each map from its spawn
under a player's movement rules and asserts that every landmark is standable
and connected — the tunnel mouths, the cellar, the attic, the summit, the
inside of the watermelon. If a change walls off a route, that test says so.

## Nodes the pack adds

`lw_maps` registers thirty-two nodes. They are deliberately **not** in the
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
| `flicker` | the lantern controller (not in the inventory) |
| `snow`, `packed_snow`, `slab_packed_snow`, `stair_packed_snow` | the mountain, the trail, the ramps |
| `ice`, `packed_ice` | the ice cave |
| `torch` | cave lighting |
| `leaves`, `pine_leaves` | the garden canopy and the pines |
| `vine` | the patch and the canopy |
| `juice_red`, `juice_green` | the juice channel |
| `sea_rock` | the headland, the sea stacks, the cave |
| `beam`, `beacon` | the lit lamp-room window and the timer that sweeps it (the beacon is not in the inventory) |
| `mudbrick` | the bazaar's walls, dome and minaret |
| `crystal_violet`, `crystal_cyan`, `crystal_rose`, `crystal_amber` | the stalls, the fountain, the grotto |
| `basalt`, `ash` | the cone, the trail, the ash field |
| `lava` | the lake and the chamber's seeps |
| `smoke`, `vent` | the puffs and the timer that raises them (the vent is not in the inventory) |

Twelve textures cover all of it: the rest are the existing tiles re-tinted
with `[multiply`, the same trick the sixteen wool cubes use. The second three
maps added only two (the crystal facets and the smoke puff). They are
regenerated by `util/content/generate_luanti_web_textures.py` along with
everything else.

## Budget

The six maps are about 186,000 authored nodes (footprint volume) and 12.5 KiB
of committed schematic; the twelve textures are under 5 KiB. `lw_world` loads
each schematic at mod load and keeps it for the session, so the maps are
charged against the WASM heap, not only against `luanti.data`.

Each loaded piece is two byte strings, one of node indices and one of
`param2`, so a node costs two bytes of heap: the six maps are under 400 KiB
resident. (They used to be two Lua arrays at 16 bytes a slot, about 3 MiB for
the first three maps, which is what the old 120k cap was priced against.) The
cap is now **200k nodes** and `test_luanti_web_maps.py` fails past it; raise
it on purpose, in the test and here, not by accident. The same test holds
every footprint to 36–40 × 16–28 × 36–40. See the content budget in
`wasm_porting.md`.

## Out of scope

Procedural overworlds, VoxeLibre/Mineclonia, villages, a nether, mobs, combat,
crafting, and particle systems that stall the application worker. The
rollercoaster and the log ride stay what they are — `games/rollercoaster` and
`games/log_ride`, separate small games in the bundle — rather than becoming
maps here: each is a game mechanic (rideable carts, flume boats) with its own
nodes and entities, not a place to walk, and the showcase world is a place to
walk.
