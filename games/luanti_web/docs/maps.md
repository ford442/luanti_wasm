<!--
Luanti
SPDX-License-Identifier: LGPL-2.1-or-later
Copyright (C) 2026 The Luanti Contributors
-->

# The themed maps

Three authored maps ship with the showcase pack, as islands around the hub
plaza. They are design pieces, not procedural terrain: each one is a single
committed schematic, compact enough for the WASM heap and short enough to walk
in about three minutes.

```
                      [ snow mountain ]
                             |
        [ Halloween ]---[ hub plaza ]---[ fruit garden ]
             west                            east
```

Every causeway is walkable. Fly, fast and noclip are on for everyone, but the
tour never needs them.

## The three maps

| Map | `id` | Schematic | Footprint (`size`) | Origin (min corner) | Spawn | Time of day |
|-----|------|-----------|--------------------|---------------------|-------|-------------|
| Halloween lane | `halloween` | `map_halloween.mts` | 36 × 16 × 36 | `(-88, 5, -26)` | `(-55, 9, -9)` | dusk (`day_night_ratio = 0.16`, fogged sky) |
| Snowy mountain | `snow_mountain` | `map_snow_mountain.mts` | 40 × 28 × 40 |  `(-20, 5, -74)` | `(6, 9, -37)` | bright overcast (`0.85`, pale sky) |
| Giant fruit garden | `fruit_garden` | `map_fruit_garden.mts` | 40 × 20 × 40 | `(53, 5, -28)` | `(55, 9, -7)` | the world's own midday |

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

## Getting there

* Walk. Three causeways leave the plaza — west, east and south — each with a
  gate whose posts are topped with something from the map they point at, and a
  poster that says what is over there.
* `/maps` lists the three maps; `/maps <id>` travels to one. It emerges the
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

## Nodes the pack adds

`lw_maps` registers nineteen nodes. They are deliberately **not** in the
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

Ten new textures cover all of it: the rest are the existing tiles re-tinted
with `[multiply`, the same trick the sixteen wool cubes use. They are
regenerated by `util/content/generate_luanti_web_textures.py` along with
everything else.

## Budget

The three maps are about 98,000 authored nodes and 6.8 KiB of committed
schematic; the ten textures are under 6 KiB. `lw_world` loads each schematic
into two Lua arrays at mod load, so the maps cost a few MiB of the WASM heap
for the session — which is why the footprints are capped and
`test_luanti_web_maps.py` fails if they grow past 120k nodes. See the content
budget in `wasm_porting.md`.
