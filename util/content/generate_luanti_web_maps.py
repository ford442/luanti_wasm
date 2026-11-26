#!/usr/bin/env python3
# Luanti
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 The Luanti Contributors
"""Generate the authored themed maps for games/luanti_web.

    python3 util/content/generate_luanti_web_maps.py

Each map is one hand-authored schematic written to
``games/luanti_web/mods/lw_world/schems/map_<name>.mts``. They are stamped
into the atlas world by ``lw_world/maps.lua`` exactly like the plaza fountain
or the theater, so a fresh world gets every map on first generation and an
existing world is never overwritten.

Why a schematic and not mapgen: the content policy in ``wasm_porting.md``
rules out noise-driven terrain as the landing world, and a schematic is the
only committed form that keeps ``param2`` (a theater seat still faces the
stage), supports never-place cells, and compresses to a couple of KiB.

Why Python and not Lua: the maps are geometry — cones, ellipsoids, a helical
ramp — and generating them once at build time keeps that arithmetic out of
the browser's application worker, where every chunk generation competes with
the compositor.

Layout, in the atlas the hub plaza sits in the middle of::

    [ laser serpent ]-[ smoke caldera ]  [ crystal bazaar ]-[ mirror hall ]
          |
    [ wof christmas ]
             [ halloween ]------[ hub ]------[ fruit garden ]-[ christmas ]
                                  |
    [ lighthouse ]  [ snow mountain ]   [ rainbow storm ]

and the Around arena north-east of the hub, beyond the gallery, with the
thunder chapel mirroring it north-west, beyond the library, and a larger
concert arena north of the Around arena, reached from its east side. The
diagonal four, the arenas and the chapel are reached by causeways that turn
in the open water, and the cabaret club, west of the lighthouse, by one that
turns twice. The two Weeks on Fire islands are spurs: the laser serpent off
the mouth of the caldera's tube, the mirror hall off the end of the bazaar's
arcade, and so are the two Christmas islands: the village off the far end of
the fruit garden's path, the Weeks on Fire Christmas off the south side of
the serpent's field;
lw_world/maps.lua has the legs, and games/luanti_web/docs/maps.md the recipe
for adding a map.

Local coordinates below run ``0..size-1`` on each axis. ``lw_world`` stamps
local ``y = 0`` at world ``y = 5``, so local ``y = SURFACE`` is the world's
ground level and local ``y = FLOOR`` is the first walkable layer — the same
``GROUND``/``FLOOR`` the rest of the showcase is built on.

Only the standard library is used.
"""

from __future__ import annotations

import argparse
import collections
import dataclasses
import math
import pathlib
import sys
import typing

SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
	sys.path.insert(0, str(SCRIPT_DIR))

from mts_to_text import Schematic, schematic_from_cells, to_text, write_mts

# --------------------------------------------------------------------------
# Shared frame
# --------------------------------------------------------------------------

# Local y of the ground surface and of the first walkable layer. Must match
# MAP_BASE_Y / GROUND / FLOOR in games/luanti_web/mods/lw_world/maps.lua.
SURFACE = 3
FLOOR = SURFACE + 1

AIR = "air"

STONE = "lw_nodes:stone"
DIRT = "lw_nodes:dirt"
GRASS = "lw_nodes:dirt_with_grass"
SAND = "lw_nodes:sand"
PAVING = "lw_nodes:paving"
WATER = "lw_nodes:water"
BRICK = "lw_nodes:stone_brick"
POLISHED = "lw_nodes:polished_stone"
PLANKS = "lw_nodes:planks"
PLANK_SLAB = "lw_nodes:slab_planks"
PLANK_STAIR = "lw_nodes:stair_planks"
BRICK_SLAB = "lw_nodes:slab_stone_brick"
BEAM = "lw_nodes:beam"
GLASS = "lw_nodes:glass"
GOLD = "lw_nodes:gold_trim"
FENCE = "lw_nodes:fence"
CURTAIN = "lw_nodes:curtain"
CARPET = "lw_nodes:carpet"
LAMP = "lw_nodes:lamp"
UPLIGHT = "lw_nodes:uplight"
HIDDEN_LIGHT = "lw_nodes:hidden_light"
PEDESTAL = "lw_nodes:pedestal"
COLUMN = "lw_nodes:column"
FIRE = "lw_nodes:fire"
SEAT = "lw_theater:seat"

PUMPKIN = "lw_maps:pumpkin"
JACK = "lw_maps:jack_o_lantern"
HAY = "lw_maps:hay"
COBWEB = "lw_maps:cobweb"
BONE = "lw_maps:bone"
DEAD_WOOD = "lw_maps:dead_wood"
FLICKER = "lw_maps:flicker"
CHASE = "lw_maps:chase"
SNOW = "lw_maps:snow"
PACKED_SNOW = "lw_maps:packed_snow"
SNOW_SLAB = "lw_maps:slab_packed_snow"
SNOW_STAIR = "lw_maps:stair_packed_snow"
ICE = "lw_maps:ice"
PACKED_ICE = "lw_maps:packed_ice"
TORCH = "lw_maps:torch"
PINE_LEAVES = "lw_maps:pine_leaves"
LEAVES = "lw_maps:leaves"
VINE = "lw_maps:vine"
JUICE_RED = "lw_maps:juice_red"
JUICE_GREEN = "lw_maps:juice_green"
NEON_TUBE = "lw_maps:neon_tube"
WATERFALL = "lw_maps:waterfall"
MORNING_GLORY = "lw_maps:morning_glory"
GLOW_SHROOM = "lw_maps:glow_shroom"
GLOW_FERN = "lw_maps:glow_fern"
BIKE_RACK = "lw_cascade:bike_rack"


def wool(color: str) -> str:
	return "lw_nodes:wool_" + color


# Everything a player walks through rather than on. Used by the reachability
# check in test_luanti_web_maps.py, and kept here so it stays next to the node
# names it talks about — a new decorative node that is secretly solid would
# otherwise wall off a route and nothing would notice.
NON_WALKABLE = frozenset({
	AIR, WATER, COBWEB, TORCH, FIRE, VINE, HIDDEN_LIGHT, FLICKER, CHASE,
	JUICE_RED, JUICE_GREEN, NEON_TUBE, WATERFALL, MORNING_GLORY, GLOW_SHROOM,
	GLOW_FERN, BIKE_RACK,
})

# Nodes a player's head and chest can occupy but that are not full cubes, so
# standing on them is fine and so is standing *in* them.
HALF_HEIGHT = frozenset({
	PLANK_SLAB, BRICK_SLAB, SNOW_SLAB, PLANK_STAIR, SNOW_STAIR, CARPET,
	"lw_nodes:stair_stone_brick", "lw_nodes:slab_stone_brick",
})


class Build:
	"""A sparse box of cells, written out as one MTS schematic."""

	def __init__(self, sx: int, sy: int, sz: int) -> None:
		self.sx, self.sy, self.sz = sx, sy, sz
		self.cells: dict[tuple[int, int, int], object] = {}

	def inside(self, x: int, y: int, z: int) -> bool:
		return 0 <= x < self.sx and 0 <= y < self.sy and 0 <= z < self.sz

	def set(self, x, y, z, name, param2: int = 0) -> None:
		"""Place one node. Out-of-range cells are dropped, not an error:
		the shape generators below sweep whole bounding boxes and clipping
		them here is what keeps a cone from needing its own edge cases."""
		if not self.inside(x, y, z):
			return
		self.cells[(x, y, z)] = (name, param2) if param2 else name

	def get(self, x, y, z) -> str:
		value = self.cells.get((x, y, z), AIR)
		return value[0] if isinstance(value, tuple) else value

	def box(self, x0, y0, z0, x1, y1, z1, name, param2: int = 0) -> None:
		for x in range(min(x0, x1), max(x0, x1) + 1):
			for y in range(min(y0, y1), max(y0, y1) + 1):
				for z in range(min(z0, z1), max(z0, z1) + 1):
					self.set(x, y, z, name, param2)

	def clear(self, x0, y0, z0, x1, y1, z1) -> None:
		self.box(x0, y0, z0, x1, y1, z1, AIR)

	def walls(self, x0, y0, z0, x1, y1, z1, name) -> None:
		self.box(x0, y0, z0, x1, y1, z0, name)
		self.box(x0, y0, z1, x1, y1, z1, name)
		self.box(x0, y0, z0, x0, y1, z1, name)
		self.box(x1, y0, z0, x1, y1, z1, name)

	def ground(self, surface: str, sub: str = DIRT, base: str = STONE) -> None:
		"""The three layers under every map: rock, subsoil, surface."""
		self.box(0, 0, 0, self.sx - 1, SURFACE - 2, self.sz - 1, base)
		self.box(0, SURFACE - 1, 0, self.sx - 1, SURFACE - 1, self.sz - 1, sub)
		self.box(0, SURFACE, 0, self.sx - 1, SURFACE, self.sz - 1, surface)

	def sphere(self, cx, cy, cz, radius, name, *, sy=None, shell=None) -> None:
		"""Solid or hollow ellipsoid. ``shell`` is the wall thickness."""
		ry = sy if sy is not None else radius
		for x in range(int(cx - radius) - 1, int(cx + radius) + 2):
			for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
				for z in range(int(cz - radius) - 1, int(cz + radius) + 2):
					d = (((x - cx) / radius) ** 2 + ((y - cy) / ry) ** 2
						+ ((z - cz) / radius) ** 2)
					if d > 1.0:
						continue
					if shell is not None:
						inner = radius - shell
						inner_y = ry - shell
						if inner > 0 and inner_y > 0 and (
								((x - cx) / inner) ** 2 + ((y - cy) / inner_y) ** 2
								+ ((z - cz) / inner) ** 2) <= 1.0:
							continue
					self.set(x, y, z, name)

	def to_schematic(self) -> Schematic:
		return schematic_from_cells(self.sx, self.sy, self.sz, self.cells)


# facedir puts a node's *back* where core.facedir_to_dir points, so a stair
# climbed walking north (+z) is facedir 0, east is 1, south is 2, west is 3 —
# the same convention the theater seats use.
NORTH, EAST, SOUTH, WEST = 0, 1, 2, 3


def stair_run(build: Build, x0: int, x1: int, z: int, dz: int,
		y: int, steps: int, node: str, headroom: int = 3) -> None:
	"""A straight run of solid steps, with the headroom above each one cut.

	``dz`` is +1 or -1 and ``steps`` may rise (positive) or fall: the caller
	passes the y of the first tread and the run walks one node per step.
	"""
	rise = 1 if steps > 0 else -1
	facing = NORTH if dz > 0 else SOUTH
	for index in range(abs(steps)):
		tz = z + dz * index
		ty = y + rise * index
		build.box(x0, ty, tz, x1, ty, tz, node, facing)
		build.clear(x0, ty + 1, tz, x1, ty + headroom, tz)


# --------------------------------------------------------------------------
# 1. Halloween lane
# --------------------------------------------------------------------------

HALLOWEEN_SIZE = (36, 20, 36)
# The causeway from the hub lands on the east face, mid-map.
HALLOWEEN_SPAWN = (33, FLOOR, 17)

# Where the haunted house stands, in local coordinates.
HOUSE = dict(x0=18, x1=32, z0=21, z1=33)
HOUSE_FLOOR = FLOOR                 # ground floor tread
HOUSE_CEILING = FLOOR + 4           # ceiling / attic floor
HOUSE_ATTIC_TOP = FLOOR + 8         # first roof course
CELLAR_FLOOR = 0                    # you stand on local y 0, head in 1..2


def lantern_post(build: Build, x: int, z: int, height: int = 2,
		flicker: bool = False) -> None:
	"""Dead-wood post, carved lantern on top, optional flicker controller.

	The controller is airlike and drives the node *below* it, so it can sit in
	the air above the lantern without putting a hole in the post.
	"""
	for offset in range(height):
		build.set(x, FLOOR + offset, z, DEAD_WOOD)
	build.set(x, FLOOR + height, z, JACK)
	if flicker:
		build.set(x, FLOOR + height + 1, z, FLICKER)


def dead_tree(build: Build, x: int, z: int, height: int, arms) -> None:
	for offset in range(height):
		build.set(x, FLOOR + offset, z, DEAD_WOOD)
	for dx, dz, ay in arms:
		build.set(x + dx, FLOOR + ay, z + dz, DEAD_WOOD)
		build.set(x + 2 * dx, FLOOR + ay, z + 2 * dz, DEAD_WOOD)
		build.set(x + 2 * dx, FLOOR + ay + 1, z + 2 * dz, COBWEB)


def gravestone(build: Build, x: int, z: int, tall: bool) -> None:
	build.set(x, FLOOR, z, BONE)
	if tall:
		build.set(x, FLOOR + 1, z, BONE)
		build.set(x, FLOOR + 2, z, BONE)
	else:
		build.set(x, FLOOR + 1, z, BRICK_SLAB)


def build_haunted_house(build: Build) -> None:
	x0, x1, z0, z1 = HOUSE["x0"], HOUSE["x1"], HOUSE["z0"], HOUSE["z1"]
	wall = wool("dark_grey")
	trim = wool("black")

	# Shell: floor slab, two storeys of wall, an attic floor that doubles as
	# the ground floor's ceiling.
	build.box(x0, HOUSE_FLOOR, z0, x1, HOUSE_FLOOR, z1, PLANKS)
	build.clear(x0, HOUSE_FLOOR + 1, z0, x1, HOUSE_ATTIC_TOP - 1, z1)
	build.walls(x0, HOUSE_FLOOR + 1, z0, x1, HOUSE_CEILING - 1, z1, wall)
	build.box(x0, HOUSE_CEILING, z0, x1, HOUSE_CEILING, z1, PLANKS)
	build.walls(x0, HOUSE_CEILING + 1, z0, x1, HOUSE_ATTIC_TOP - 1, z1, wall)
	# Corner posts, so the black box reads as a timber frame.
	for cx in (x0, x1):
		for cz in (z0, z1):
			build.box(cx, HOUSE_FLOOR + 1, cz, cx, HOUSE_ATTIC_TOP - 1, cz, BEAM)

	# Gabled roof: courses of plank stair stepping in from both long sides.
	span = (z1 - z0) // 2
	for step in range(span + 1):
		y = HOUSE_ATTIC_TOP + step
		if y >= build.sy:
			break
		build.box(x0 - 1, y, z0 + step, x1 + 1, y, z0 + step, PLANK_STAIR, 20)
		build.box(x0 - 1, y, z1 - step, x1 + 1, y, z1 - step, PLANK_STAIR, 22)
		# Gable ends, between the two slopes. At the ridge the slopes meet and
		# there is nothing between them; box() would otherwise swap the range
		# round and stand a stub of wall on each end of the ridge.
		if z0 + step + 1 <= z1 - step - 1:
			build.clear(x0, y, z0 + step + 1, x1, y, z1 - step - 1)
			build.box(x0, y, z0 + step + 1, x0, y, z1 - step - 1, wall)
			build.box(x1, y, z0 + step + 1, x1, y, z1 - step - 1, wall)

	# Front door and hallway, straight through from the lane to the back wall.
	hall_x0, hall_x1 = 24, 25
	build.clear(hall_x0, HOUSE_FLOOR + 1, z0, hall_x1, HOUSE_FLOOR + 2, z0)
	build.box(hall_x0 - 1, HOUSE_FLOOR + 3, z0, hall_x1 + 1, HOUSE_FLOOR + 3, z0, trim)
	build.set(hall_x0, HOUSE_FLOOR + 3, z0 - 1, JACK)
	build.set(hall_x1, HOUSE_FLOOR + 3, z0 - 1, JACK)
	build.set(hall_x0, HOUSE_FLOOR + 4, z0 - 1, FLICKER)
	# Porch steps down to the lane.
	build.box(hall_x0 - 1, HOUSE_FLOOR, z0 - 2, hall_x1 + 1, HOUSE_FLOOR, z0 - 1, PLANK_SLAB)

	# Two partition walls with doorways, so the hallway is a hallway.
	for wall_x in (hall_x0 - 1, hall_x1 + 1):
		build.box(wall_x, HOUSE_FLOOR + 1, z0 + 1, wall_x, HOUSE_CEILING - 1, z1 - 1, wall)
		build.clear(wall_x, HOUSE_FLOOR + 1, z0 + 5, wall_x, HOUSE_FLOOR + 2, z0 + 6)
	# Lit windows on the side rooms.
	for wx in (x0, x1):
		for wz in (z0 + 3, z0 + 7, z0 + 10):
			build.box(wx, HOUSE_FLOOR + 2, wz, wx, HOUSE_FLOOR + 3, wz, GLASS)
			inner = wx + (1 if wx == x0 else -1)
			build.set(inner, HOUSE_FLOOR + 3, wz, JACK)
	# Cobwebs in every ground-floor corner.
	for cx in (x0 + 1, x1 - 1):
		for cz in (z0 + 1, z1 - 1):
			build.set(cx, HOUSE_CEILING - 1, cz, COBWEB)

	# Stair to the attic, at the north end of the hallway, with the ceiling
	# opened above it.
	build.clear(hall_x0, HOUSE_CEILING, z1 - 5, hall_x1, HOUSE_CEILING, z1 - 1)
	stair_run(build, hall_x0, hall_x1, z1 - 5, 1,
		HOUSE_FLOOR + 1, 4, PLANK_STAIR, headroom=4)
	build.box(hall_x0, HOUSE_CEILING, z1 - 1, hall_x1, HOUSE_CEILING, z1 - 1, PLANKS)

	# Attic: one long room, a gable window at each end, a single lantern.
	build.box(x0 + 1, HOUSE_CEILING + 2, z0, x1 - 1, HOUSE_CEILING + 3, z0, GLASS)
	build.box(x0 + 1, HOUSE_CEILING + 2, z1, x1 - 1, HOUSE_CEILING + 3, z1, GLASS)
	build.set(25, HOUSE_CEILING + 3, z0 + 6, JACK)
	build.set(25, HOUSE_CEILING + 4, z0 + 6, FLICKER)
	for cx in (x0 + 1, x1 - 1):
		for cz in (z0 + 1, z1 - 1):
			build.set(cx, HOUSE_CEILING + 1, cz, COBWEB)
	build.box(x0 + 2, HOUSE_CEILING + 1, z0 + 2, x0 + 4, HOUSE_CEILING + 1, z0 + 3, HAY)

	# Cellar: carved out under the east half, reached by stairs cut through
	# the ground floor. You stand on local y 0 with two nodes of headroom.
	cellar = dict(x0=26, x1=31, z0=z0 + 1, z1=z0 + 7)
	build.box(cellar["x0"], CELLAR_FLOOR, cellar["z0"],
		cellar["x1"], CELLAR_FLOOR, cellar["z1"], BRICK)
	build.clear(cellar["x0"], CELLAR_FLOOR + 1, cellar["z0"],
		cellar["x1"], SURFACE, cellar["z1"])
	build.walls(cellar["x0"] - 1, CELLAR_FLOOR + 1, cellar["z0"] - 1,
		cellar["x1"] + 1, SURFACE, cellar["z1"] + 1, BRICK)
	build.set(cellar["x0"] + 1, CELLAR_FLOOR + 2, cellar["z0"] + 1, TORCH)
	build.set(cellar["x1"] - 1, CELLAR_FLOOR + 2, cellar["z1"] - 1, COBWEB)
	build.box(cellar["x1"] - 2, CELLAR_FLOOR + 1, cellar["z1"] - 1,
		cellar["x1"] - 1, CELLAR_FLOOR + 1, cellar["z1"] - 1, PUMPKIN)
	# The stairwell: four treads down from the ground floor into the cellar.
	well_x0, well_x1 = 27, 28
	stair_run(build, well_x0, well_x1, z0 + 8, -1,
		HOUSE_FLOOR - 1, -4, PLANK_STAIR, headroom=3)
	build.clear(well_x0, HOUSE_FLOOR, z0 + 5, well_x1, HOUSE_FLOOR, z0 + 8)
	# Reopen the cellar's north wall where the stair comes through it.
	build.clear(well_x0, CELLAR_FLOOR + 1, cellar["z1"] + 1,
		well_x1, SURFACE, cellar["z1"] + 1)


def build_stage(build: Build) -> None:
	"""The lane's destination: a small porch stage facing two rows of seats.

	The deck is west, the audience east, and the seats are lw_theater:seat at
	facedir 1 — the quarter turn that puts a sitter's eyes on the deck.
	"""
	build.box(2, FLOOR, 4, 12, FLOOR, 12, PLANKS)
	build.box(3, FLOOR + 1, 4, 5, FLOOR + 1, 12, PLANKS)      # raised deck
	build.box(2, FLOOR + 1, 4, 2, FLOOR + 6, 12, CURTAIN)     # backdrop
	for z in (4, 12):
		build.box(3, FLOOR + 2, z, 3, FLOOR + 5, z, BEAM)
	build.box(3, FLOOR + 6, 4, 3, FLOOR + 6, 12, GOLD)
	for z in (5, 11):
		build.set(3, FLOOR + 2, z, JACK)
	build.set(3, FLOOR + 3, 11, FLICKER)
	build.set(4, FLOOR + 2, 8, PUMPKIN)
	for x in (8, 10):
		for z in range(5, 12, 2):
			build.set(x, FLOOR + 1, z, SEAT, EAST)
	build.set(12, FLOOR + 1, 8, PEDESTAL)
	build.set(12, FLOOR + 2, 8, JACK)


def build_graveyard(build: Build) -> None:
	x0, x1, z0, z1 = 3, 15, 21, 33
	build.box(x0, SURFACE, z0, x1, SURFACE, z1, DIRT)
	for x in range(x0, x1 + 1, 2):
		build.set(x, FLOOR, z0, FENCE)
	for z in range(z0, z1 + 1, 2):
		build.set(x0, FLOOR, z, FENCE)
		build.set(x1, FLOOR, z, FENCE)
	build.clear(8, FLOOR, z0, 10, FLOOR, z0)      # gate onto the lane
	build.set(8, FLOOR + 1, z0, JACK)
	build.set(10, FLOOR + 1, z0, JACK)
	for row, z in enumerate(range(z0 + 3, z1 - 1, 3)):
		for column, x in enumerate(range(x0 + 2, x1 - 1, 3)):
			gravestone(build, x, z, tall=(row + column) % 3 == 0)
	dead_tree(build, x0 + 2, z1 - 2, 5, ((1, 0, 3), (0, -1, 4)))
	dead_tree(build, x1 - 2, z0 + 4, 4, ((-1, 0, 3), (0, 1, 2)))
	build.set(9, FLOOR, z1 - 2, UPLIGHT)


def build_pumpkin_patch(build: Build) -> None:
	x0, x1, z0, z1 = 16, 32, 2, 14
	build.box(x0, SURFACE, z0, x1, SURFACE, z1, DIRT)
	# Rows of pumpkins on their vines, with hay bales stacked at the ends.
	for row, z in enumerate(range(z0 + 1, z1, 3)):
		for x in range(x0 + 1, x1, 2):
			if (x + row) % 3 == 0:
				continue
			build.set(x, FLOOR, z, PUMPKIN)
			build.set(x, FLOOR, z + 1, VINE, 2)
	build.box(x1 - 3, FLOOR, z0 + 1, x1 - 1, FLOOR, z0 + 2, HAY)
	build.box(x1 - 2, FLOOR + 1, z0 + 1, x1 - 1, FLOOR + 1, z0 + 2, HAY)
	build.box(x0 + 1, FLOOR, z1 - 1, x0 + 2, FLOOR + 1, z1, HAY)
	dead_tree(build, 22, 8, 5, ((1, 0, 4), (-1, 0, 3)))
	build.set(28, FLOOR, 8, FIRE)
	build.box(27, SURFACE, 7, 29, SURFACE, 9, POLISHED)
	build.set(28, SURFACE, 8, POLISHED)


def build_halloween() -> Build:
	sx, sy, sz = HALLOWEEN_SIZE
	build = Build(sx, sy, sz)
	build.ground(GRASS)

	# The lane: paving from the causeway on the east face to the stage.
	build.box(2, SURFACE, 16, sx - 1, SURFACE, 19, PAVING)
	for x in range(3, sx - 1, 4):
		lantern_post(build, x, 15, flicker=(x % 8 == 3))
		lantern_post(build, x, 20, flicker=(x % 8 == 7))
	# Entrance arch where the causeway lands.
	for z in (15, 20):
		build.box(sx - 1, FLOOR, z, sx - 1, FLOOR + 4, z, DEAD_WOOD)
	build.box(sx - 1, FLOOR + 5, 15, sx - 1, FLOOR + 5, 20, DEAD_WOOD)
	build.set(sx - 1, FLOOR + 4, 17, COBWEB)
	build.set(sx - 1, FLOOR + 4, 18, COBWEB)
	build.set(sx - 2, FLOOR, 21, PEDESTAL)
	build.set(sx - 2, FLOOR + 1, 21, JACK)

	build_pumpkin_patch(build)
	build_graveyard(build)
	build_haunted_house(build)
	build_stage(build)

	# A weather vane on the house ridge: the kinetic beat, spun by an entity
	# lw_maps registers, so the schematic only carries its mast.
	build.set(25, HOUSE_ATTIC_TOP + 6, 27, DEAD_WOOD)
	return build


# --------------------------------------------------------------------------
# 2. Snowy mountain
# --------------------------------------------------------------------------

SNOW_SIZE = (40, 28, 40)
# The causeway lands on the north face, at the trailhead — east of the tunnel
# axis, so a visitor arrives on the snow field and not in the cutting.
SNOW_SPAWN = (26, FLOOR, 37)

PEAK = (19.5, 19.5)                 # centre in x, z
PEAK_TOP = 23                       # local y of the summit plateau
SUMMIT_RADIUS = 4.0                 # the plateau the overlook deck sits on
SLOPE = 1.5                         # nodes of height lost per node of radius
PEAK_BASE_RADIUS = SUMMIT_RADIUS + (PEAK_TOP - SURFACE) / SLOPE

# The through-mountain tunnel runs north-south at this height and x range.
# Its z range stops short of the map edge so both mouths land on the cone's
# lower slope rather than opening onto flat snow.
SHORTCUT_Y = FLOOR + 1
SHORTCUT_X = (18, 21)
SHORTCUT_Z = (2, 37)
# The ice cave sits west of the shortcut and opens onto the west face.
ICE_CAVE = dict(x0=5, x1=13, z0=15, z1=23, y=FLOOR + 1)
# The mineshaft leaves the through-tunnel here and climbs to this height,
# where it meets the switchback.
SHAFT_Z0 = 12
SHAFT_TOP = FLOOR + 9


def peak_height(x: float, z: float) -> int:
	"""Top surface of the cone at (x, z), as a local y.

	Flat-topped on purpose: a true cone tapers to a single node and there is
	nowhere to stand, so the last four nodes of radius are a plateau and the
	overlook deck sits on it.
	"""
	radius = math.hypot(x - PEAK[0], z - PEAK[1])
	if radius <= SUMMIT_RADIUS:
		return PEAK_TOP
	if radius > PEAK_BASE_RADIUS:
		return SURFACE
	return max(SURFACE, PEAK_TOP - int((radius - SUMMIT_RADIUS) * SLOPE))


def peak_radius(y: int) -> float:
	"""Radius at which the cone's surface reaches local height y."""
	return SUMMIT_RADIUS + max(0.0, (PEAK_TOP - y) / SLOPE)


def carve(build: Build, x0, y0, z0, x1, y1, z1, *, floor=None, ceiling=None) -> None:
	"""Hollow a passage and give it a floor, so a tunnel is never a pit."""
	build.clear(x0, y0, z0, x1, y1, z1)
	if floor is not None:
		build.box(x0, y0 - 1, z0, x1, y0 - 1, z1, floor)
	if ceiling is not None:
		build.box(x0, y1 + 1, z0, x1, y1 + 1, z1, ceiling)


def build_mountain_mass(build: Build) -> None:
	for x in range(build.sx):
		for z in range(build.sz):
			top = peak_height(x, z)
			if top <= SURFACE:
				continue
			build.box(x, SURFACE + 1, z, x, top, z, STONE)
			# Snow line: a cap, plus a dusting on the shoulders below it.
			if top >= FLOOR + 9:
				build.set(x, top, z, SNOW)
				if top >= FLOOR + 12:
					build.set(x, top - 1, z, SNOW)
			elif (x * 5 + z * 3) % 7 == 0:
				build.set(x, top, z, SNOW)


def build_switchback(build: Build) -> list[tuple[int, int, int]]:
	"""A spiral shelf cut into the cone, one node up every four steps.

	Returns the path so the caller can hang a rail off its outer edge and put
	the mineshaft mouth exactly where a climber walks past it.
	"""
	path: list[tuple[int, int, int]] = []
	y = FLOOR
	angle = math.pi / 2                 # start on the north face, at the causeway
	step = 0
	while y <= PEAK_TOP:
		radius = peak_radius(y) - 1.0
		x = int(round(PEAK[0] + radius * math.cos(angle)))
		z = int(round(PEAK[1] + radius * math.sin(angle)))
		if not path or path[-1] != (x, y, z):
			path.append((x, y, z))
		# Three nodes wide, cut back into the hillside and cleared overhead.
		for dx in (-1, 0, 1):
			for dz in (-1, 0, 1):
				build.set(x + dx, y, z + dz, PACKED_SNOW)
				build.clear(x + dx, y + 1, z + dz, x + dx, y + 3, z + dz)
		step += 1
		if step % 4 == 0:
			y += 1
		angle += 1.0 / max(radius, 3.0)
	return path


def build_summit(build: Build) -> None:
	"""The overlook: a decked plateau with a rail, reached by the trail."""
	y = PEAK_TOP
	cx, cz = int(PEAK[0]), int(PEAK[1])
	reach = int(SUMMIT_RADIUS)
	for x in range(cx - reach, cx + reach + 2):
		for z in range(cz - reach, cz + reach + 2):
			if math.hypot(x - PEAK[0], z - PEAK[1]) > SUMMIT_RADIUS:
				continue
			build.set(x, y, z, PACKED_SNOW)
			build.clear(x, y + 1, z, x, y + 4, z)
			# Rail on the outermost ring only, with gaps to walk through.
			if (math.hypot(x - PEAK[0], z - PEAK[1]) > SUMMIT_RADIUS - 1.0
					and (x + z) % 2 == 0):
				build.set(x, y + 1, z, FENCE)
	build.set(cx, y + 1, cz, PEDESTAL)
	build.set(cx, y + 2, cz, LAMP)
	build.set(cx + 1, y + 1, cz + 1, TORCH)


def build_shortcut(build: Build) -> None:
	"""North-south tunnel, all the way through the mountain at trail level."""
	x0, x1 = SHORTCUT_X
	z0, z1 = SHORTCUT_Z
	y = SHORTCUT_Y
	carve(build, x0, y, z0, x1, y + 2, z1, floor=STONE)
	for z in range(z0 + 2, z1 - 2, 7):
		build.set(x0, y + 2, z, TORCH)
		build.set(x1, y + 2, z + 3, TORCH)
	# Portals, so both mouths read as a way in rather than as a crack.
	for z in (z0, z1):
		build.walls(x0 - 1, y, z, x1 + 1, y + 3, z, BRICK)
		build.clear(x0, y, z, x1, y + 2, z)
	# A slab ramp at each mouth, up from the snow field to the tunnel floor,
	# so the step in is half a node rather than a hop.
	for z, step, facing in ((z0 - 1, -1, NORTH), (z1 + 1, 1, SOUTH)):
		for offset in (0, step):
			build.box(x0, y - 1, z + offset, x1, y - 1, z + offset, SNOW_SLAB)
			build.clear(x0, y, z + offset, x1, y + 2, z + offset)
		build.box(x0, y - 2, z + step, x1, y - 2, z + step, PACKED_SNOW, facing)
	# A packed-ice floor band in the middle, where it passes the ice cave.
	build.box(x0, y - 1, 16, x1, y - 1, 24, PACKED_ICE)


def build_ice_cave(build: Build) -> None:
	c = ICE_CAVE
	y = c["y"]
	carve(build, c["x0"], y, c["z0"], c["x1"], y + 3, c["z1"], floor=PACKED_ICE)
	# Blue glass walls and a few frozen columns.
	build.walls(c["x0"] - 1, y, c["z0"] - 1, c["x1"] + 1, y + 3, c["z1"] + 1, ICE)
	build.box(c["x0"] - 1, y + 4, c["z0"] - 1, c["x1"] + 1, y + 4, c["z1"] + 1, PACKED_ICE)
	for cx, cz in ((c["x0"] + 2, c["z0"] + 2), (c["x1"] - 2, c["z1"] - 2),
			(c["x0"] + 2, c["z1"] - 2)):
		build.box(cx, y, cz, cx, y + 3, cz, ICE)
	build.set(c["x0"] + 4, y + 3, c["z0"] + 4, HIDDEN_LIGHT)
	build.set(c["x0"] + 1, y + 2, c["z0"] + 1, TORCH)
	build.set(c["x1"] - 1, y + 2, c["z1"] - 1, TORCH)

	# Mouth on the west face, so the cave can be entered from outside.
	carve(build, 0, y, c["z0"] + 3, c["x0"] - 1, y + 2, c["z0"] + 5, floor=STONE)
	build.set(2, y + 2, c["z0"] + 3, TORCH)
	# Link east into the through-mountain shortcut.
	carve(build, c["x1"] + 1, y, c["z0"] + 3, SHORTCUT_X[0] - 1, y + 2,
		c["z0"] + 5, floor=STONE)


def build_mineshaft(build: Build, path) -> None:
	"""Timbered stair from the through-tunnel up to a mouth on the trail.

	The mouth is not a constant: it is whichever tread of the switchback the
	shaft can reach at ``SHAFT_TOP``, found from the path the spiral actually
	took. Hard-coding a position here would put the exit a few nodes off the
	trail the first time the cone's slope changed, and nothing would say so.
	"""
	x0, x1 = SHORTCUT_X
	y = SHORTCUT_Y
	z0 = SHAFT_Z0
	# A landing off the east wall of the through-tunnel.
	carve(build, x1 + 1, y, z0, x1 + 3, y + 2, z0 + 1, floor=PLANKS)
	build.clear(x1, y, z0, x1, y + 2, z0 + 1)

	# The climb: one tread per node north, timbered every third step.
	x_lo, x_hi = x1 + 2, x1 + 3
	rises = SHAFT_TOP - y
	for index in range(rises + 1):
		ty = y + index
		tz = z0 + 1 + index
		build.box(x_lo, ty, tz, x_hi, ty, tz, PLANK_STAIR, NORTH)
		build.clear(x_lo, ty + 1, tz, x_hi, ty + 4, tz)
		if index % 3 == 0:
			build.box(x_lo - 1, ty + 1, tz, x_lo - 1, ty + 3, tz, BEAM)
			build.box(x_hi + 1, ty + 1, tz, x_hi + 1, ty + 3, tz, BEAM)
		if index % 4 == 0:
			build.set(x_hi + 1, ty + 2, tz, TORCH)

	# The gallery out to the trail. Both ends are at SHAFT_TOP, so it is an
	# L of two level legs: east in x, then north or south in z.
	head = (x_hi, SHAFT_TOP, z0 + 1 + rises)
	mouth = min((p for p in path if p[1] == SHAFT_TOP),
		key=lambda p: abs(p[0] - head[0]) + abs(p[2] - head[2]), default=None)
	if mouth is None:
		raise SystemExit("mineshaft: the switchback never passes y=%d" % SHAFT_TOP)
	mx, my, mz = mouth
	lo_x, hi_x = sorted((head[0], mx))
	carve(build, lo_x, my, head[2], hi_x, my + 2, head[2] + 1, floor=PLANKS)
	lo_z, hi_z = sorted((head[2], mz))
	carve(build, mx - 1, my, lo_z, mx + 1, my + 2, hi_z, floor=PLANKS)
	# A timber portal where the gallery breaks out onto the trail.
	for dz in (-2, 2):
		build.box(mx - 1, my, mz + dz, mx + 1, my + 3, mz + dz, BEAM)
	build.clear(mx - 1, my, mz - 1, mx + 1, my + 2, mz + 1)
	build.set(mx - 1, my + 2, mz - 1, TORCH)


def build_snow_apron(build: Build) -> None:
	"""The flat ground the mountain sits on: snow field, pines, trailhead."""
	build.box(0, SURFACE, 0, build.sx - 1, SURFACE, build.sz - 1, SNOW)
	# Trailhead plaza under the causeway on the north face.
	build.box(24, SURFACE, build.sz - 5, 29, SURFACE, build.sz - 1, PACKED_SNOW)
	# A kerb of snow stairs where the causeway lands, facing the mountain.
	build.box(24, SURFACE, build.sz - 6, 29, SURFACE, build.sz - 6, SNOW_STAIR, SOUTH)
	build.set(24, FLOOR, build.sz - 2, PEDESTAL)
	build.set(24, FLOOR + 1, build.sz - 2, LAMP)
	for x, z in ((4, 5), (9, 3), (33, 6), (36, 14), (5, 33), (34, 33), (12, 36)):
		height = 4 + (x + z) % 3
		for offset in range(height):
			build.set(x, FLOOR + offset, z, BEAM)
		for level, spread in ((height - 3, 2), (height - 2, 2), (height - 1, 1)):
			if level < 0:
				continue
			for dx in range(-spread, spread + 1):
				for dz in range(-spread, spread + 1):
					if abs(dx) + abs(dz) > spread:
						continue
					if dx == 0 and dz == 0:
						continue
					build.set(x + dx, FLOOR + level, z + dz, PINE_LEAVES)
		build.set(x, FLOOR + height, z, PINE_LEAVES)


def build_snow_mountain() -> Build:
	sx, sy, sz = SNOW_SIZE
	build = Build(sx, sy, sz)
	build.ground(SNOW, sub=STONE)
	build_snow_apron(build)
	build_mountain_mass(build)
	path = build_switchback(build)
	build_summit(build)
	# Interiors last: they cut through whatever the cone put in their way.
	build_shortcut(build)
	build_ice_cave(build)
	build_mineshaft(build, path)
	return build


# --------------------------------------------------------------------------
# 3. Giant fruit garden
# --------------------------------------------------------------------------

FRUIT_SIZE = (40, 20, 40)
# The causeway lands on the west face.
FRUIT_SPAWN = (2, FLOOR, 21)

MELON = (11, FLOOR + 5, 12)         # centre of the walk-in watermelon
MELON_RADIUS = 6
BOWL = (28, FLOOR, 11)              # the sliced-melon amphitheatre


def build_watermelon(build: Build) -> None:
	"""The centrepiece: an 13x11x13 melon you walk into.

	Rind, stripes and flesh are all wool — the dye palette fakes every fruit
	on this map, which is why the pack adds no fruit nodes at all.
	"""
	cx, cy, cz = MELON
	build.sphere(cx, cy, cz, MELON_RADIUS, wool("dark_green"),
		sy=MELON_RADIUS - 1, shell=1)
	# Stripes: meridians of the lighter green, drawn on the rind only.
	for x in range(cx - MELON_RADIUS, cx + MELON_RADIUS + 1):
		for y in range(cy - MELON_RADIUS, cy + MELON_RADIUS + 1):
			for z in range(cz - MELON_RADIUS, cz + MELON_RADIUS + 1):
				if build.get(x, y, z) != wool("dark_green"):
					continue
				angle = math.atan2(z - cz, x - cx)
				if int((angle + math.pi) / (math.pi / 6)) % 2 == 0:
					build.set(x, y, z, wool("green"))
	# Flesh and seeds, one shell in from the rind.
	build.sphere(cx, cy, cz, MELON_RADIUS - 1, wool("red"),
		sy=MELON_RADIUS - 2, shell=1)
	for index, (dx, dy, dz) in enumerate((
			(3, 1, 1), (-3, 0, 2), (1, 2, -3), (-2, -2, 2),
			(2, -1, 3), (0, 3, 2), (-1, -3, -2), (3, 2, -1))):
		build.set(cx + dx, cy + dy, cz + dz, wool("black"))
	# Hollow the middle, then square the bottom of the cavity off into a room
	# with a floor you can stand on: an ellipsoid alone leaves the lowest
	# courses solid, which is exactly where a visitor walks in.
	build.sphere(cx, cy, cz, MELON_RADIUS - 2, AIR, sy=MELON_RADIUS - 3)
	build.clear(cx - 3, FLOOR + 1, cz - 3, cx + 3, FLOOR + 5, cz + 3)
	build.box(cx - 3, FLOOR, cz - 3, cx + 3, FLOOR, cz + 3, wool("pink"))
	build.set(cx, cy + 1, cz, HIDDEN_LIGHT)
	build.set(cx - 2, cy, cz - 2, HIDDEN_LIGHT)
	# Doorway on the path side (west), cut through rind and flesh together.
	build.clear(cx - MELON_RADIUS, FLOOR, cz - 1, cx - 2, FLOOR + 2, cz + 1)
	build.box(cx - MELON_RADIUS, FLOOR - 1, cz - 1, cx - 2, FLOOR - 1, cz + 1, DIRT)
	build.set(cx - MELON_RADIUS, FLOOR + 3, cz, wool("black"))
	# A stem and a curl of vine on top.
	build.set(cx, cy + MELON_RADIUS - 1, cz, wool("brown"))
	build.set(cx, cy + MELON_RADIUS, cz, wool("brown"))
	build.set(cx + 1, cy + MELON_RADIUS, cz, VINE, 2)


BOWL_RADIUS = 7
# How far the bowl is set into the ground. Sunk, its rim is a single step off
# the path; standing proud it would be a five-node wall with the seating on
# the wrong side of it.
BOWL_SINK = 3
BOWL_BOTTOM = 1


def bowl_surface(distance: float) -> int:
	"""Local y of the bowl's inner face at `distance` from its centre.

	One node of rise every 2.2 of radius, so the terraces are steps a walker
	takes without jumping: the amphitheatre has to be usable, not just round.
	"""
	return FLOOR - BOWL_SINK + int(distance / 2.2)


def build_bowl(build: Build) -> None:
	"""Half a melon, cut face up, set into the lawn as a picnic amphitheatre."""
	cx, _, cz = BOWL
	for x in range(cx - BOWL_RADIUS, cx + BOWL_RADIUS + 1):
		for z in range(cz - BOWL_RADIUS, cz + BOWL_RADIUS + 1):
			distance = math.hypot(x - cx, z - cz)
			if distance > BOWL_RADIUS:
				continue
			top = bowl_surface(distance)
			build.box(x, BOWL_BOTTOM, z, x, top, z, wool("red"))
			build.clear(x, top + 1, z, x, FLOOR + 6, z)
			# The rind: a ring of dark green standing one course proud of the
			# flesh, so the silhouette from the path is a melon half.
			if distance > BOWL_RADIUS - 1.5:
				build.box(x, BOWL_BOTTOM, z, x, top + 1, z, wool("dark_green"))
	# Seeds, pressed into the terraces where they read from above.
	for dx, dz in ((-4, 0), (0, -4), (4, 0), (0, 4), (-3, -3), (3, 3)):
		build.set(cx + dx, bowl_surface(math.hypot(dx, dz)), cz + dz, wool("black"))
	# Two pairs of theater seats on a terrace, looking inward.
	for dz in (-1, 1):
		seat_y = bowl_surface(math.hypot(3, dz)) + 1
		build.set(cx - 3, seat_y, cz + dz, SEAT, EAST)
		build.set(cx + 3, seat_y, cz + dz, SEAT, WEST)
	build.set(cx - 1, bowl_surface(math.hypot(1, 1)) + 1, cz - 1, UPLIGHT)
	# A notch in the rind on the path side, and a dirt spur up to the spine.
	build.clear(cx - 1, bowl_surface(BOWL_RADIUS) + 1, cz + BOWL_RADIUS - 1,
		cx + 1, FLOOR + 6, cz + BOWL_RADIUS + 1)
	build.box(cx - 1, SURFACE, cz + BOWL_RADIUS + 1, cx + 1, SURFACE, 20, DIRT)


def build_orchard(build: Build) -> None:
	"""The supporting giants, each a readable silhouette from the path."""
	# Apple: sphere, stem, one oversized leaf.
	build.sphere(9, FLOOR + 5, 30, 4, wool("red"))
	build.box(9, FLOOR + 9, 30, 9, FLOOR + 10, 30, wool("brown"))
	build.box(10, FLOOR + 10, 30, 12, FLOOR + 10, 31, LEAVES)
	build.box(9, FLOOR, 30, 9, FLOOR, 30, wool("brown"))

	# Grape cluster: overlapping spheres hung under a canopy.
	for index, (dx, dy, dz) in enumerate((
			(0, 0, 0), (3, 0, 1), (-3, 0, 1), (1, -3, -1), (-2, -3, 0),
			(0, -6, 1), (2, -6, -1))):
		build.sphere(21 + dx, FLOOR + 10 + dy, 30 + dz, 2, wool("violet"))
	build.box(19, FLOOR + 12, 28, 24, FLOOR + 12, 32, LEAVES)
	for x, z in ((19, 28), (24, 32), (19, 32), (24, 28)):
		build.box(x, FLOOR, z, x, FLOOR + 11, z, BEAM)
		build.set(x, FLOOR + 6, z, VINE, 2)

	# Banana: an arc of yellow with a brown tip at each end.
	for index in range(11):
		angle = math.pi * index / 10.0
		x = 30 + index
		y = FLOOR + 1 + int(round(4.0 * math.sin(angle)))
		build.box(x, y, 29, x, y + 2, 31, wool("yellow"))
	build.box(30, FLOOR + 1, 29, 30, FLOOR + 1, 31, wool("brown"))
	build.box(40 - 1, FLOOR + 1, 29, 40 - 1, FLOOR + 1, 31, wool("brown"))

	# Citrus: sphere with a pith rind and a couple of leaves.
	build.sphere(33, FLOOR + 4, 16, 4, wool("orange"))
	build.sphere(33, FLOOR + 4, 16, 2, wool("white"))
	build.box(33, FLOOR + 8, 16, 33, FLOOR + 9, 16, wool("brown"))
	build.box(34, FLOOR + 9, 16, 36, FLOOR + 9, 17, LEAVES)

	# Strawberry: a cone of red, seeded white, with a leafy crown.
	for level in range(7):
		radius = 4 - level * 0.55
		for x in range(1, 12):
			for z in range(30, 40):
				if math.hypot(x - 6, z - 35) <= radius:
					build.set(x, FLOOR + 10 + level, z, wool("red"))
	build.sphere(6, FLOOR + 10, 35, 4.6, wool("red"), sy=1)
	for dx, dz in ((-3, 0), (2, 2), (0, -3), (3, -1), (-1, 3)):
		build.set(6 + dx, FLOOR + 11, 35 + dz, wool("white"))
	build.box(3, FLOOR + 17, 32, 9, FLOOR + 17, 38, LEAVES)
	build.box(6, FLOOR, 35, 6, FLOOR + 9, 35, BEAM)


def build_juice_river(build: Build) -> None:
	"""A shallow channel of translucent juice from the bowl to a basin."""
	build.box(20, SURFACE, 10, 20, SURFACE, 12, DIRT)
	for x in range(16, 22):
		build.box(x, SURFACE, 10, x, SURFACE, 12, STONE)
		build.box(x, SURFACE, 11, x, SURFACE, 11, JUICE_RED)
	for z in range(4, 11):
		build.box(15, SURFACE, z, 17, SURFACE, z, STONE)
		build.set(16, SURFACE, z, JUICE_GREEN)
	# A basin where the two meet, edged so nobody walks into it by accident.
	build.box(14, SURFACE, 2, 18, SURFACE, 5, STONE)
	build.box(15, SURFACE, 3, 17, SURFACE, 4, JUICE_RED)
	for x in range(13, 20, 2):
		build.set(x, FLOOR, 1, FENCE)


def build_fruit_garden() -> Build:
	sx, sy, sz = FRUIT_SIZE
	build = Build(sx, sy, sz)
	build.ground(GRASS)

	# Dirt paths: an east-west spine from the causeway, one north spur.
	build.box(0, SURFACE, 20, sx - 1, SURFACE, 22, DIRT)
	build.box(18, SURFACE, 22, 20, SURFACE, sz - 1, DIRT)
	build.box(18, SURFACE, 4, 20, SURFACE, 20, DIRT)

	build_watermelon(build)
	build_bowl(build)
	build_orchard(build)
	build_juice_river(build)

	# Canopy over the spine: beams, oversized leaves, hanging vines.
	for x in range(4, sx - 3, 6):
		for z in (19, 23):
			build.box(x, FLOOR, z, x, FLOOR + 4, z, BEAM)
		build.box(x - 1, FLOOR + 5, 19, x + 1, FLOOR + 5, 23, LEAVES)
		build.set(x, FLOOR + 4, 19, VINE, 2)
		build.set(x, FLOOR + 4, 23, VINE, 0)
	build.set(3, FLOOR, 20, PEDESTAL)
	build.set(3, FLOOR + 1, 20, wool("pink"))
	return build


# --------------------------------------------------------------------------
# 4. Lighthouse tide
# --------------------------------------------------------------------------

LIGHTHOUSE_SIZE = (36, 24, 36)
# The causeway lands on the north face, on the shore promenade.
LIGHTHOUSE_SPAWN = (27, FLOOR, 34)

# The lagoon's surface is local y 3, level with the shore and with the beach
# lw_world lays round the island, so the water inside the footprint is three
# deep and a tunnel on its bed has water over its roof.
TIDE_TOP = SURFACE

TOWER = (8, 8)                      # centre, in x and z
TOWER_RADIUS = 6.5                  # outer face of the wall
TOWER_WALL = 1.0
NEWEL_RADIUS = 1.5                  # the solid core the stair winds round
STAIR_BASE = FLOOR                  # first tread
STAIR_PITCH = 5                     # rise per full turn: four nodes of head room
# Where the first tread is, as an angle from +x towards +z. The door faces
# north (+z), so starting the flight just past it leaves the doorway opening
# onto floor rather than onto the underside of the last turn.
STAIR_START = math.pi / 2 + 0.7
LANTERN_FLOOR = FLOOR + 15          # the gallery deck, and the top of the stair
LANTERN_RADIUS = 3.5                # the glass lantern on it
GALLERY_RADIUS = 7.5                # the railed walkway round the lantern

JETTY = dict(x0=20, x1=24, z0=7, z1=26)
JETTY_HEAD = dict(x0=18, x1=26, z0=3, z1=7)
JETTY_DECK = SURFACE + 1            # one proud of the water, on piles
# Two glass-bottomed tide pools set into the jetty deck. The first is over the
# tunnel, so its glass is the tunnel's roof.
TIDE_POOLS = ((21, 23, 16, 18), (21, 23, 10, 12))

# The tunnel runs east-west under the lagoon and under the jetty, from a
# stairwell on the west spine to one on the east ledge. You walk on local y 0
# with your head at y 2 and the lagoon's surface in the roof.
TIDE_TUNNEL = dict(x0=13, x1=30, z0=16, z1=18, floor=0)
TUNNEL_WEST_STAIR = 10              # first tread down, west end
TUNNEL_EAST_STAIR = 31              # first tread up, east end


def tower_angle(x: float, z: float) -> float:
	"""Angle round the tower, measured from where the stair starts."""
	angle = math.atan2(z - TOWER[1], x - TOWER[0]) - STAIR_START
	return angle % (2 * math.pi)


def tower_radius(x: float, z: float) -> float:
	return math.hypot(x - TOWER[0], z - TOWER[1])


def stair_treads(x: int, z: int) -> list[int]:
	"""Every tread height of the spiral stair in column (x, z), bottom up.

	The stair is a helicoid: a cell at angle a has a tread on each turn, at
	STAIR_BASE + (a / 2pi + turn) * STAIR_PITCH. Neighbouring cells round the
	annulus are never more than one node apart, so the whole flight is walkable
	without a jump, and each turn clears the one below by four nodes.

	The last two rises would put a visitor's head through the lantern deck, so
	only the outer lane of the flight takes them — up through a hatch in the
	gallery, outside the lantern's glass — and the inner lane, under the lantern
	itself, stops short and leaves its floor whole.
	"""
	radius = tower_radius(x, z)
	if not (NEWEL_RADIUS < radius <= TOWER_RADIUS - TOWER_WALL):
		return []
	top = LANTERN_FLOOR if radius > LANTERN_RADIUS else LANTERN_FLOOR - 2
	fraction = tower_angle(x, z) / (2 * math.pi)
	treads = []
	turn = 0
	while True:
		y = STAIR_BASE + int((fraction + turn) * STAIR_PITCH)
		if y >= top:
			return treads
		treads.append(y)
		turn += 1


def build_tide_ground(build: Build) -> None:
	"""A lagoon three deep, with land round three sides of it."""
	sx, _, sz = build.sx, build.sy, build.sz
	# Everything starts as lagoon: a sand bed on local y 0 and water to the top.
	build.box(0, 0, 0, sx - 1, 0, sz - 1, SAND)
	build.box(0, 1, 0, sx - 1, TIDE_TOP, sz - 1, WATER)

	def land(x: int, z: int) -> bool:
		return (z >= 27                                   # north shore
			or x <= 14 and z >= 12                        # west spine
			or x >= 30                                    # east ledge
			or math.hypot(x - 8, z - 8) <= 8.5)           # tower headland

	for x in range(sx):
		for z in range(sz):
			if not land(x, z):
				continue
			build.box(x, 0, z, x, SURFACE - 2, z, STONE)
			build.set(x, SURFACE - 1, z, DIRT)
			# A sand margin wherever the land meets the water.
			wet = any(not land(x + dx, z + dz) and build.inside(x + dx, 0, z + dz)
				for dx in (-1, 0, 1) for dz in (-1, 0, 1))
			build.set(x, SURFACE, z, SAND if wet else GRASS)

	# Paths: a promenade along the shore from the causeway, down the spine to
	# the lighthouse door, and down the east ledge to the far tunnel mouth.
	build.box(3, SURFACE, 29, sx - 1, SURFACE, 31, PAVING)
	build.box(26, SURFACE, 29, 28, SURFACE, sz - 1, PAVING)
	build.box(7, SURFACE, 15, 9, SURFACE, 31, PAVING)
	build.box(32, SURFACE, 16, 34, SURFACE, 31, PAVING)
	for x, z in ((25, 34), (29, 34), (10, 28), (6, 20), (35, 22)):
		build.set(x, FLOOR, z, UPLIGHT)
	# Rocks in the shallows, so the lagoon reads as a tide line, not a pool.
	for x, z in ((16, 3), (28, 1), (17, 24), (28, 22), (12, 1)):
		build.box(x, 1, z, x, TIDE_TOP, z, STONE)


def build_lighthouse_tower(build: Build) -> None:
	cx, cz = TOWER
	reach = int(GALLERY_RADIUS) + 1
	columns = [(x, z) for x in range(cx - reach, cx + reach + 1)
		for z in range(cz - reach, cz + reach + 1)]

	# The floor, the shell and the core. Painted in bands, three courses of
	# white to three of red, like every lighthouse a child has drawn.
	for x, z in columns:
		radius = tower_radius(x, z)
		if radius > TOWER_RADIUS:
			continue
		build.set(x, SURFACE, z, POLISHED)
		build.clear(x, FLOOR, z, x, LANTERN_FLOOR - 1, z)
		if radius > TOWER_RADIUS - TOWER_WALL:
			for y in range(FLOOR, LANTERN_FLOOR):
				band = "white" if (y - FLOOR) // 3 % 2 == 0 else "red"
				build.set(x, y, z, wool(band))
		elif radius <= NEWEL_RADIUS:
			build.box(x, FLOOR, z, x, LANTERN_FLOOR - 1, z, BRICK)

	# Windows at the four compass points, above the door.
	for y0 in (FLOOR + 4, FLOOR + 9):
		for dx, dz in ((0, 6), (6, 0), (0, -6), (-6, 0)):
			build.box(cx + dx, y0, cz + dz, cx + dx, y0 + 1, cz + dz, GLASS)

	# The door, north, facing the spine path.
	build.clear(cx - 1, FLOOR, cz + 6, cx + 1, FLOOR + 1, cz + 6)
	build.box(cx - 1, FLOOR + 2, cz + 6, cx + 1, FLOOR + 2, cz + 6, GOLD)

	# The spiral stair. A tread one up from its neighbour is a stair node with
	# its low half towards that neighbour, so each rise is two half steps.
	treads = {}
	for x, z in columns:
		for y in stair_treads(x, z):
			treads[(x, y, z)] = True
	for (x, y, z) in treads:
		facing = None
		for dx, dz, facedir in ((0, 1, NORTH), (1, 0, EAST), (0, -1, SOUTH), (-1, 0, WEST)):
			if (x - dx, y - 1, z - dz) in treads:
				facing = facedir
				break
		if facing is None:
			build.set(x, y, z, PLANKS)
		else:
			build.set(x, y, z, PLANK_STAIR, facing)

	# The lantern deck, open only over the stair's last two rises: the hatch
	# a visitor climbs out of onto the gallery.
	def hatch(x: int, z: int) -> bool:
		heights = stair_treads(x, z)
		return bool(heights) and heights[-1] >= LANTERN_FLOOR - 2

	deck = LANTERN_FLOOR
	for x, z in columns:
		radius = tower_radius(x, z)
		if radius > GALLERY_RADIUS:
			continue
		if not hatch(x, z):
			build.set(x, deck, z, POLISHED if radius <= TOWER_RADIUS else PLANKS)
		if radius > GALLERY_RADIUS - 1.0 and (x + z) % 2 == 0:
			build.set(x, deck + 1, z, FENCE)
		if LANTERN_RADIUS - 1.0 < radius <= LANTERN_RADIUS:
			build.box(x, deck + 1, z, x, deck + 3, z, GLASS)
		if radius <= LANTERN_RADIUS:
			build.set(x, deck + 4, z, wool("black"))
	# A door in the glass on the seaward side, opposite the hatch.
	build.clear(cx, deck + 1, cz - 3, cx, deck + 2, cz - 3)
	# The lamp, on the core, with the beam entity one above it (lw_maps).
	build.set(cx, deck + 1, cz, LAMP)
	build.set(cx, deck + 4, cz, GOLD)


def build_jetty(build: Build) -> None:
	"""A plank jetty on piles, one node proud of the lagoon."""
	for part in (JETTY, JETTY_HEAD):
		build.box(part["x0"], JETTY_DECK, part["z0"], part["x1"], JETTY_DECK,
			part["z1"], PLANKS)
		build.clear(part["x0"], JETTY_DECK + 1, part["z0"], part["x1"],
			JETTY_DECK + 3, part["z1"])
	# Piles at the corners and down both edges, clear of the tunnel crossing.
	for x in (JETTY["x0"], JETTY["x1"]):
		for z in (8, 12, 22, 26):
			build.box(x, 1, z, x, JETTY_DECK - 1, z, BEAM)
	for x in (JETTY_HEAD["x0"], JETTY_HEAD["x1"]):
		for z in (JETTY_HEAD["z0"], JETTY_HEAD["z1"]):
			build.box(x, 1, z, x, JETTY_DECK - 1, z, BEAM)
	# Step up from the shore.
	build.box(JETTY["x0"], JETTY_DECK, JETTY["z1"], JETTY["x1"], JETTY_DECK,
		JETTY["z1"], PLANK_STAIR, SOUTH)
	# Rails down both sides, with gaps, and a lamp post and a bench at the head.
	for z in range(JETTY["z0"] + 1, JETTY["z1"], 3):
		build.set(JETTY["x0"], JETTY_DECK + 1, z, FENCE)
		build.set(JETTY["x1"], JETTY_DECK + 1, z, FENCE)
	build.box(JETTY_HEAD["x0"], JETTY_DECK + 1, JETTY_HEAD["z0"],
		JETTY_HEAD["x0"], JETTY_DECK + 2, JETTY_HEAD["z0"], BEAM)
	build.set(JETTY_HEAD["x0"], JETTY_DECK + 3, JETTY_HEAD["z0"], LAMP)
	build.box(JETTY_HEAD["x0"] + 2, JETTY_DECK + 1, JETTY_HEAD["z0"],
		JETTY_HEAD["x0"] + 4, JETTY_DECK + 1, JETTY_HEAD["z0"], PLANK_SLAB)

	# The tide pools: water one node deep, on glass, in the deck.
	for x0, x1, z0, z1 in TIDE_POOLS:
		build.box(x0, JETTY_DECK, z0, x1, JETTY_DECK, z1, WATER)
		build.box(x0, JETTY_DECK - 1, z0, x1, JETTY_DECK - 1, z1, GLASS)


def build_tide_tunnel(build: Build) -> None:
	"""A glass tube along the lagoon bed, under the jetty and out the far side."""
	t = TIDE_TUNNEL
	floor = t["floor"]
	x0, x1, z0, z1 = t["x0"], t["x1"], t["z0"], t["z1"]
	# Walls and roof first, then hollow them: glass where there is water
	# outside, whatever was there already (shore, pile) where there is not.
	for x in range(x0, x1 + 1):
		for z in range(z0 - 1, z1 + 2):
			for y in range(floor + 1, TIDE_TOP + 1):
				if build.get(x, y, z) == WATER:
					build.set(x, y, z, GLASS)
	build.box(x0, floor, z0, x1, floor, z1, POLISHED)
	build.clear(x0, floor + 1, z0, x1, floor + 2, z1)
	# The roof is glass the whole way under the lagoon, including the pool's
	# floor, which is the same node.
	for x in range(x0, x1 + 1):
		for z in range(z0, z1 + 1):
			if build.get(x, TIDE_TOP, z) not in (GLASS, GRASS, SAND, PAVING, DIRT):
				build.set(x, TIDE_TOP, z, GLASS)
	for x in range(x0 + 2, x1, 5):
		build.set(x, floor + 1, z0, UPLIGHT)
		build.set(x + 2, floor + 1, z1, UPLIGHT)

	# Stairwells at both ends, three treads each, open to the sky.
	for x, y in ((TUNNEL_WEST_STAIR, floor + 2), (TUNNEL_WEST_STAIR + 1, floor + 1),
			(TUNNEL_WEST_STAIR + 2, floor)):
		build.box(x, y, z0, x, y, z1, PLANK_STAIR if y > floor else POLISHED, WEST)
		build.clear(x, y + 1, z0, x, SURFACE + 3, z1)
	for x, y in ((TUNNEL_EAST_STAIR, floor), (TUNNEL_EAST_STAIR + 1, floor + 1),
			(TUNNEL_EAST_STAIR + 2, floor + 2)):
		build.box(x, y, z0, x, y, z1, PLANK_STAIR if y > floor else POLISHED, EAST)
		build.clear(x, y + 1, z0, x, SURFACE + 3, z1)
	# A kerb of fence round each stairwell, open on the side you walk in from.
	for x0_, x1_, open_x in ((TUNNEL_WEST_STAIR, TUNNEL_WEST_STAIR + 2, TUNNEL_WEST_STAIR),
			(TUNNEL_EAST_STAIR, TUNNEL_EAST_STAIR + 2, TUNNEL_EAST_STAIR + 2)):
		for x in range(x0_, x1_ + 1):
			build.set(x, FLOOR, z0 - 1, FENCE)
			build.set(x, FLOOR, z1 + 1, FENCE)


def build_lighthouse_tide() -> Build:
	sx, sy, sz = LIGHTHOUSE_SIZE
	build = Build(sx, sy, sz)
	build_tide_ground(build)
	build_jetty(build)
	# The tunnel after the jetty, so it cuts through the pile it passes and
	# finds the pool's glass already in its roof.
	build_tide_tunnel(build)
	build_lighthouse_tower(build)
	# Where the causeway lands, a pair of lamp posts.
	for x in (25, 29):
		build.box(x, FLOOR, sz - 1, x, FLOOR + 1, sz - 1, BEAM)
		build.set(x, FLOOR + 2, sz - 1, LAMP)
	return build


# --------------------------------------------------------------------------
# 5. Crystal night bazaar
# --------------------------------------------------------------------------

BAZAAR_SIZE = (36, 16, 36)
# The causeway lands on the west face, at the mouth of the arcade.
BAZAAR_SPAWN = (1, FLOOR, 18)

# The arcade runs east-west through the middle of the map, in two vaulted
# wings either side of a domed rotunda.
AISLE_Z = (16, 20)                  # the walkway down the middle of the arcade
STALL_BACK = (13, 23)               # the stalls' back walls, and the vault's feet
VAULT_AXIS = 18                     # z of the barrel vault's crown line
VAULT_SPRING = FLOOR + 4            # local y the vault springs from
VAULT_RADIUS = 5.0                  # from the axis to the stall back walls
WEST_WING = (0, 10)
EAST_WING = (26, 35)
# Stall partitions: a timber post at each, a lantern on it, and a chase
# controller over the lantern.
STALL_POSTS = {WEST_WING: (1, 4, 7, 10), EAST_WING: (26, 29, 32, 35)}

ROTUNDA = (18, 18)                  # centre of the drum and dome, in x and z
DRUM_RADIUS = 7.5                   # outer face of the drum wall
RIM = FLOOR + 4                     # the terrace round the dome's foot
RIM_RADIUS = 8.5
DOME_RADIUS = 6.5
DOME_RISE = 3                       # the crown is this far above the rim

CISTERN = dict(x0=13, x1=23, z0=10, z1=22)
CISTERN_STAIR_X = (17, 19)
CISTERN_STAIR_Z = 14                # first tread down, from the rotunda floor
TERRACE_STAIR_X = (17, 19)
TERRACE_STAIR_Z = 30                # first tread up, from the north souk

LANTERN = "lw_maps:lantern"
LANTERN_OFF = "lw_maps:lantern_off"
BRICK_STAIR = "lw_nodes:stair_stone_brick"

# Stall awnings, round the loop in chase order.
AWNINGS = ("violet", "magenta", "cyan", "blue", "yellow", "orange", "pink", "green")


def rotunda_radius(x: float, z: float) -> float:
	return math.hypot(x - ROTUNDA[0], z - ROTUNDA[1])


def dome_height(radius: float) -> int:
	"""Local y of the dome's glass surface at `radius` from its centre.

	A paraboloid, low enough that its steepest point — the foot — rises less
	than a node per node, so a visitor walks up it from the rim rather than
	climbing it: that is the "dome you can walk onto".
	"""
	if radius > DOME_RADIUS:
		return RIM
	return RIM + int(DOME_RISE * (1 - (radius / DOME_RADIUS) ** 2) + 0.5)


def build_bazaar_ground(build: Build) -> None:
	sx, _, sz = build.sx, build.sy, build.sz
	build.ground(PAVING)
	# The arcade's floor and the rotunda's are polished; the souks either side
	# are paving with a sand border.
	build.box(0, SURFACE, STALL_BACK[0], sx - 1, SURFACE, STALL_BACK[1], POLISHED)
	for x in range(sx):
		for z in (0, sz - 1):
			build.set(x, SURFACE, z, SAND)
	for z in range(sz):
		for x in (0, sx - 1):
			if not STALL_BACK[0] <= z <= STALL_BACK[1]:
				build.set(x, SURFACE, z, SAND)


def build_vault(build: Build, x0: int, x1: int) -> None:
	"""A barrel vault over one wing: glass panes between violet ribs."""
	z0, z1 = STALL_BACK
	# Stall back walls, up to the springing line.
	for z in (z0, z1):
		build.box(x0, FLOOR, z, x1, VAULT_SPRING - 1, z, BRICK)
	for x in range(x0, x1 + 1):
		rib = x % 3 == 0 or x in (x0, x1)
		for z in range(z0, z1 + 1):
			for y in range(VAULT_SPRING, build.sy):
				d = math.hypot(z - VAULT_AXIS, y - VAULT_SPRING)
				if VAULT_RADIUS - 0.5 < d <= VAULT_RADIUS + 0.5:
					build.set(x, y, z, wool("violet") if rib else GLASS)
				elif d <= VAULT_RADIUS - 0.5:
					build.set(x, y, z, AIR)


def build_stalls(build: Build) -> list[tuple[int, int]]:
	"""Stalls both sides of both wings. Returns the post positions in chase
	order: west to east along the south side, back east to west along the
	north, so the lit pair runs round the arcade like a lap."""
	south = []
	north = []
	for wing, posts in STALL_POSTS.items():
		for x in posts:
			south.append((x, STALL_BACK[0] + 2))
			north.append((x, STALL_BACK[1] - 2))
	loop = sorted(south) + sorted(north, reverse=True)

	for side, (back, front, step) in (("south", (STALL_BACK[0], STALL_BACK[0] + 2, 1)),
			("north", (STALL_BACK[1], STALL_BACK[1] - 2, -1))):
		for wing, posts in STALL_POSTS.items():
			for left, right in zip(posts, posts[1:]):
				index = len([p for p in loop if p[0] < left])
				color = AWNINGS[index % len(AWNINGS)]
				# Counter across the front, awning over it, goods on the shelf.
				build.box(left + 1, FLOOR, front, right - 1, FLOOR, front, PLANK_SLAB)
				build.box(left + 1, VAULT_SPRING - 1, back + step, right - 1,
					VAULT_SPRING - 1, front, wool(color))
				build.box(left + 1, FLOOR, back + step, right - 1, FLOOR + 1,
					back + step, GLASS)
				build.set(left + 1, FLOOR + 2, back + step, wool(color))
		# Partition posts, from the back wall to the counter.
		for x, z in (p for p in loop if (p[1] < VAULT_AXIS) == (side == "south")):
			build.box(x, FLOOR, back + step, x, VAULT_SPRING - 1, back + step, BEAM)
			build.box(x, FLOOR, front, x, FLOOR + 1, front, BEAM)
	for index, (x, z) in enumerate(loop):
		build.set(x, FLOOR + 2, z, LANTERN_OFF)
		build.set(x, FLOOR + 3, z, CHASE, index % 8)
	return loop


def build_rotunda(build: Build) -> None:
	cx, cz = ROTUNDA
	reach = int(RIM_RADIUS) + 1
	columns = [(x, z) for x in range(cx - reach, cx + reach + 1)
		for z in range(cz - reach, cz + reach + 1)]
	surface = {(x, z): dome_height(rotunda_radius(x, z)) for x, z in columns}

	for x, z in columns:
		radius = rotunda_radius(x, z)
		# The wings' end arches are the rotunda's neighbours, not its floor.
		if radius > RIM_RADIUS or x <= WEST_WING[1] or x >= EAST_WING[0]:
			continue
		build.clear(x, FLOOR, z, x, build.sy - 1, z)
		if radius > DOME_RADIUS:
			# The drum, and the terrace on top of it that the dome sits in.
			if radius <= DRUM_RADIUS:
				build.box(x, FLOOR, z, x, RIM - 1, z, BRICK)
			build.set(x, RIM, z, POLISHED)
			landing = (TERRACE_STAIR_X[0] <= x <= TERRACE_STAIR_X[1] and z > cz)
			if radius > RIM_RADIUS - 1.0 and (x + z) % 2 == 1 and not landing:
				build.set(x, RIM + 1, z, FENCE)
			continue
		# The dome: glass from its own surface down to the lowest neighbour's,
		# so where it steps up a node there is no slot to see daylight through.
		top = surface[(x, z)]
		low = min(surface.get((x + dx, z + dz), RIM)
			for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1)))
		build.box(x, min(low, top), z, x, top, z, GLASS)
	# Crown and a ring of gold where the glass meets the stone.
	build.set(cx, surface[(cx, cz)], cz, wool("cyan"))
	for x, z in columns:
		if DOME_RADIUS - 1.0 < rotunda_radius(x, z) <= DOME_RADIUS:
			build.set(x, RIM, z, GOLD)
	# Under the dome: a hall lit from below, with doors to both wings.
	for z in range(AISLE_Z[0], AISLE_Z[1] + 1):
		for x in range(cx - reach, cx + reach + 1):
			if DOME_RADIUS < rotunda_radius(x, z) <= DRUM_RADIUS:
				build.clear(x, FLOOR, z, x, FLOOR + 2, z)
	for dx, dz in ((4, 4), (-4, 4), (4, -4), (-4, -4)):
		build.set(cx + dx, FLOOR, cz + dz, UPLIGHT)
	build.set(cx, FLOOR + 3, cz, HIDDEN_LIGHT)


def build_terrace_stair(build: Build) -> None:
	"""A straight flight from the north souk up onto the rim terrace."""
	x0, x1 = TERRACE_STAIR_X
	for step in range(RIM - FLOOR):
		z = TERRACE_STAIR_Z - step
		y = FLOOR + step
		if y > FLOOR:
			build.box(x0, FLOOR, z, x1, y - 1, z, BRICK)
		build.box(x0, y, z, x1, y, z, BRICK_STAIR, SOUTH)
		build.clear(x0, y + 1, z, x1, y + 3, z)
	for x in (x0 - 1, x1 + 1):
		for step in range(RIM - FLOOR):
			z = TERRACE_STAIR_Z - step
			build.box(x, FLOOR, z, x, FLOOR + step, z, BRICK)


def build_cistern(build: Build) -> None:
	"""Under the rotunda: a pillared cistern, lit only by torches."""
	c = CISTERN
	# Brick walls and floor; the roof is whatever floor is above it already.
	build.box(c["x0"] - 1, 0, c["z0"] - 1, c["x1"] + 1, SURFACE - 1, c["z1"] + 1, BRICK)
	build.box(c["x0"], 1, c["z0"], c["x1"], SURFACE - 1, c["z1"], AIR)
	# A still pool in the middle, sunk one below the walkway.
	cx, cz = ROTUNDA
	build.box(cx - 2, 0, cz - 1, cx + 2, 0, cz + 3, WATER)
	for px in range(c["x0"] + 2, c["x1"], 4):
		for pz in range(c["z0"] + 2, c["z1"], 4):
			if abs(px - cx) <= 2 and cz - 1 <= pz <= cz + 3:
				continue
			build.box(px, 1, pz, px, SURFACE - 1, pz, BRICK)
			build.set(px + 1, 2, pz, TORCH)
	# The stairwell down from the rotunda floor, three treads, with a kerb.
	x0, x1 = CISTERN_STAIR_X
	for step, y in enumerate((2, 1)):
		z = CISTERN_STAIR_Z - step
		build.box(x0, y, z, x1, y, z, PLANK_STAIR, NORTH)
		build.clear(x0, y + 1, z, x1, FLOOR + 2, z)
	build.clear(x0, 1, CISTERN_STAIR_Z - 2, x1, FLOOR + 2, CISTERN_STAIR_Z - 2)
	# The drum wall closes the far end; the near end is the way in.
	for z in range(CISTERN_STAIR_Z - 2, CISTERN_STAIR_Z + 1):
		build.set(x0 - 1, FLOOR, z, FENCE)
		build.set(x1 + 1, FLOOR, z, FENCE)


def build_souks(build: Build) -> None:
	"""The open squares north and south of the arcade: crystal clusters,
	awnings on poles, and lamp posts to find your way between them."""
	for x, z, color, height in ((5, 5, "cyan", 4), (30, 6, "violet", 5),
			(6, 30, "magenta", 5), (29, 31, "blue", 4), (12, 3, "blue", 3),
			(26, 32, "cyan", 3)):
		build.box(x, FLOOR, z, x, FLOOR + height - 1, z, GLASS)
		for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1)):
			build.box(x + dx, FLOOR, z + dz, x + dx, FLOOR + height - 3, z + dz,
				wool(color))
		build.set(x, FLOOR + height, z, HIDDEN_LIGHT)
	for x0, z0, color in ((20, 4, "orange"), (8, 27, "yellow"), (26, 26, "pink")):
		for dx, dz in ((0, 0), (3, 0), (0, 3), (3, 3)):
			build.box(x0 + dx, FLOOR, z0 + dz, x0 + dx, FLOOR + 2, z0 + dz, BEAM)
		build.box(x0, FLOOR + 3, z0, x0 + 3, FLOOR + 3, z0 + 3, wool(color))
		build.box(x0 + 1, FLOOR, z0 + 1, x0 + 2, FLOOR, z0 + 2, PLANK_SLAB)
	for x, z in ((3, 11), (33, 11), (3, 25), (33, 25), (14, 30), (22, 30)):
		build.box(x, FLOOR, z, x, FLOOR + 1, z, COLUMN)
		build.set(x, FLOOR + 2, z, LANTERN)


def build_crystal_bazaar() -> Build:
	sx, sy, sz = BAZAAR_SIZE
	build = Build(sx, sy, sz)
	build_bazaar_ground(build)
	build_souks(build)
	build_vault(build, *WEST_WING)
	build_vault(build, *EAST_WING)
	build_stalls(build)
	build_rotunda(build)
	build_terrace_stair(build)
	build_cistern(build)
	return build


# --------------------------------------------------------------------------
# 6. Volcanic smoke caldera
# --------------------------------------------------------------------------

CALDERA_SIZE = (38, 22, 38)
# The causeway lands on the east face, at the trailhead.
CALDERA_SPAWN = (37, FLOOR, 19)

VENT = (18.5, 18.5)                 # centre of the cone, in x and z
CONE_BASE_RADIUS = 17.5             # where the outer slope meets the ash field
CONE_SLOPE = 2.5                    # nodes of height per node of radius, outside
RIM_TOP = FLOOR + 13                # local y of the rim's walkway
RIM_OUTER = CONE_BASE_RADIUS - (RIM_TOP - SURFACE) / CONE_SLOPE
RIM_INNER = 8.5                     # the crater's lip
CRATER_FLOOR = SURFACE + 2          # local y of the crater floor
CRATER_RADIUS = 5.0                 # flat floor inside this
LAVA_RADIUS = 3.0                   # and the lava lake inside that
INNER_SLOPE = (RIM_TOP - CRATER_FLOOR) / (RIM_INNER - CRATER_RADIUS)

# The observation lip: a glass cantilever out over the crater, due north.
LIP_ANGLE = math.pi / 2
LIP_SPREAD = 0.4                    # radians either side
LIP_REACH = 6.0                     # how far in towards the vent it goes

# The tube runs due west from the crater floor and out the far face.
TUBE_Z = (17, 19)
TUBE_MOUTH_X = 0

BASALT = "lw_maps:basalt"
PACKED_BASALT = "lw_maps:packed_basalt"
LAVA = "lw_maps:lava"
LAVA_CRUST = "lw_maps:lava_crust"


def vent_radius(x: float, z: float) -> float:
	return math.hypot(x - VENT[0], z - VENT[1])


def vent_angle(x: float, z: float) -> float:
	return math.atan2(z - VENT[1], x - VENT[0]) % (2 * math.pi)


def caldera_height(x: float, z: float) -> int:
	"""Top of the cone's mass at (x, z), as a local y."""
	radius = vent_radius(x, z)
	if radius <= CRATER_RADIUS:
		return CRATER_FLOOR
	if radius <= RIM_INNER:
		return min(RIM_TOP, CRATER_FLOOR + int((radius - CRATER_RADIUS) * INNER_SLOPE))
	if radius <= RIM_OUTER:
		return RIM_TOP
	if radius >= CONE_BASE_RADIUS:
		return SURFACE
	return max(SURFACE, int(RIM_TOP - (radius - RIM_OUTER) * CONE_SLOPE))


def tube_floor(x: int) -> int:
	"""The tube steps down twice on its way out, to meet the ash field."""
	if x >= 11:
		return CRATER_FLOOR
	if x >= 6:
		return CRATER_FLOOR - 1
	return SURFACE


def build_cone(build: Build) -> None:
	for x in range(build.sx):
		for z in range(build.sz):
			top = caldera_height(x, z)
			if top <= SURFACE:
				continue
			build.box(x, FLOOR, z, x, top, z, BASALT)
			# Streaks of grey where the flanks have weathered, and sulphur
			# round the inside of the crater.
			radius = vent_radius(x, z)
			if radius > RIM_OUTER and (x * 7 + z * 3) % 5 == 0:
				build.set(x, top, z, STONE)
			if CRATER_RADIUS < radius <= RIM_INNER and (x * 3 + z * 5) % 7 == 0:
				build.set(x, top, z, wool("yellow"))


def build_ring_trail(build: Build) -> list[tuple[int, int, int]]:
	"""The outer trail: a shelf cut into the flank, one node up every four
	steps, from the trailhead on the east face to the rim."""
	path: list[tuple[int, int, int]] = []
	y = FLOOR
	angle = 0.0
	step = 0
	while y <= RIM_TOP:
		radius = CONE_BASE_RADIUS - (y - SURFACE) / CONE_SLOPE - 1.0
		x = int(round(VENT[0] + radius * math.cos(angle)))
		z = int(round(VENT[1] + radius * math.sin(angle)))
		if not path or path[-1] != (x, y, z):
			path.append((x, y, z))
		for dx in (-1, 0, 1):
			for dz in (-1, 0, 1):
				build.set(x + dx, y, z + dz, PACKED_BASALT)
				build.clear(x + dx, y + 1, z + dz, x + dx, y + 3, z + dz)
		step += 1
		if step % 4 == 0:
			y += 1
		angle += 1.0 / max(radius, 3.0)
		if y == RIM_TOP and vent_radius(x, z) <= RIM_OUTER + 0.5:
			break
	return path


def build_crater_shelf(build: Build, start_angle: float) -> list[tuple[int, int, int]]:
	"""The switchback down the inside: a ledge cut into the crater wall, one
	node down every three steps, from the rim to the crater floor."""
	path: list[tuple[int, int, int]] = []
	y = RIM_TOP
	angle = start_angle
	step = 0
	while y >= CRATER_FLOOR:
		# Half a node into the wall: any deeper and, near the top, the cut
		# takes the rim walkway with it.
		radius = CRATER_RADIUS + (y - CRATER_FLOOR) / INNER_SLOPE + 0.5
		x = int(round(VENT[0] + radius * math.cos(angle)))
		z = int(round(VENT[1] + radius * math.sin(angle)))
		if not path or path[-1] != (x, y, z):
			path.append((x, y, z))
		for dx in (-1, 0, 1):
			for dz in (-1, 0, 1):
				build.set(x + dx, y, z + dz, PACKED_BASALT)
				build.clear(x + dx, y + 1, z + dz, x + dx, y + 3, z + dz)
		step += 1
		if step % 3 == 0:
			y -= 1
		angle += 1.0 / max(radius, 3.0)
	return path


def build_crater(build: Build) -> None:
	cx, cz = VENT
	for x in range(build.sx):
		for z in range(build.sz):
			radius = vent_radius(x, z)
			if radius > CRATER_RADIUS:
				continue
			if radius <= LAVA_RADIUS:
				build.set(x, CRATER_FLOOR, z, LAVA)
				# About one lava cell in three has a flicker over it, so the lake
				# glows and dims in patches, never all at once.
				if (x + 2 * z) % 3 == 0:
					build.set(x, CRATER_FLOOR + 1, z, FLICKER)
			else:
				build.set(x, CRATER_FLOOR, z, BASALT)


def build_lip(build: Build) -> None:
	"""A glass cantilever off the rim, with a glass parapet at its end."""
	for x in range(build.sx):
		for z in range(build.sz):
			radius = vent_radius(x, z)
			off = abs((vent_angle(x, z) - LIP_ANGLE + math.pi) % (2 * math.pi) - math.pi)
			if off > LIP_SPREAD or not (LIP_REACH <= radius <= RIM_OUTER):
				continue
			if radius <= RIM_INNER:
				build.set(x, RIM_TOP, z, GLASS)
				build.clear(x, RIM_TOP + 1, z, x, RIM_TOP + 3, z)
			if radius < LIP_REACH + 0.9 or off > LIP_SPREAD - 0.12:
				build.set(x, RIM_TOP + 1, z, GLASS)


def build_tube(build: Build) -> None:
	"""The packed-basalt tube from the crater floor out through the west face."""
	z0, z1 = TUBE_Z
	start = int(VENT[0] - CRATER_RADIUS) + 1
	for x in range(TUBE_MOUTH_X, start + 1):
		f = tube_floor(x)
		build.box(x, f, z0 - 1, x, f + 4, z1 + 1, PACKED_BASALT)
		build.clear(x, f + 1, z0, x, f + 3, z1)
	# Half steps where it drops, so the walk out is a walk.
	for x in range(TUBE_MOUTH_X + 1, start + 1):
		if tube_floor(x) > tube_floor(x - 1):
			build.box(x - 1, tube_floor(x - 1) + 1, z0, x - 1, tube_floor(x - 1) + 1,
				z1, "lw_nodes:slab_stone_brick")
	for x in range(TUBE_MOUTH_X + 3, start, 4):
		build.set(x, tube_floor(x) + 3, z0, TORCH)
	# A portal on the far face.
	build.box(TUBE_MOUTH_X, SURFACE + 1, z0 - 2, TUBE_MOUTH_X, SURFACE + 5, z0 - 2,
		PACKED_BASALT)
	build.box(TUBE_MOUTH_X, SURFACE + 1, z1 + 2, TUBE_MOUTH_X, SURFACE + 5, z1 + 2,
		PACKED_BASALT)
	build.box(TUBE_MOUTH_X, SURFACE + 5, z0 - 2, TUBE_MOUTH_X, SURFACE + 5, z1 + 2,
		PACKED_BASALT)


def hollow(build: Build, mass: frozenset, keep: int = 2, y_min: int = FLOOR) -> None:
	"""Empty every `mass` cell more than `keep` nodes from anything that is not.

	The cone is generated solid and then carved, and only then hollowed, so
	every cut — trail, shelf, tube — ends up with walls `keep` nodes thick and
	nothing behind them. The hollow is sealed by construction: it is at least
	`keep` nodes from every open cell.
	"""
	sx, sy, sz = build.sx, build.sy, build.sz
	distance = {}
	queue = collections.deque()
	for x in range(sx):
		for y in range(y_min, sy):
			for z in range(sz):
				if build.get(x, y, z) not in mass:
					distance[(x, y, z)] = 0
					queue.append((x, y, z))
	while queue:
		x, y, z = queue.popleft()
		d = distance[(x, y, z)] + 1
		if d > keep:
			continue
		for dx, dy, dz in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)):
			n = (x + dx, y + dy, z + dz)
			if n in distance or not build.inside(*n) or n[1] < y_min:
				continue
			distance[n] = d
			queue.append(n)
	for x in range(sx):
		for y in range(y_min, sy):
			for z in range(sz):
				if (x, y, z) not in distance and build.get(x, y, z) in mass:
					build.set(x, y, z, AIR)


def build_ash_field(build: Build) -> None:
	"""The flat ground round the cone: ash, pumice, dead trees, the trailhead."""
	sx, _, sz = build.sx, build.sy, build.sz
	for x, z in ((4, 4), (33, 5), (5, 33), (32, 33), (2, 12), (12, 2), (35, 28)):
		height = 3 + (x + z) % 3
		build.box(x, FLOOR, z, x, FLOOR + height - 1, z, DEAD_WOOD)
		build.set(x + 1, FLOOR + height - 2, z, DEAD_WOOD)
		build.set(x, FLOOR + height - 1, z + 1, DEAD_WOOD)
	for x, z in ((8, 30), (29, 8), (30, 29), (9, 7), (24, 35)):
		build.box(x, FLOOR, z, x + 1, FLOOR, z + 1, BASALT)
		build.set(x, FLOOR + 1, z, BASALT)
	# The trailhead, where the causeway lands.
	build.box(sx - 5, SURFACE, 16, sx - 1, SURFACE, 22, PACKED_BASALT)
	for z in (15, 23):
		build.box(sx - 3, FLOOR, z, sx - 3, FLOOR + 1, z, PACKED_BASALT)
		build.set(sx - 3, FLOOR + 2, z, JACK)
		build.set(sx - 3, FLOOR + 3, z, FLICKER)


def build_smoke_caldera() -> Build:
	sx, sy, sz = CALDERA_SIZE
	build = Build(sx, sy, sz)
	build.ground(wool("dark_grey"), sub=STONE)
	build_ash_field(build)
	build_cone(build)
	trail = build_ring_trail(build)
	build_crater(build)
	# The way down starts a quarter turn past where the trail tops out, so the
	# two never share a stretch of rim.
	top = trail[-1]
	build_crater_shelf(build, vent_angle(top[0], top[2]) + math.pi / 2)
	build_lip(build)
	build_tube(build)
	hollow(build, frozenset({BASALT, STONE}))
	return build


# --------------------------------------------------------------------------
# 7. Rainbow storm
# --------------------------------------------------------------------------

# A long, low box: the arches are a walk, not a climb, and the storm is the
# sky above them, so nothing in the schematic stands higher than a rod.
RAINBOW_SIZE = (64, 8, 24)
# The causeway lands on the west face, on the middle (green) band.
RAINBOW_SPAWN = (1, FLOOR, 11)

# Outer edge to outer edge across the deck, one band per row of z.
RAINBOW_BANDS = ("red", "orange", "yellow", "green", "cyan", "blue", "violet")
DECK_Z0 = 8
DECK_Z1 = DECK_Z0 + len(RAINBOW_BANDS) - 1
# Where each arch's feet stand. Neighbouring arches share a foot, and the two
# ends are the landings: everything west of the first foot and east of the
# last is solid ground at the causeway's level.
ARCH_FEET = (8, 33, 58)
ARCH_RISE = 3
ARCH_RUN = 4                        # steps per node of rise
# A lightning rod on each crest: (x of the crest, z of the rod). The rod
# stands on a plinth just off the deck's edge, alternating sides, so the bolt
# comes down beside the path rather than on it.
RAINBOW_RODS = ((20, DECK_Z0 - 1), (45, DECK_Z1 + 1))


def arch_height(x: int) -> int:
	"""Local y of the feet of someone standing on the deck at column ``x``."""
	if x <= ARCH_FEET[0] or x >= ARCH_FEET[-1]:
		return FLOOR
	foot = max(f for f in ARCH_FEET if f <= x)
	span = ARCH_FEET[ARCH_FEET.index(foot) + 1] - foot
	d = min(x - foot, foot + span - x)
	# (d + 1) // RUN rather than d // RUN: with an odd span that makes every
	# flight a full four, the crest included, and the shared foot five.
	return FLOOR + min(ARCH_RISE, (d + 1) // ARCH_RUN)


def build_rainbow_storm() -> Build:
	sx, sy, sz = RAINBOW_SIZE
	build = Build(sx, sy, sz)
	# Lagoon under the arches, at the atlas sea's own level (local SURFACE - 1),
	# so the island reads as two landings with open water between them.
	build.box(0, 0, 0, sx - 1, SURFACE - 1, sz - 1, WATER)
	for x0, x1 in ((0, ARCH_FEET[0] - 1), (ARCH_FEET[-1] + 1, sx - 1)):
		build.box(x0, 0, 0, x1, SURFACE - 2, sz - 1, STONE)
		build.box(x0, SURFACE - 1, 0, x1, SURFACE - 1, sz - 1, DIRT)
		build.box(x0, SURFACE, 0, x1, SURFACE, sz - 1, GRASS)

	# The deck: one node thick, a band of wool per row, from landing to
	# landing. Where it is down at the water it stands on a pier of the same
	# wool, so the bands carry on to the lagoon floor.
	for x in range(sx):
		top = arch_height(x) - 1
		for z, color in zip(range(DECK_Z0, DECK_Z1 + 1), RAINBOW_BANDS):
			build.set(x, top, z, wool(color))
			if top == SURFACE and ARCH_FEET[0] <= x <= ARCH_FEET[-1]:
				build.box(x, 0, z, x, SURFACE - 1, z, wool(color))

	# Lightning rods: a gold plinth level with the crest's deck, a fence post
	# on it. lw_maps aims the bolts at the top of the post.
	for x, z in RAINBOW_RODS:
		crest = arch_height(x)
		build.set(x, crest - 1, z, GOLD)
		build.set(x, crest, z, FENCE)
	return build


# --------------------------------------------------------------------------
# 8. Around arena
# --------------------------------------------------------------------------

# Lace Waterfall's stage for "Around". Since the concert arena (9.) took the
# song, this one is a light show only: no amp cabs, so nothing here pulls the
# song files in. Small on purpose: 25 x 12 x 25 is 7,500
# cells, a small box (see Budget in docs/maps.md). Odd on both sides so the truss round the
# edge is 96 cells, which takes 32 lights three apart — a whole number of
# chase periods, so the loop has no seam.
ARENA_SIZE = (25, 12, 25)
# The causeway lands on the south face, under the marquee, in the middle.
ARENA_SPAWN = (12, FLOOR, 0)

# The truss: one row of cells all round the map's edge, on columns, with the
# lights in it and the chase controllers on top. The emitters lw_maps sends
# racing round the arena ride along the top of it.
TRUSS_Y = FLOOR + 6
TRUSS_EDGE = ARENA_SIZE[0] - 1
TRUSS_LIGHT_SPACING = 3
TRUSS_COLUMN_SPACING = 6

# The stage, at the north end, facing south down the dance floor. The deck is
# one node up: stand on it at FLOOR + 1. Its back is the backdrop wall, which
# is the truss's north side.
ARENA_STAGE = dict(x0=4, x1=20, z0=16, z1=TRUSS_EDGE - 1)
BACKDROP_Z = TRUSS_EDGE
BACKDROP_TOP = TRUSS_Y - 1
STAGE_STAIRS = ((4, 5), (19, 20))   # x, either side of the stage front
# Dummy speaker stacks on the deck's front corners, where the amp cabs stood
# before the song moved to the concert arena. Plain wool, so punching one
# does not start anything.
ARENA_SPEAKERS = ((6, ARENA_STAGE["z0"]), (18, ARENA_STAGE["z0"]))
# The Around arena's east edge, clear between two truss columns: where the
# concert arena's causeway leaves (lw_world/maps.lua).
ARENA_EAST_EXIT = (TRUSS_EDGE, FLOOR, 21)
STAGE_UPLIGHTS = (8, 10, 14, 16)

DANCE_FLOOR = dict(x0=3, x1=21, z0=2, z1=14)

# Banners. Full cubes with the art on the face that looks south at facedir 0,
# cut from one image each (lw_maps.register_banner); `(name, cols, rows)`.
AROUND_SIGN = ("lw_maps:around_sign", 5, 1)
LACE_BANNER = ("lw_maps:lace_banner", 1, 3)
PORTRAIT_RUBELLA = ("lw_maps:portrait_rubella", 2, 4)
PORTRAIT_LILLITH = ("lw_maps:portrait_lillith", 2, 4)

STAGE_LIGHT = "lw_maps:stage_light"
STAGE_LIGHT_OFF = "lw_maps:stage_light_off"
AMP_CAB = "lw_amps:cab"
BRICK_STAIR_NODE = "lw_nodes:stair_stone_brick"
TRUSS = wool("dark_grey")


def truss_ring(edge: int = TRUSS_EDGE) -> list[tuple[int, int]]:
	"""The truss's cells in loop order: east along the south edge, north up
	the east, west along the north, south down the west. lw_maps.track_point
	walks the same loop the same way, so the emitters race the way the
	lights chase."""
	e = edge
	ring = [(x, 0) for x in range(e)]
	ring += [(e, z) for z in range(e)]
	ring += [(x, e) for x in range(e, 0, -1)]
	ring += [(0, z) for z in range(e, 0, -1)]
	return ring


def place_banner(build: Build, banner, x0: int, top: int, z: int,
		facing: int = NORTH, step: tuple[int, int] = (1, 0)) -> None:
	"""Lay out a banner's cells, reading order, from its top-left corner.

	``step`` is the direction its columns run in, as seen from in front of
	it: (+1, 0) for a banner that faces south, (0, +1) for one that faces
	west, (0, -1) for one that faces east.
	"""
	name, cols, rows = banner
	for row in range(rows):
		for col in range(cols):
			build.set(x0 + step[0] * col, top - row, z + step[1] * col,
				f"{name}_{row * cols + col + 1}", facing)


def build_arena() -> Build:
	sx, sy, sz = ARENA_SIZE
	build = Build(sx, sy, sz)
	build.ground(POLISHED)

	# The dance floor: a two-node checker of black and violet.
	f = DANCE_FLOOR
	for x in range(f["x0"], f["x1"] + 1):
		for z in range(f["z0"], f["z1"] + 1):
			dark = (x // 2 + z // 2) % 2 == 0
			build.set(x, SURFACE, z, wool("black") if dark else wool("violet"))

	# The truss and its lights. A light every third cell, starting at a
	# corner, and its chase controller on top of it carrying its place.
	for index, (x, z) in enumerate(truss_ring()):
		if index % TRUSS_LIGHT_SPACING == 0:
			build.set(x, TRUSS_Y, z, STAGE_LIGHT_OFF)
			build.set(x, TRUSS_Y + 1, z, CHASE, (index // TRUSS_LIGHT_SPACING) % 8)
		else:
			build.set(x, TRUSS_Y, z, TRUSS)
	# Columns under it, except over the entrance.
	e = TRUSS_EDGE
	for a in range(0, e + 1, TRUSS_COLUMN_SPACING):
		for x, z in ((a, 0), (e, a), (0, a)):
			if (x, z) == (ARENA_SPAWN[0], 0):
				continue
			build.box(x, FLOOR, z, x, TRUSS_Y - 1, z, COLUMN)

	# Backdrop: the truss's north side is a wall of black cloth, with the
	# band's banners in it facing the floor.
	build.box(1, FLOOR, BACKDROP_Z, e - 1, BACKDROP_TOP, BACKDROP_Z, wool("black"))
	place_banner(build, AROUND_SIGN, 10, BACKDROP_TOP, BACKDROP_Z)
	place_banner(build, PORTRAIT_RUBELLA, 7, FLOOR + 4, BACKDROP_Z)
	place_banner(build, PORTRAIT_LILLITH, 16, FLOOR + 4, BACKDROP_Z)
	for x in (3, 12, 21):
		place_banner(build, LACE_BANNER, x, FLOOR + 4, BACKDROP_Z)

	# The marquee over the entrance faces the causeway, and cloth hangs from
	# the side trusses between the columns, facing in.
	place_banner(build, AROUND_SIGN, 10, TRUSS_Y - 1, 0)
	for z in (3, 9):
		place_banner(build, LACE_BANNER, 0, TRUSS_Y - 1, z, facing=WEST)
		place_banner(build, LACE_BANNER, e, TRUSS_Y - 1, z, facing=EAST)

	# The stage: a black deck with a violet lip, a stair up each side of the
	# front, uplights along the lip and the two cabs on its front corners.
	s = ARENA_STAGE
	build.box(s["x0"], FLOOR, s["z0"], s["x1"], FLOOR, s["z1"], wool("black"))
	build.box(s["x0"], FLOOR, s["z0"], s["x1"], FLOOR, s["z0"], wool("violet"))
	for pair in STAGE_STAIRS:
		for x in pair:
			build.set(x, FLOOR, s["z0"] - 1, BRICK_STAIR_NODE, NORTH)
	for x in STAGE_UPLIGHTS:
		build.set(x, FLOOR + 1, s["z0"], UPLIGHT)
	for x, z in ARENA_SPEAKERS:
		build.set(x, FLOOR + 1, z, wool("black"))

	# House lights: four hidden lamps over the floor, so the crowd is seen
	# between the chasing lights. They are airlike; nothing to walk into.
	for x in (f["x0"] + 2, f["x1"] - 2):
		for z in (f["z0"] + 3, f["z1"] - 2):
			build.set(x, TRUSS_Y - 1, z, HIDDEN_LIGHT)
	return build


# --------------------------------------------------------------------------
# 9. Thunder chapel (halloween_storm)
# --------------------------------------------------------------------------

# The Halloween lane's props under the rainbow storm's sky: a roofless chapel
# with an organ loft, a graveyard, a mausoleum and a pumpkin patch, on a night
# when lightning keeps finding the three tallest things there. The storm is
# lw_maps' (rain, flashes, thunder); the schematic only carries the rods.
#
# 36 x 20 x 36, the lane's own box: 25,920 cells, so it keeps 1 MiB like the
# lane does (see Budget in docs/maps.md).
STORM_CHAPEL_SIZE = (36, 20, 36)
# The causeway comes up from the south, onto the middle of the path.
STORM_CHAPEL_SPAWN = (19, FLOOR, 0)

# The path from the causeway to the chapel door, and the chapel itself: a
# brick shell with no roof, a loft across its north end and a tower behind.
CHAPEL_PATH_X = (18, 20)
CHAPEL = dict(x0=13, x1=25, z0=14, z1=30)
CHAPEL_WALL_TOP = FLOOR + 8         # a ruin: some columns stop short of this
CHAPEL_LOFT = FLOOR + 5             # the loft's floor; you stand one above it
CHAPEL_LOFT_Z0 = 23
CHAPEL_STAIR_X = (14, 15)           # up the west wall, climbing north
CHAPEL_STAIR_Z = CHAPEL_LOFT_Z0 - (CHAPEL_LOFT - FLOOR) - 1
BELL_TOWER = dict(x0=17, x1=21, z0=30, z1=34)
BELL_TOWER_TOP = FLOOR + 12              # the tower's cap; the spire stands on it
# The organ's pipes on the loft, against the north wall. lw_maps plays the
# optional pipe-organ track from just in front of them (the `organ` row in the
# registry); the pipes are the place, not the sound.
ORGAN_PIPES = (16, 22)
GRAVEYARD = dict(x0=2, x1=11, z0=6, z1=30)
MAUSOLEUM = dict(x0=27, x1=33, z0=17, z1=25)
MAUSOLEUM_ROOF = FLOOR + 5
STORM_PATCH = dict(x0=24, x1=33, z0=2, z1=12)
# Three lightning rods, each a fence post on the tallest thing in its corner
# of the map: the chapel's spire, the dead oak in the graveyard and the
# mausoleum's roof. (x, y, z) of the post itself; the bolt lands on its top.
STORM_CHAPEL_RODS = (
	(19, BELL_TOWER_TOP + 3, 32),
	(5, FLOOR + 9, 26),
	(30, MAUSOLEUM_ROOF + 2, 21),
)


def build_chapel(build: Build) -> None:
	c = CHAPEL
	x0, x1, z0, z1 = c["x0"], c["x1"], c["z0"], c["z1"]
	build.box(x0, SURFACE, z0, x1, SURFACE, z1, POLISHED)
	build.walls(x0, FLOOR, z0, x1, CHAPEL_WALL_TOP, z1, BRICK)
	# The ruin: a fixed pattern of broken wall tops, so every rebuild of the
	# schematic breaks the same stones. Only the front and the east side of
	# the nave: the west wall stands whole beside the loft stair, and the
	# loft's own walls do too, so nobody walks off the side of either.
	broken = (0, 2, 0, 0, 3, 1, 0, 4, 0, 1, 0, 0, 2)
	for x in range(x0, x1 + 1):
		drop = broken[(x - x0) % len(broken)]
		build.clear(x, CHAPEL_WALL_TOP - drop + 1, z0, x, CHAPEL_WALL_TOP, z0)
	for z in range(z0 + 1, CHAPEL_LOFT_Z0):
		drop = broken[(z - z0) % len(broken)]
		build.clear(x1, CHAPEL_WALL_TOP - drop + 1, z, x1, CHAPEL_WALL_TOP, z)
	# Tall open windows down both sides of the nave, a jack-o'-lantern on
	# the sill of each one.
	for z in range(z0 + 3, CHAPEL_LOFT_Z0, 4):
		for x in (x0, x1):
			build.clear(x, FLOOR + 3, z, x, FLOOR + 4, z)
			build.set(x, FLOOR + 2, z, JACK)
	# The door, under a pointed head of dead wood, and lanterns either side.
	px0, px1 = CHAPEL_PATH_X
	build.clear(px0, FLOOR, z0, px1, FLOOR + 3, z0)
	build.box(px0 - 1, FLOOR + 4, z0, px1 + 1, FLOOR + 4, z0, DEAD_WOOD)
	build.set(px0 + 1, FLOOR + 5, z0, DEAD_WOOD)
	for x in (px0 - 2, px1 + 2):
		lantern_post(build, x, z0 - 1, flicker=True)

	# Pews either side of the aisle, facing the loft (backs to the south).
	for z in range(z0 + 3, CHAPEL_LOFT_Z0 - 1, 2):
		for x in list(range(CHAPEL_STAIR_X[1] + 1, px0)) + list(range(px1 + 1, x1)):
			build.set(x, FLOOR, z, SEAT, SOUTH)
	build.set(x1 - 2, FLOOR + 3, z0 + 6, COBWEB)
	build.set(x0 + 4, FLOOR + 3, z0 + 9, COBWEB)

	# The loft: a plank floor across the north end, railed along its front
	# except where the stair comes up, reached by a stair up the west wall.
	build.box(x0 + 1, CHAPEL_LOFT, CHAPEL_LOFT_Z0, x1 - 1, CHAPEL_LOFT, z1 - 1, PLANKS)
	for x in range(CHAPEL_STAIR_X[1] + 1, x1):
		build.set(x, CHAPEL_LOFT + 1, CHAPEL_LOFT_Z0, FENCE)
	stair_run(build, CHAPEL_STAIR_X[0], CHAPEL_STAIR_X[1], CHAPEL_STAIR_Z, 1,
		FLOOR, CHAPEL_LOFT - FLOOR + 1, PLANK_STAIR, headroom=3)
	# Under the loft: an altar of bone-white stone, and a lamp nobody sees.
	build.box(px0, FLOOR, z1 - 2, px1, FLOOR, z1 - 2, BONE)
	build.set(px0 + 1, FLOOR + 1, z1 - 2, JACK)
	build.set(px0 + 1, CHAPEL_LOFT - 1, z1 - 4, HIDDEN_LIGHT)

	# The organ: a rank of pipes against the north wall, tallest in the
	# middle, gold-capped, with a console in front of them.
	ox0, ox1 = ORGAN_PIPES
	mid = (ox0 + ox1) // 2
	for x in range(ox0, ox1 + 1):
		height = max(2, 5 - abs(x - mid))
		top = CHAPEL_LOFT + height
		build.box(x, CHAPEL_LOFT + 1, z1 - 1, x, top, z1 - 1, COLUMN)
		build.set(x, top + 1, z1 - 1, GOLD)
	build.set(mid, CHAPEL_LOFT + 1, z1 - 3, PEDESTAL)
	build.set(mid - 1, CHAPEL_LOFT + 1, z1 - 3, JACK)
	build.set(mid + 1, CHAPEL_LOFT + 1, z1 - 3, JACK)
	build.set(mid - 1, CHAPEL_LOFT + 2, z1 - 3, FLICKER)

	# Rafters: what is left of the roof, black beams across the nave.
	for z in range(z0 + 2, z1, 4):
		build.box(x0, CHAPEL_WALL_TOP, z, x1, CHAPEL_WALL_TOP, z, BEAM)


def build_storm_tower(build: Build) -> None:
	t = BELL_TOWER
	x0, x1, z0, z1 = t["x0"], t["x1"], t["z0"], t["z1"]
	build.box(x0, SURFACE, z0, x1, SURFACE, z1, BRICK)
	build.walls(x0, FLOOR, z0, x1, BELL_TOWER_TOP, z1, BRICK)
	build.box(x0, BELL_TOWER_TOP, z0, x1, BELL_TOWER_TOP, z1, BRICK)
	# The belfry: an arch through every face, and a bell in the middle.
	cx, cz = (x0 + x1) // 2, (z0 + z1) // 2
	for y in (BELL_TOWER_TOP - 3, BELL_TOWER_TOP - 2):
		build.set(cx, y, z0, AIR)
		build.set(cx, y, z1, AIR)
		build.set(x0, y, cz, AIR)
		build.set(x1, y, cz, AIR)
	build.set(cx, BELL_TOWER_TOP - 1, cz, BEAM)
	build.set(cx, BELL_TOWER_TOP - 2, cz, GOLD)
	# The spire, and the rod on top of it.
	build.box(x0 + 1, BELL_TOWER_TOP + 1, z0 + 1, x1 - 1, BELL_TOWER_TOP + 1, z1 - 1, wool("black"))
	build.set(cx, BELL_TOWER_TOP + 2, cz, wool("black"))
	rx, ry, rz = STORM_CHAPEL_RODS[0]
	build.set(rx, ry, rz, FENCE)


def build_storm_graveyard(build: Build) -> None:
	g = GRAVEYARD
	x0, x1, z0, z1 = g["x0"], g["x1"], g["z0"], g["z1"]
	build.box(x0, SURFACE, z0, x1, SURFACE, z1, DIRT)
	for x in range(x0, x1 + 1, 2):
		build.set(x, FLOOR, z0, FENCE)
		build.set(x, FLOOR, z1, FENCE)
	for z in range(z0, z1 + 1, 2):
		build.set(x0, FLOOR, z, FENCE)
		build.set(x1, FLOOR, z, FENCE)
	# The gate faces the path, with a paved spur out to it, between the
	# lantern posts that line the path.
	build.clear(x1, FLOOR, 9, x1, FLOOR, 11)
	build.box(x1, SURFACE, 9, CHAPEL_PATH_X[0] - 1, SURFACE, 11, PAVING)
	build.set(x1, FLOOR + 1, 8, JACK)
	build.set(x1, FLOOR + 1, 12, JACK)
	build.set(x1, FLOOR + 2, 12, FLICKER)
	for row, z in enumerate(range(z0 + 3, z1 - 1, 3)):
		for column, x in enumerate(range(x0 + 2, x1 - 1, 3)):
			gravestone(build, x, z, tall=(row + column) % 3 == 1)
	# The dead oak in the far corner carries the second rod.
	rx, ry, rz = STORM_CHAPEL_RODS[1]
	dead_tree(build, rx, rz, ry - FLOOR, ((1, 0, 5), (0, -1, 6), (-1, 0, 4)))
	build.set(rx, ry, rz, FENCE)
	dead_tree(build, x1 - 2, z0 + 2, 4, ((-1, 0, 3),))
	build.set(8, FLOOR, z1 - 3, UPLIGHT)


def build_mausoleum(build: Build) -> None:
	m = MAUSOLEUM
	x0, x1, z0, z1 = m["x0"], m["x1"], m["z0"], m["z1"]
	build.box(x0, SURFACE, z0, x1, SURFACE, z1, POLISHED)
	build.walls(x0, FLOOR, z0, x1, MAUSOLEUM_ROOF - 1, z1, BONE)
	build.box(x0, MAUSOLEUM_ROOF, z0, x1, MAUSOLEUM_ROOF, z1, BRICK)
	for x, z in ((x0, z0), (x0, z1), (x1, z0), (x1, z1)):
		build.box(x, FLOOR, z, x, MAUSOLEUM_ROOF, z, COLUMN)
	# The door faces the chapel, between two lanterns.
	cz = (z0 + z1) // 2
	build.clear(x0, FLOOR, cz - 1, x0, FLOOR + 2, cz + 1)
	build.set(x0 - 1, FLOOR, cz - 2, PUMPKIN)
	build.set(x0 - 1, FLOOR, cz + 2, JACK)
	# Inside: a tomb, torches and webs.
	build.box(x1 - 2, FLOOR, cz - 1, x1 - 1, FLOOR, cz + 1, BONE)
	build.set(x1 - 1, FLOOR + 2, z0 + 1, TORCH)
	build.set(x1 - 1, FLOOR + 2, z1 - 1, TORCH)
	build.set(x0 + 1, FLOOR + 3, z0 + 1, COBWEB)
	build.set(x0 + 1, FLOOR + 3, z1 - 1, COBWEB)
	# The third rod, on a gold plinth on the roof.
	rx, ry, rz = STORM_CHAPEL_RODS[2]
	build.set(rx, ry - 1, rz, GOLD)
	build.set(rx, ry, rz, FENCE)


def build_storm_patch(build: Build) -> None:
	p = STORM_PATCH
	x0, x1, z0, z1 = p["x0"], p["x1"], p["z0"], p["z1"]
	build.box(x0, SURFACE, z0, x1, SURFACE, z1, DIRT)
	for row, z in enumerate(range(z0 + 1, z1, 3)):
		for x in range(x0 + 1, x1, 2):
			if (x + row) % 3 == 0:
				continue
			build.set(x, FLOOR, z, JACK if (x + 2 * row) % 7 == 0 else PUMPKIN)
			build.set(x, FLOOR, z + 1, VINE, 2)
	build.box(x1 - 1, FLOOR, z1 - 1, x1, FLOOR + 1, z1, HAY)
	dead_tree(build, 29, 7, 4, ((-1, 0, 3), (0, 1, 2)))


def build_halloween_storm() -> Build:
	sx, sy, sz = STORM_CHAPEL_SIZE
	build = Build(sx, sy, sz)
	build.ground(GRASS)

	# The path, and the arch the causeway lands under.
	px0, px1 = CHAPEL_PATH_X
	build.box(px0, SURFACE, 0, px1, SURFACE, CHAPEL["z0"], PAVING)
	for x in (px0 - 1, px1 + 1):
		build.box(x, FLOOR, 0, x, FLOOR + 4, 0, DEAD_WOOD)
	build.box(px0 - 1, FLOOR + 5, 0, px1 + 1, FLOOR + 5, 0, DEAD_WOOD)
	build.set(px0, FLOOR + 4, 0, COBWEB)
	build.set(px1, FLOOR + 4, 0, COBWEB)
	for z in (4, 8, 12):
		lantern_post(build, px0 - 2, z, flicker=(z % 8 == 4))
		lantern_post(build, px1 + 2, z, flicker=(z % 8 == 0))

	build_storm_patch(build)
	build_storm_graveyard(build)
	build_mausoleum(build)
	build_chapel(build)
	build_storm_tower(build)
	dead_tree(build, 31, 31, 6, ((-1, 0, 4), (0, -1, 5)))
	dead_tree(build, 2, 2, 5, ((1, 0, 3), (0, 1, 4)))
	return build


# --------------------------------------------------------------------------
# 10. Cabaret club
# --------------------------------------------------------------------------

# A dim, warm room for Rubella and Lillith: a proscenium stage with velvet
# wings and chasing bulbs, a dance floor in front of it, candlelit tables and
# a bar. Indoors, so the night outside is the sky and fog over the roof and
# the room is lit by its own lamps.
#
# 27 x 11 x 27 is 8,019 cells, a small box like the Around arena's (see Budget
# in docs/maps.md).
CABARET_SIZE = (27, 11, 27)
# The causeway lands on the east face, under the awning, level with the door.
CABARET_SPAWN = (26, FLOOR, 14)

CLUB = dict(x0=2, x1=24, z0=2, z1=24)
CLUB_ROOF = 10                      # the top layer of the box
CLUB_DOOR_Z = (13, 15)
# The stage runs along the west wall and faces east, down the room. Its deck
# is one node up; the front of it is CABARET_STAGE["x1"].
CABARET_STAGE = dict(x0=3, x1=8, z0=4, z1=22)
# The two cabs on the stage's front corners, twelve nodes apart. Facing the
# stage from the floor (looking west), the audience's left is south.
CABARET_CABS = ((8, 7), (8, 19))    # (x, z): audience-left first
CABARET_BULBS_X = 9                 # the chasing bulbs hang in front of the header
CABARET_BULBS_Y = FLOOR + 4
CABARET_FLOOR = dict(x0=10, x1=15, z0=8, z1=18)
CABARET_TABLES = ((18, 5), (22, 5), (18, 9), (22, 9), (18, 17), (22, 17))
CABARET_BAR = dict(x0=16, x1=22, z=21)
# Where the Stage Director stands, on the floor south of the stage stair.
CABARET_DIRECTOR = (11, FLOOR, 4)
LANTERN_NODE = "lw_maps:lantern"
LANTERN_NODE_OFF = "lw_maps:lantern_off"


def build_cabaret_stage(build: Build) -> None:
	s = CABARET_STAGE
	x0, x1, z0, z1 = s["x0"], s["x1"], s["z0"], s["z1"]
	velvet = CURTAIN
	# The deck, with a gold lip along its front.
	build.box(x0, FLOOR, z0, x1, FLOOR, z1, PLANKS)
	build.box(x1, FLOOR, z0, x1, FLOOR, z1, GOLD)
	# Backdrop and wings of velvet, and a velvet valance under the header.
	build.box(x0, FLOOR + 1, z0, x0, CLUB_ROOF - 1, z1, velvet)
	for z in (z0, z1):
		build.box(x0, FLOOR + 1, z, x1 - 1, CLUB_ROOF - 1, z, velvet)
	build.box(x1 - 1, CLUB_ROOF - 1, z0, x1 - 1, CLUB_ROOF - 1, z1, velvet)
	# The proscenium: gold posts at the front corners, a gold header.
	for z in (z0, z1):
		build.box(x1, FLOOR + 1, z, x1, CLUB_ROOF - 1, z, GOLD)
	build.box(x1, CLUB_ROOF - 1, z0, x1, CLUB_ROOF - 1, z1, GOLD)
	# Footlights along the lip, clear of where the band stands.
	for z in (10, 16):
		build.set(x1, FLOOR + 1, z, UPLIGHT)
	# The cabs, grilles to the room (facedir 3 turns the front to +x).
	for x, z in CABARET_CABS:
		build.set(x, FLOOR + 1, z, AMP_CAB, WEST)
	# A stair up at each end of the front, climbing west.
	for z in (z0 + 1, z1 - 1):
		build.set(x1 + 1, FLOOR, z, BRICK_STAIR_NODE, WEST)
	# Chasing bulbs across the front of the header: a lantern every other
	# cell, each with a chase controller over it carrying its place.
	for index, z in enumerate(range(z0 + 2, z1 - 1, 2)):
		build.set(CABARET_BULBS_X, CABARET_BULBS_Y, z, LANTERN_NODE_OFF)
		build.set(CABARET_BULBS_X, CABARET_BULBS_Y + 1, z, CHASE, index % 8)


def build_cabaret_room(build: Build) -> None:
	c = CLUB
	x0, x1, z0, z1 = c["x0"], c["x1"], c["z0"], c["z1"]
	build.box(x0 + 1, SURFACE, z0 + 1, x1 - 1, SURFACE, z1 - 1, PLANKS)
	build.walls(x0, FLOOR, z0, x1, CLUB_ROOF - 1, z1, BRICK)
	build.box(x0, CLUB_ROOF, z0, x1, CLUB_ROOF, z1, wool("black"))
	# The door, on the east face.
	dz0, dz1 = CLUB_DOOR_Z
	build.clear(x1, FLOOR, dz0, x1, FLOOR + 2, dz1)
	build.box(x1, FLOOR + 3, dz0 - 1, x1, FLOOR + 3, dz1 + 1, GOLD)
	# Sconces: warm lanterns set into the side walls, high up.
	for x in (12, 18):
		build.set(x, FLOOR + 3, z0, LANTERN_NODE)
		build.set(x, FLOOR + 3, z1, LANTERN_NODE)
	build.set(x1, FLOOR + 3, 6, LANTERN_NODE)
	build.set(x1, FLOOR + 3, 20, LANTERN_NODE)

	# The dance floor: a two-node checker of black and red.
	f = CABARET_FLOOR
	for x in range(f["x0"], f["x1"] + 1):
		for z in range(f["z0"], f["z1"] + 1):
			dark = (x // 2 + z // 2) % 2 == 0
			build.set(x, SURFACE, z, wool("black") if dark else wool("red"))

	# Tables: a pedestal with a candle on it, a chair either side facing in.
	for x, z in CABARET_TABLES:
		build.set(x, FLOOR, z, PEDESTAL)
		build.set(x, FLOOR + 1, z, TORCH)
		build.set(x - 1, FLOOR, z, SEAT, WEST)
		build.set(x + 1, FLOOR, z, SEAT, EAST)

	# The bar along the north wall: a counter, stools on the room side, and
	# a lit back bar of glass shelves against the wall.
	b = CABARET_BAR
	build.box(b["x0"], FLOOR, b["z"], b["x1"], FLOOR, b["z"], PLANKS)
	build.box(b["x0"], FLOOR + 1, b["z"], b["x1"], FLOOR + 1, b["z"], BRICK_SLAB)
	for x in range(b["x0"] + 1, b["x1"], 2):
		build.set(x, FLOOR, b["z"] - 1, SEAT, SOUTH)
	build.box(b["x0"], FLOOR + 1, z1 - 1, b["x1"], FLOOR + 2, z1 - 1, GLASS)
	build.set((b["x0"] + b["x1"]) // 2, FLOOR + 3, z1 - 1, LANTERN_NODE)
	build.set(b["x0"], FLOOR, z1 - 1, PLANKS)
	build.set(b["x1"], FLOOR, z1 - 1, PLANKS)


def build_cabaret() -> Build:
	sx, sy, sz = CABARET_SIZE
	build = Build(sx, sy, sz)
	build.ground(PAVING)
	build_cabaret_room(build)
	build_cabaret_stage(build)

	# Outside: an awning over the door on gold posts, and a lantern either
	# side, so the club reads from the causeway in the dark.
	dz0, dz1 = CLUB_DOOR_Z
	x1 = CLUB["x1"]
	for z in (dz0 - 1, dz1 + 1):
		build.box(x1 + 2, FLOOR, z, x1 + 2, FLOOR + 3, z, GOLD)
	build.box(x1 + 1, FLOOR + 4, dz0 - 1, sx - 1, FLOOR + 4, dz1 + 1, wool("red"))
	for z in (dz0 - 3, dz1 + 3):
		build.set(x1 + 1, FLOOR, z, PEDESTAL)
		build.set(x1 + 1, FLOOR + 1, z, LANTERN_NODE)
	return build


# --------------------------------------------------------------------------
# 11. Concert arena
# --------------------------------------------------------------------------

# The one map that plays the songs. lw_amps keeps the song files out of the
# media every client is sent on join and pushes a pair only when it plays
# here (lw_amps/songs/README.md), so the rest of the pack stays light; a
# later lossless experiment belongs here too, and nowhere else.
#
# 49 x 13 x 49 is 31,213 cells: about twice the Around arena on each side (see
# NODE_BUDGET). Odd on both sides again: a 192-cell truss takes 64 lights
# three apart, eight whole chase periods.
CONCERT_SIZE = (49, 13, 49)
CONCERT_EDGE = CONCERT_SIZE[0] - 1
# The causeway lands on the south face, under the marquee, in the middle.
CONCERT_SPAWN = (CONCERT_EDGE // 2, FLOOR, 0)

CONCERT_TRUSS_Y = FLOOR + 7
CONCERT_COLUMN_SPACING = 8
# A second truss bar across the room in front of the stage, hung with lit
# stage lights that do not chase: the wash on the band.
CONCERT_FRONT_TRUSS_Z = 28

# The stage, across the north end, facing south. One node up, like the Around
# deck, so lw_dance's band stands on it at FLOOR + 1.
CONCERT_STAGE = dict(x0=8, x1=40, z0=30, z1=CONCERT_EDGE - 1)
CONCERT_BACKDROP_TOP = CONCERT_TRUSS_Y - 1
CONCERT_STAGE_STAIRS = ((8, 9), (39, 40))
# The two amp cabs, audience-left (west) first: lw_maps points lw_amps one
# node above each and lw_dance puts the band between them. Twenty apart, so
# the stereo image has room to open up across the floor.
CONCERT_CABS = ((14, CONCERT_STAGE["z0"]), (34, CONCERT_STAGE["z0"]))
CONCERT_UPLIGHTS = (11, 18, 22, 26, 30, 37)

CONCERT_FLOOR = dict(x0=7, x1=41, z0=3, z1=26)
# Audience risers down both sides: two tiers, each a single step up, so the
# back of the crowd sees over the front.
CONCERT_RISERS = ((1, 2, 2), (3, 4, 1), (44, 45, 1), (46, 47, 2))
CONCERT_RISER_Z = (6, 24)
# Front-of-house desk, on the floor's centre line near the back.
CONCERT_DESK = dict(x0=21, x1=27, z=9)


def build_concert_arena() -> Build:
	sx, sy, sz = CONCERT_SIZE
	build = Build(sx, sy, sz)
	build.ground(POLISHED)
	e = CONCERT_EDGE
	mid = e // 2

	# The dance floor: a two-node checker of black and magenta, edged violet.
	f = CONCERT_FLOOR
	for x in range(f["x0"] - 1, f["x1"] + 2):
		for z in range(f["z0"] - 1, f["z1"] + 2):
			if not (f["x0"] <= x <= f["x1"] and f["z0"] <= z <= f["z1"]):
				build.set(x, SURFACE, z, wool("violet"))
			elif (x // 2 + z // 2) % 2 == 0:
				build.set(x, SURFACE, z, wool("black"))
			else:
				build.set(x, SURFACE, z, wool("magenta"))

	# The edge truss and its chase, exactly as the Around arena's.
	for index, (x, z) in enumerate(truss_ring(e)):
		if index % TRUSS_LIGHT_SPACING == 0:
			build.set(x, CONCERT_TRUSS_Y, z, STAGE_LIGHT_OFF)
			build.set(x, CONCERT_TRUSS_Y + 1, z, CHASE,
				(index // TRUSS_LIGHT_SPACING) % 8)
		else:
			build.set(x, CONCERT_TRUSS_Y, z, TRUSS)
	for a in range(0, e + 1, CONCERT_COLUMN_SPACING):
		for x, z in ((a, 0), (e, a), (0, a)):
			if (x, z) == (CONCERT_SPAWN[0], 0):
				continue
			build.box(x, FLOOR, z, x, CONCERT_TRUSS_Y - 1, z, COLUMN)

	# The front truss: wall to wall at the edge truss's height, a lit light
	# every fourth cell. Nothing rides on it, so the chase stays the edge's.
	for x in range(1, e):
		lit = x % 4 == 0
		build.set(x, CONCERT_TRUSS_Y, CONCERT_FRONT_TRUSS_Z,
			STAGE_LIGHT if lit else TRUSS)

	# Backdrop and banners, the Around arena's art spread across a wider wall.
	build.box(1, FLOOR, e, e - 1, CONCERT_BACKDROP_TOP, e, wool("black"))
	place_banner(build, AROUND_SIGN, mid - 2, CONCERT_BACKDROP_TOP, e)
	place_banner(build, PORTRAIT_RUBELLA, 15, FLOOR + 5, e)
	place_banner(build, PORTRAIT_LILLITH, 32, FLOOR + 5, e)
	for x in (4, 10, 24, 38, 44):
		place_banner(build, LACE_BANNER, x, FLOOR + 4, e)

	# The marquee over the entrance, and cloth on the side trusses facing in.
	place_banner(build, AROUND_SIGN, mid - 2, CONCERT_TRUSS_Y - 1, 0)
	for z in (4, 12, 20):
		place_banner(build, LACE_BANNER, 0, CONCERT_TRUSS_Y - 1, z, facing=WEST)
		place_banner(build, LACE_BANNER, e, CONCERT_TRUSS_Y - 1, z, facing=EAST)

	# The stage: deck, violet lip, stairs either side of the front, uplights
	# along the lip and the two cabs.
	s = CONCERT_STAGE
	build.box(s["x0"], FLOOR, s["z0"], s["x1"], FLOOR, s["z1"], wool("black"))
	build.box(s["x0"], FLOOR, s["z0"], s["x1"], FLOOR, s["z0"], wool("violet"))
	for pair in CONCERT_STAGE_STAIRS:
		for x in pair:
			build.set(x, FLOOR, s["z0"] - 1, BRICK_STAIR_NODE, NORTH)
	for x in CONCERT_UPLIGHTS:
		build.set(x, FLOOR + 1, s["z0"], UPLIGHT)
	for x, z in CONCERT_CABS:
		# facedir 0 puts the cab's grille on its south face, at the floor.
		build.set(x, FLOOR + 1, z, AMP_CAB, NORTH)

	# Risers down both sides of the floor.
	z0, z1 = CONCERT_RISER_Z
	for x0, x1, height in CONCERT_RISERS:
		build.box(x0, FLOOR, z0, x1, FLOOR + height - 1, z1, BRICK)

	# Front-of-house: a planks desk with a gold edge, lamps at either end.
	d = CONCERT_DESK
	build.box(d["x0"], FLOOR, d["z"], d["x1"], FLOOR, d["z"], PLANKS)
	build.box(d["x0"] + 1, FLOOR, d["z"] - 1, d["x1"] - 1, FLOOR, d["z"] - 1, GOLD)
	build.set(d["x0"], FLOOR + 1, d["z"], LAMP)
	build.set(d["x1"], FLOOR + 1, d["z"], LAMP)

	# House lights over the floor, every twelve nodes; airlike.
	for x in range(f["x0"] + 3, f["x1"], 12):
		for z in range(f["z0"] + 3, f["z1"], 8):
			build.set(x, CONCERT_TRUSS_Y - 1, z, HIDDEN_LIGHT)
	return build


# --------------------------------------------------------------------------
# 12. Laser serpent (Weeks on Fire)
# --------------------------------------------------------------------------

# A night ash field west of the smoke caldera, reached by a spur from the
# mouth of its basalt tube. A serpent of glowing scales coils up round a
# basalt obelisk, its head reared out over the field towards the causeway,
# and lw_maps' laser show (the Around arena's, given patterns) sweeps its
# beams across the walk that runs past it. Punch the console at the far end
# of the walk and the beams change pattern.
#
# 35 x 16 x 35 is 19,600 cells.
SERPENT_SIZE = (35, 16, 35)
# The causeway lands on the east face, on the middle of the walk.
SERPENT_SPAWN = (34, FLOOR, 17)

# The walk: packed basalt, east to west through the middle of the field, with
# a neon tube along each edge.
SERPENT_WALK_Z = (16, 18)
SERPENT_WALK_X0 = 6
# The dais at the west end, one node up, with the console on it.
SERPENT_DAIS = dict(x0=1, x1=5, z0=13, z1=21)
SERPENT_CONSOLE = (2, FLOOR + 1, 17)
SERPENT_CONSOLE_STAND = (3, FLOOR + 1, 17)

# The coil: a helix of scales round an obelisk north of the walk, from the
# tail on the ground at its south side to the neck at its east side. lw_maps'
# `coil` laser pattern runs its emitters up the same helix (laser_serpent's
# `lasers.coil` in lw_maps/init.lua), which test_luanti_web_maps.py checks.
COIL_CENTRE = (17, 26)
COIL_RADIUS = 5.0
COIL_Y0 = FLOOR
COIL_RISE = 9                       # from the tail to the neck
COIL_TURNS = 2.25
COIL_START = -math.pi / 2           # the tail: due south of the obelisk
OBELISK_RADIUS = 2.5
OBELISK_TOP = FLOOR + 10

# The head: reared out east of the coil at the top of the neck, mouth open
# towards the causeway, a laser emitter for each eye.
SERPENT_HEAD = dict(x0=24, x1=28, y0=COIL_Y0 + COIL_RISE - 2,
	y1=COIL_Y0 + COIL_RISE, z0=24, z1=28)
SERPENT_MOUTH = (30, COIL_Y0 + COIL_RISE - 2, 26)

# Pylons at the corners, a laser emitter on each: the `sweep` pattern's
# emitters race round from cap to cap.
SERPENT_PYLONS = ((2, 2), (32, 2), (2, 32), (32, 32))
SERPENT_PYLON_TOP = FLOOR + 9

# Two ember pits south of the walk, flickering, and the HOA's notice by the
# causeway.
EMBER_PITS = ((11, 8), (21, 7))
SERPENT_MEMO = (31, FLOOR + 1, 14)

SERPENT_SCALE = "lw_maps:serpent_scale"
SERPENT_SCALE_OFF = "lw_maps:serpent_scale_off"
LASER_BLOCK = "lw_maps:laser_block"
NEON = "lw_maps:neon_tube"
EMBER = "lw_maps:ember_block"
EMBER_OFF = "lw_maps:ember_block_off"
HOA_MEMO = "lw_maps:hoa_memo"
SERPENT_SWITCH = "lw_maps:serpent_switch"


def coil_point(s: float) -> tuple[float, float, float]:
	"""The coil's centre line at `s` (0 at the tail, 1 at the neck).

	lw_maps.laser_frame's `coil` pattern computes the same point; keep the
	two in step (test_serpent_emitters_ride_the_coil)."""
	angle = COIL_START + s * COIL_TURNS * 2 * math.pi
	return (COIL_CENTRE[0] + COIL_RADIUS * math.cos(angle),
		COIL_Y0 + s * COIL_RISE,
		COIL_CENTRE[1] + COIL_RADIUS * math.sin(angle))


def coil_cells(radius: float = COIL_RADIUS) -> list[tuple[int, int, int]]:
	"""The helix rasterised at `radius`, tail first, each cell once."""
	cells: list[tuple[int, int, int]] = []
	seen = set()
	steps = 1200
	for i in range(steps + 1):
		s = i / steps
		angle = COIL_START + s * COIL_TURNS * 2 * math.pi
		cell = (int(round(COIL_CENTRE[0] + radius * math.cos(angle))),
			int(COIL_Y0 + s * COIL_RISE),
			int(round(COIL_CENTRE[1] + radius * math.sin(angle))))
		if cell not in seen:
			seen.add(cell)
			cells.append(cell)
	return cells


def build_serpent_field(build: Build) -> None:
	"""The ash field: dunes, dead trees, pylons, the walk and its dais."""
	sx, _, sz = build.sx, build.sy, build.sz
	build.ground(wool("dark_grey"), sub=STONE)
	# Low dunes of pale sand in the open corners.
	for cx, cz in ((6, 28), (30, 3), (30, 31)):
		build.sphere(cx, SURFACE, cz, 4.0, SAND, sy=2)
	for x, z in ((4, 10), (31, 10), (13, 32), (33, 21)):
		height = 3 + (x + z) % 3
		build.box(x, FLOOR, z, x, FLOOR + height - 1, z, DEAD_WOOD)
		build.set(x + 1, FLOOR + height - 2, z, DEAD_WOOD)
		build.set(x, FLOOR + height - 1, z - 1, DEAD_WOOD)
	for x, z in SERPENT_PYLONS:
		build.box(x, SURFACE, z, x, SERPENT_PYLON_TOP - 1, z, PACKED_BASALT)
		build.set(x, SERPENT_PYLON_TOP, z, LASER_BLOCK)

	# The walk, edged with neon, from the causeway to the dais.
	z0, z1 = SERPENT_WALK_Z
	build.box(SERPENT_WALK_X0, SURFACE, z0, sx - 1, SURFACE, z1, PACKED_BASALT)
	build.clear(SERPENT_WALK_X0, FLOOR, z0, sx - 1, FLOOR + 3, z1)
	for x in range(SERPENT_WALK_X0 + 1, sx - 1):
		build.set(x, FLOOR, z0 - 1, NEON)
		build.set(x, FLOOR, z1 + 1, NEON)
	for x in (12, 20, 28):
		build.set(x, FLOOR + 3, (z0 + z1) // 2, HIDDEN_LIGHT)

	# The dais: one node up, a half step from the walk, the console on it.
	d = SERPENT_DAIS
	build.box(d["x0"], FLOOR, d["z0"], d["x1"], FLOOR, d["z1"], PACKED_BASALT)
	build.box(d["x1"] + 1, FLOOR, z0, d["x1"] + 1, FLOOR, z1, BRICK_SLAB)
	# Its face looks east, down the walk.
	build.set(*SERPENT_CONSOLE, SERPENT_SWITCH, WEST)
	for z in (d["z0"], d["z1"]):
		build.set(d["x0"], FLOOR + 1, z, LASER_BLOCK)
	build.set(d["x0"] + 2, FLOOR + 3, (d["z0"] + d["z1"]) // 2, HIDDEN_LIGHT)

	# The HOA's notice, on a pedestal by the causeway, facing the walk.
	mx, my, mz = SERPENT_MEMO
	build.set(mx, my - 1, mz, PEDESTAL)
	build.set(mx, my, mz, HOA_MEMO, SOUTH)


def build_ember_pits(build: Build) -> None:
	"""Shallow pits of ember blocks, ringed with basalt, each ember under a
	flicker controller: the caldera's lava-lake trick at a campfire's size."""
	for cx, cz in EMBER_PITS:
		for x in range(cx - 3, cx + 4):
			for z in range(cz - 3, cz + 4):
				d = math.hypot(x - cx, z - cz)
				if d <= 2.2:
					build.set(x, SURFACE, z, EMBER_OFF)
					if (x + 2 * z) % 3 != 0:
						build.set(x, SURFACE, z, EMBER)
					build.set(x, FLOOR, z, FLICKER)
				elif d <= 3.2 and (x + z) % 2 == 0:
					build.set(x, FLOOR, z, BASALT)


def build_serpent(build: Build) -> list[tuple[int, int, int]]:
	"""The obelisk, the coiled body, the neck and the head. Returns the lit
	scales in chase order, tail to neck."""
	cx, cz = COIL_CENTRE
	reach = int(OBELISK_RADIUS) + 1
	for x in range(cx - reach, cx + reach + 1):
		for z in range(cz - reach, cz + reach + 1):
			if math.hypot(x - cx, z - cz) <= OBELISK_RADIUS:
				build.box(x, SURFACE, z, x, OBELISK_TOP - 1, z, PACKED_BASALT)
	build.set(cx, OBELISK_TOP, cz, LASER_BLOCK)

	# The body: an outer course of scales that light, and an inner one of
	# dark scales behind it, so it reads as a body and not a wire.
	outer = coil_cells(COIL_RADIUS)
	inner = coil_cells(COIL_RADIUS - 1)
	for x, y, z in inner:
		build.set(x, y, z, SERPENT_SCALE_OFF)
	for x, y, z in outer:
		build.set(x, y, z, SERPENT_SCALE_OFF)

	# Neck and head, out east of the coil's last cell.
	h = SERPENT_HEAD
	build.box(cx + int(COIL_RADIUS), h["y0"] + 1, cz - 1, h["x0"] - 1, h["y1"], cz + 1,
		SERPENT_SCALE_OFF)
	build.box(h["x0"], h["y0"], h["z0"], h["x1"], h["y1"], h["z1"], SERPENT_SCALE_OFF)
	mx, my, mz = SERPENT_MOUTH
	# Upper snout over an open mouth, the lower jaw under it.
	build.box(h["x1"] + 1, my + 1, mz - 1, mx + 1, h["y1"], mz + 1, SERPENT_SCALE_OFF)
	build.box(h["x1"] + 1, my - 1, mz - 1, mx + 1, my - 1, mz + 1, SERPENT_SCALE_OFF)
	build.clear(h["x1"] + 1, my, mz - 1, mx + 1, my, mz + 1)
	for z in (mz - 1, mz + 1):
		build.set(mx + 1, my, z, BONE)
		build.set(mx + 4, my, z, NEON)
	# A forked neon tongue, out over the lower jaw.
	build.box(mx + 1, my, mz, mx + 3, my, mz, NEON)
	for z in (h["z0"], h["z1"]):
		build.set(h["x1"], h["y1"], z, LASER_BLOCK)

	# A chase controller on every outer scale with open air above it, its
	# place along the body in param2, so light runs up the coil tail to neck.
	lit = []
	for x, y, z in outer:
		if build.get(x, y + 1, z) == AIR and build.get(x, y, z) == SERPENT_SCALE_OFF:
			build.set(x, y + 1, z, CHASE, len(lit) % 8)
			lit.append((x, y, z))
	return lit


def build_laser_serpent() -> Build:
	sx, sy, sz = SERPENT_SIZE
	build = Build(sx, sy, sz)
	build_serpent_field(build)
	build_ember_pits(build)
	build_serpent(build)
	return build


# --------------------------------------------------------------------------
# 13. Mirror hall (Weeks on Fire)
# --------------------------------------------------------------------------

# A vaulted hall of mirror tiles east of the crystal bazaar, after the mirror
# mosaic halls (Shah Cheragh) in the film: the bazaar's glass-between-ribs
# vault, closed in and silvered, at twilight. A crystal skull on a plinth in
# the middle, a gallery round three sides one storey up with a parapet of
# crystals that chase round it, and three of lw_maps' lasers circling the
# skull. Reached by a spur out of the bazaar arcade's east end.
#
# 31 x 18 x 31 is 17,298 cells.
MIRROR_SIZE = (31, 18, 31)
# The causeway lands on the west face, on the forecourt's path.
MIRROR_SPAWN = (0, FLOOR, 15)

MIRROR_PATH_Z = (14, 16)
HALL = dict(x0=8, x1=28, z0=6, z1=24)    # outer walls
HALL_AXIS_Z = 15
HALL_SPRING = FLOOR + 8
HALL_RISE = 5
HALL_HALF = 9.5
HALL_PORTAL_Z = (13, 17)

# The gallery, one storey up round the north, east and south walls, and the
# flight up to it along the north wall from the hall floor.
BALCONY_Y = FLOOR + 4                       # the deck; stand on it at +1
BALCONY_DECKS = (dict(x0=14, x1=27, z0=21, z1=23), dict(x0=14, x1=27, z0=7, z1=9),
	dict(x0=25, x1=27, z0=7, z1=23))
BALCONY_STAIR = dict(x0=9, x1=13, z0=22, z1=23)

SKULL = (17, 15)                            # x, z of the plinth's centre
SKULL_PLINTH = 2                            # half-width

MIRROR_POOLS = (dict(x0=1, x1=6, z0=9, z1=12), dict(x0=1, x1=6, z0=18, z1=21))
MIRROR_MEMO = (7, FLOOR + 1, 12)

MIRROR = "lw_maps:mirror"
CRYSTAL = "lw_maps:crystal"
CRYSTAL_DIM = "lw_maps:crystal_dim"


def hall_vault_top(z: int) -> int:
	"""Local y of the vault's shell over row `z`: a low ellipse across the
	hall, springing from the walls' tops."""
	d = (z - HALL_AXIS_Z) / HALL_HALF
	if abs(d) >= 1:
		return HALL_SPRING
	return HALL_SPRING + int(HALL_RISE * math.sqrt(1 - d * d) + 0.5)


def in_balcony(x: int, z: int) -> bool:
	return any(b["x0"] <= x <= b["x1"] and b["z0"] <= z <= b["z1"] for b in BALCONY_DECKS)


def build_mirror_forecourt(build: Build) -> None:
	build.ground(POLISHED)
	sx, _, sz = build.sx, build.sy, build.sz
	for x in range(sx):
		for z in (0, sz - 1):
			build.set(x, SURFACE, z, SAND)
	for z in range(sz):
		for x in (0, sx - 1):
			if not MIRROR_PATH_Z[0] <= z <= MIRROR_PATH_Z[1]:
				build.set(x, SURFACE, z, SAND)
	z0, z1 = MIRROR_PATH_Z
	build.box(0, SURFACE, z0, HALL["x0"] - 1, SURFACE, z1, PAVING)
	# Reflecting pools either side of the path, glass under still water.
	for p in MIRROR_POOLS:
		build.box(p["x0"], SURFACE - 1, p["z0"], p["x1"], SURFACE - 1, p["z1"], GLASS)
		build.box(p["x0"], SURFACE, p["z0"], p["x1"], SURFACE, p["z1"], WATER)
	for x in (1, 6):
		for z in (z0 - 1, z1 + 1):
			build.box(x, FLOOR, z, x, FLOOR + 1, z, COLUMN)
			build.set(x, FLOOR + 2, z, LANTERN)
	mx, my, mz = MIRROR_MEMO
	build.set(mx, my - 1, mz, PEDESTAL)
	build.set(mx, my, mz, HOA_MEMO, SOUTH)


def build_hall_shell(build: Build) -> None:
	"""Walls, portal and vault: mirror tiles between violet ribs."""
	h = HALL
	for y in range(FLOOR, HALL_SPRING):
		for x in range(h["x0"], h["x1"] + 1):
			for z in range(h["z0"], h["z1"] + 1):
				if h["x0"] < x < h["x1"] and h["z0"] < z < h["z1"]:
					continue
				pilaster = (x % 4 == 0 if z in (h["z0"], h["z1"]) else z % 4 == 3)
				band = y == HALL_SPRING - 1
				build.set(x, y, z, GOLD if band else wool("violet") if pilaster else MIRROR)
	# The floor: a checker of polished stone and mirror.
	for x in range(h["x0"] + 1, h["x1"]):
		for z in range(h["z0"] + 1, h["z1"]):
			build.set(x, SURFACE, z, MIRROR if (x + z) % 2 else POLISHED)
	# The vault, and its two gable ends, with crystal glints set into it.
	for x in range(h["x0"], h["x1"] + 1):
		rib = x % 4 == 0
		for z in range(h["z0"], h["z1"] + 1):
			top = hall_vault_top(z)
			if x in (h["x0"], h["x1"]):
				low = HALL_SPRING
			else:
				low = min(hall_vault_top(z - 1) if z > h["z0"] else HALL_SPRING,
					hall_vault_top(z + 1) if z < h["z1"] else HALL_SPRING, top)
			for y in range(low, top + 1):
				glint = not rib and (x * 7 + z * 5 + y) % 13 == 0
				build.set(x, y, z, wool("violet") if rib else CRYSTAL if glint else MIRROR)
	# The portal: an iwan in the west wall, gold-framed, pointed at the top.
	z0, z1 = HALL_PORTAL_Z
	x = h["x0"]
	build.clear(x, FLOOR, z0, x, FLOOR + 4, z1)
	build.clear(x, FLOOR + 5, z0 + 1, x, FLOOR + 5, z1 - 1)
	build.clear(x, FLOOR + 6, (z0 + z1) // 2, x, FLOOR + 6, (z0 + z1) // 2)
	for z in (z0 - 1, z1 + 1):
		build.box(x, FLOOR, z, x, FLOOR + 5, z, GOLD)
	build.set(x, FLOOR + 6, z0, GOLD)
	build.set(x, FLOOR + 6, z1, GOLD)
	build.set(x, FLOOR + 7, (z0 + z1) // 2, GOLD)


def build_balcony(build: Build) -> list[tuple[int, int]]:
	"""The gallery round three sides, its stair, and its parapet. Returns the
	parapet's crystals in chase order: along the south side going east, up the
	east side, back along the north side going west."""
	h = HALL
	for b in BALCONY_DECKS:
		build.box(b["x0"], BALCONY_Y, b["z0"], b["x1"], BALCONY_Y, b["z1"], POLISHED)
	s = BALCONY_STAIR
	for step, x in enumerate(range(s["x0"], s["x1"] + 1)):
		y = FLOOR + step
		if y > FLOOR:
			build.box(x, FLOOR, s["z0"], x, y - 1, s["z1"], BRICK)
		build.box(x, y, s["z0"], x, y, s["z1"], BRICK_STAIR, EAST)

	interior = [(x, z) for x in range(h["x0"] + 1, h["x1"])
		for z in range(h["z0"] + 1, h["z1"])]
	stair = {(x, z) for x in range(s["x0"], s["x1"] + 1)
		for z in range(s["z0"], s["z1"] + 1)}
	open_floor = {c for c in interior if not in_balcony(*c) and c not in stair}
	parapet = [c for c in interior if in_balcony(*c) and any(
		(c[0] + dx, c[1] + dz) in open_floor
		for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1)))]

	# Chase order round the U.
	def order(c):
		x, z = c
		if z <= 9 and x < 25:
			return (0, x, z)
		if x >= 25:
			return (1, z, x)
		return (2, -x, z)
	parapet.sort(key=order)
	lamps = []
	for index, (x, z) in enumerate(parapet):
		if index % 2 == 0:
			build.set(x, BALCONY_Y + 1, z, CRYSTAL_DIM)
			build.set(x, BALCONY_Y + 2, z, CHASE, len(lamps) % 8)
			lamps.append((x, z))
		else:
			build.set(x, BALCONY_Y + 1, z, GLASS)
	# Columns under the gallery's inner edge.
	for x in (15, 19, 23):
		for z in (9, 21):
			build.box(x, FLOOR, z, x, BALCONY_Y - 1, z, COLUMN)
	for z in (13, 17):
		build.box(25, FLOOR, z, 25, BALCONY_Y - 1, z, COLUMN)
	# Lights: hidden ones under the gallery and over the floor.
	for x in (17, 23):
		for z in (8, 22):
			build.set(x, BALCONY_Y - 1, z, HIDDEN_LIGHT)
	build.set(26, BALCONY_Y - 1, 15, HIDDEN_LIGHT)
	build.set(SKULL[0], HALL_SPRING - 1, SKULL[1], HIDDEN_LIGHT)
	return lamps


def build_crystal_skull(build: Build) -> None:
	"""A crystal skull facing the portal, on a gold-edged plinth, with laser
	emitters for eyes that show through the glass."""
	cx, cz = SKULL
	r = SKULL_PLINTH
	build.box(cx - r, FLOOR, cz - r, cx + r, FLOOR, cz + r, POLISHED)
	for x in range(cx - r, cx + r + 1):
		for z in range(cz - r, cz + r + 1):
			if abs(x - cx) == r or abs(z - cz) == r:
				build.set(x, FLOOR, z, GOLD)
	build.sphere(cx, FLOOR + 4, cz, 2.5, CRYSTAL, sy=2.5)
	# Jaw, teeth, sockets and a nose, on the west face.
	front = cx - 2
	build.box(front, FLOOR + 1, cz - 1, cx, FLOOR + 1, cz + 1, CRYSTAL)
	for z in (cz - 1, cz + 1):
		build.set(front, FLOOR + 2, z, BONE)
	build.set(front, FLOOR + 2, cz, AIR)
	build.set(front, FLOOR + 4, cz - 1, LASER_BLOCK)
	build.set(front, FLOOR + 4, cz + 1, LASER_BLOCK)
	build.set(front, FLOOR + 3, cz, AIR)
	for dx, dz in ((-r - 1, -r - 1), (-r - 1, r + 1), (r + 1, -r - 1), (r + 1, r + 1)):
		build.set(cx + dx, FLOOR, cz + dz, UPLIGHT)


def build_mirror_hall() -> Build:
	sx, sy, sz = MIRROR_SIZE
	build = Build(sx, sy, sz)
	build_mirror_forecourt(build)
	build_hall_shell(build)
	build_balcony(build)
	build_crystal_skull(build)
	return build


# --------------------------------------------------------------------------
# 14. Waterfall cascade
# --------------------------------------------------------------------------

# A river that falls down five terraces in glowing sheets, south of the snowy
# mountain: walk through the mountain's tunnel and out of its south mouth, and
# the spur runs on over the water to the foot of the falls. Bioluminescent
# mushrooms, trees and ferns line the way up; clouds hung with morning glories
# shed their petals over it; and at the top, behind the spring the river rises
# from, a volcano erupts flowers. Bike racks and gem geodes belong to
# lw_cascade (bicycles you ride until they break, gems you dig and fuse).
#
# The falls are not flowing liquid. The streams and pools are lw_nodes:water,
# which never spreads, and each sheet is lw_maps:waterfall, an animated,
# glowing, climbable node, so nothing here runs the liquid simulation on the
# WASM worker.
#
# 40 x 28 x 52 is 58,240 cells.
CASCADE_SIZE = (40, 28, 52)
# The causeway lands on the north face, on the middle of the landing.
CASCADE_SPAWN = (19, FLOOR, 51)

# The terraces, north (low, where the causeway lands) to south (high): each
# runs z0..z1 and `top` is the local y of its top solid layer; you stand one
# above it. Each cliff between them is four nodes, and so is each fall.
CASCADE_TIERS = (
	dict(z0=38, z1=51, top=SURFACE),
	dict(z0=31, z1=37, top=SURFACE + 4),
	dict(z0=24, z1=30, top=SURFACE + 8),
	dict(z0=17, z1=23, top=SURFACE + 12),
	dict(z0=0, z1=16, top=SURFACE + 16),
)
CASCADE_RIVER_X = (17, 22)
# Each fall lands in a pool two deep, this many rows into the terrace below
# and two wider than the river either side. The bottom one is the basin.
CASCADE_POOL_ROWS = 2
CASCADE_BASIN_ROWS = 4
CASCADE_POOL_SPREAD = 2
# The basin drains west to the island's edge.
CASCADE_OUTFLOW_Z = (41, 43)

# The path: up the east side to the second terrace, over the river by a
# bridge, up the west side to the spring terrace, and back east over a second
# bridge to the lookout.
CASCADE_LANDING = dict(x0=15, x1=23, z0=46, z1=51)
CASCADE_PATH_EAST_X = (28, 30)
CASCADE_PATH_WEST_X = (9, 11)
# (tier, z0, z1): a plank deck one above the stream, a stair at each end.
CASCADE_BRIDGES = ((2, 26, 27), (4, 13, 14))
CASCADE_LOOKOUT = dict(x0=26, x1=36, z0=12, z1=15)

# The volcano: a basalt cone on the spring terrace's south edge. Its crater
# is where the eruption comes from (`eruption.at` in lw_maps' registry row,
# checked against CASCADE_CRATER by test_luanti_web_maps.py).
VOLCANO = (20, 2)
VOLCANO_TOP = CASCADE_SIZE[1] - 1
VOLCANO_RADIUS_TOP = 2.5
VOLCANO_SLOPE = 1.0                 # nodes of radius per node of height
CASCADE_CRATER = (20, VOLCANO_TOP - 1, 2)
# The spring the river rises from: a glowing sheet down a basalt buttress at
# the cone's foot, into the top pool.
CASCADE_SPRING = dict(x0=18, x1=21, z=11, y1=VOLCANO_TOP - 4)

# Clouds over the falls, morning glories hanging under them: (x, z, y, rx, rz).
# Petals rain from under each one (lw_maps' `showers`), and from the drape of
# morning glories over the spring terrace's edge above the east lawn.
CASCADE_CLOUDS = (
	(19, 43, SURFACE + 12, 5.5, 3.0),
	(19, 31, SURFACE + 18, 6.0, 3.0),
	(31, 20, SURFACE + 21, 4.5, 2.5),
)
CASCADE_DRAPE = dict(x0=25, x1=37, z=17)

# Giant glowing mushrooms in the grove west of the landing: (x, z, stem
# height, cap radius, cap node).
GLOW_CAP = "lw_maps:glow_cap"
GLOW_CAP_VIOLET = "lw_maps:glow_cap_violet"
GLOW_STEM = "lw_maps:glow_stem"
GLOW_LEAVES = "lw_maps:glow_leaves"
GLOW_LEAVES_DIM = "lw_maps:glow_leaves_dim"
GLOW_MOSS = "lw_maps:glow_moss"
CLOUD = "lw_maps:cloud"
CASCADE_MUSHROOMS = (
	(4, 48, 5, 2.5, GLOW_CAP),
	(9, 50, 3, 1.6, GLOW_CAP_VIOLET),
	(11, 46, 6, 2.8, GLOW_CAP_VIOLET),
	(2, 39, 3, 1.5, GLOW_CAP),
)
# Glowing trees: (x, z, trunk height). They stand on whichever terrace holds z.
CASCADE_TREES = (
	(5, 34, 4), (12, 33, 3), (3, 28, 4), (14, 29, 3), (3, 20, 4),
	(37, 21, 3), (4, 9, 5), (35, 5, 4), (7, 3, 4), (31, 9, 3),
)

# Where lw_cascade's racks stand, each beside the path: (x, y, z, facedir).
CASCADE_RACKS = (
	(25, FLOOR, 49, EAST),
	(32, SURFACE + 9, 25, NORTH),
	(13, SURFACE + 13, 19, NORTH),
	(36, SURFACE + 17, 13, EAST),
)
GEODES = ("lw_cascade:geode_red", "lw_cascade:geode_yellow", "lw_cascade:geode_blue")


def cascade_tier(z: int) -> dict:
	for tier in CASCADE_TIERS:
		if tier["z0"] <= z <= tier["z1"]:
			return tier
	raise ValueError(z)


def cascade_top(z: int) -> int:
	return cascade_tier(z)["top"]


def volcano_height(x: int, z: int) -> int:
	"""Local y of the cone's top over (x, z), or -1 off the cone."""
	r = math.hypot(x - VOLCANO[0], z - VOLCANO[1])
	h = VOLCANO_TOP - int((r - VOLCANO_RADIUS_TOP) / VOLCANO_SLOPE + 0.5)
	if r < VOLCANO_RADIUS_TOP:
		h = VOLCANO_TOP
	return h if h > CASCADE_TIERS[-1]["top"] else -1


def cascade_pools() -> list[dict]:
	"""The pool at the foot of each fall, lowest first."""
	pools = []
	x0, x1 = CASCADE_RIVER_X
	for index, tier in enumerate(CASCADE_TIERS[:-1]):
		rows = CASCADE_BASIN_ROWS if index == 0 else CASCADE_POOL_ROWS
		pools.append(dict(x0=x0 - CASCADE_POOL_SPREAD, x1=x1 + CASCADE_POOL_SPREAD,
			z0=tier["z0"], z1=tier["z0"] + rows - 1, top=tier["top"]))
	return pools


def build_cascade_terraces(build: Build) -> None:
	"""The stepped ground: rock, a dirt layer, grass on top."""
	for x in range(build.sx):
		for z in range(build.sz):
			top = cascade_top(z)
			build.box(x, 0, z, x, top - 2, z, STONE)
			build.set(x, top - 1, z, DIRT)
			build.set(x, top, z, GRASS)


def build_cascade_river(build: Build) -> None:
	"""Streams flush with their banks, a pool under every fall, the falls
	themselves, the spring at the top and the basin's outflow."""
	x0, x1 = CASCADE_RIVER_X
	for tier in CASCADE_TIERS[1:]:
		z_start = CASCADE_SPRING["z"] if tier is CASCADE_TIERS[-1] else tier["z0"]
		build.box(x0, tier["top"], z_start, x1, tier["top"], tier["z1"], WATER)
	for pool in cascade_pools():
		build.box(pool["x0"], pool["top"] - 1, pool["z0"], pool["x1"], pool["top"],
			pool["z1"], WATER)
	for lower, upper in zip(CASCADE_TIERS, CASCADE_TIERS[1:]):
		# The sheet hangs in front of the cliff, from the stream's level above
		# down to the pool's surface.
		build.box(x0, lower["top"] + 1, lower["z0"], x1, upper["top"], lower["z0"],
			WATERFALL)
	# The basin's outflow, west to the edge.
	oz0, oz1 = CASCADE_OUTFLOW_Z
	build.box(0, SURFACE, oz0, x0 - CASCADE_POOL_SPREAD - 1, SURFACE, oz1, WATER)

	# The spring: a basalt buttress against the cone, the sheet down its face.
	s = CASCADE_SPRING
	top = CASCADE_TIERS[-1]["top"]
	build.box(s["x0"] - 1, top + 1, s["z"] - 2, s["x1"] + 1, s["y1"] + 1, s["z"] - 1,
		BASALT)
	build.box(s["x0"], top + 1, s["z"], s["x1"], s["y1"], s["z"], WATERFALL)
	build.box(s["x0"], s["y1"] + 1, s["z"] - 1, s["x1"], s["y1"] + 1, s["z"] - 1,
		"lw_maps:crystal")
	build.box(x0, top - 1, s["z"], x1, top, s["z"] + 1, WATER)


def build_cascade_volcano(build: Build) -> None:
	"""The cone, its crater of glowing lava under flicker controllers, and
	three streaks of lava down its flanks."""
	base = CASCADE_TIERS[-1]["top"] + 1
	vx, vz = VOLCANO
	for x in range(build.sx):
		for z in range(build.sz):
			h = volcano_height(x, z)
			if h >= base:
				build.box(x, base, z, x, h, z, BASALT)
	cx, cy, cz = CASCADE_CRATER
	for x in range(vx - 3, vx + 4):
		for z in range(vz - 3, vz + 4):
			r = math.hypot(x - vx, z - vz)
			if r < VOLCANO_RADIUS_TOP:
				build.clear(x, cy, z, x, VOLCANO_TOP, z)
				build.set(x, cy - 1, z, LAVA if r < 1.6 else BASALT)
				if r < 1.6:
					build.set(x, cy, z, FLICKER)
	# Streaks down the north-east and north-west flanks, either side of the
	# spring.
	for angle in (math.pi / 4, 3 * math.pi / 4):
		for step in range(30):
			r = VOLCANO_RADIUS_TOP + 0.5 + step * 0.3
			x = int(round(vx + r * math.cos(angle)))
			z = int(round(vz + r * math.sin(angle)))
			h = volcano_height(x, z) if build.inside(x, 0, z) else -1
			if h >= base:
				build.set(x, h, z, LAVA)


def build_cascade_path(build: Build) -> list[tuple[int, int]]:
	"""The landing, the paved path, its stairs and bridges. Returns the path's
	flat cells in walking order, causeway first, for the lamps along it."""
	order: list[tuple[int, int]] = []

	def pave(x0, z0, x1, z1):
		for z in range(min(z0, z1), max(z0, z1) + 1):
			for x in range(min(x0, x1), max(x0, x1) + 1):
				top = cascade_top(z)
				build.set(x, top, z, PAVING)
				build.clear(x, top + 1, z, x, top + 3, z)
				order.append((x, z))

	stair = "lw_nodes:stair_stone_brick"
	land = CASCADE_LANDING
	ex0, ex1 = CASCADE_PATH_EAST_X
	wx0, wx1 = CASCADE_PATH_WEST_X
	t = CASCADE_TIERS
	pave(land["x0"], land["z1"], land["x1"], land["z0"])
	pave(land["x1"] + 1, 46, ex1, 48)
	pave(ex0, 45, ex1, t[0]["z0"])
	# Up into each terrace from the one below: four steps cut into its cliff.
	stair_run(build, ex0, ex1, t[1]["z1"], -1, t[0]["top"] + 1, 4, stair)
	pave(ex0, t[1]["z1"] - 4, ex1, t[1]["z0"])
	stair_run(build, ex0, ex1, t[2]["z1"], -1, t[1]["top"] + 1, 4, stair)
	b_tier, bz0, bz1 = CASCADE_BRIDGES[0]
	pave(ex0, t[2]["z1"] - 4, ex1, t[2]["z0"])
	pave(ex0 - 1, bz0, CASCADE_RIVER_X[1] + CASCADE_POOL_SPREAD, bz1)
	pave(CASCADE_RIVER_X[0] - 2, bz0, wx0, bz1)
	pave(wx0, bz0 - 1, wx1, t[2]["z0"])
	stair_run(build, wx0, wx1, t[3]["z1"], -1, t[2]["top"] + 1, 4, stair)
	pave(wx0, t[3]["z1"] - 4, wx1, t[3]["z0"])
	stair_run(build, wx0, wx1, t[4]["z1"], -1, t[3]["top"] + 1, 4, stair)
	c_tier, cz0, cz1 = CASCADE_BRIDGES[1]
	pave(wx1 + 1, cz0, CASCADE_RIVER_X[0] - 2, cz1)
	pave(CASCADE_RIVER_X[1] + 2, cz0, CASCADE_LOOKOUT["x0"], cz1)
	lo = CASCADE_LOOKOUT
	pave(lo["x0"], lo["z0"], lo["x1"], lo["z1"])

	# The bridges: a plank deck one above the stream, a stair up at each end.
	x0, x1 = CASCADE_RIVER_X
	for tier_index, z0, z1 in CASCADE_BRIDGES:
		top = CASCADE_TIERS[tier_index]["top"]
		build.box(x0 - 1, top + 1, z0, x0 - 1, top + 1, z1, PLANK_STAIR, EAST)
		build.box(x1 + 1, top + 1, z0, x1 + 1, top + 1, z1, PLANK_STAIR, WEST)
		build.box(x0, top + 1, z0, x1, top + 1, z1, PLANKS)
		build.clear(x0 - 1, top + 2, z0, x1 + 1, top + 4, z1)
		for x in range(x0, x1 + 1, 2):
			for z in (z0 - 1, z1 + 1):
				if build.get(x, top, z) == WATER:
					build.set(x, top + 1, z, "lw_nodes:fence")
		for z in range(z0, z1 + 1):
			order.append((x0 - 1, z))

	# The lookout's rail, along the spring terrace's edge over the east lawn.
	for x in range(lo["x0"] - 1, lo["x1"] + 2):
		build.set(x, CASCADE_TIERS[-1]["top"] + 1, CASCADE_TIERS[-1]["z1"], "lw_nodes:fence")
	return order


def build_cascade_lamps(build: Build, order: list[tuple[int, int]]) -> list[tuple[int, int, int]]:
	"""Glow moss along both edges of the path, each under a chase controller
	numbered by how far up the path it is, so light runs from the causeway to
	the lookout. Returns the moss cells in chase order."""
	rank: dict[tuple[int, int], int] = {}
	for index, cell in enumerate(order):
		rank.setdefault(cell, index)
	path = set(rank)
	lamps: list[tuple[int, int, int, int]] = []
	seen = set()
	for (px, pz), index in sorted(rank.items(), key=lambda item: item[1]):
		for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1)):
			x, z = px + dx, pz + dz
			if (x, z) in path or (x, z) in seen or not build.inside(x, 0, z):
				continue
			top = cascade_top(z)
			if top != cascade_top(pz) or (x + z) % 2:
				continue
			if build.get(x, top, z) != GRASS or build.get(x, top + 1, z) != AIR:
				continue
			seen.add((x, z))
			lamps.append((index, x, top, z))
	lamps.sort()
	out = []
	for number, (_, x, y, z) in enumerate(lamps):
		build.set(x, y, z, GLOW_MOSS)
		# A step of the chase for every three lamps, so a pulse is a short
		# run of moss rather than a single node.
		build.set(x, y + 1, z, CHASE, (number // 3) % 8)
		out.append((x, y, z))
	return out


def glow_tree(build: Build, x: int, z: int, height: int) -> None:
	base = cascade_top(z) + 1
	build.box(x, base, z, x, base + height - 1, z, "lw_nodes:beam")
	cy = base + height
	for cx in range(x - 3, x + 4):
		for cyy in range(cy - 2, cy + 3):
			for cz in range(z - 3, z + 4):
				d = math.sqrt((cx - x) ** 2 + ((cyy - cy) * 1.3) ** 2 + (cz - z) ** 2)
				if d <= 2.4 and build.get(cx, cyy, cz) == AIR:
					build.set(cx, cyy, cz, GLOW_LEAVES)
	build.set(x, cy, z, "lw_nodes:beam")
	# A few top leaves twinkle: dim, with a flicker controller above.
	for dx, dz in ((0, 0), (1, -1), (-1, 1)):
		for y in range(cy + 3, cy - 3, -1):
			if build.get(x + dx, y, z + dz) == GLOW_LEAVES:
				if build.get(x + dx, y + 1, z + dz) == AIR:
					build.set(x + dx, y, z + dz, GLOW_LEAVES_DIM)
					build.set(x + dx, y + 1, z + dz, FLICKER)
				break


def glow_mushroom(build: Build, x: int, z: int, height: int, radius: float, cap: str) -> None:
	base = cascade_top(z) + 1
	build.box(x, base, z, x, base + height - 1, z, GLOW_STEM)
	top = base + height
	reach = int(radius) + 1
	for cx in range(x - reach, x + reach + 1):
		for cz in range(z - reach, z + reach + 1):
			d = math.hypot(cx - x, cz - z)
			if d <= radius:
				build.set(cx, top, cz, cap)
			if d <= radius - 1.2:
				build.set(cx, top + 1, cz, cap)
			# Gills: the cap's rim hangs down a node, so it reads as a cap.
			if radius - 1 < d <= radius:
				if build.get(cx, top - 1, cz) == AIR:
					build.set(cx, top - 1, cz, cap)


def build_cascade_flora(build: Build) -> None:
	for x, z, height, radius, cap in CASCADE_MUSHROOMS:
		glow_mushroom(build, x, z, height, radius, cap)
	for x, z, height in CASCADE_TREES:
		glow_tree(build, x, z, height)
	# Small glowing fungi and ferns scattered over the grass, where nothing
	# else stands.
	for x in range(build.sx):
		for z in range(build.sz):
			top = cascade_top(z)
			if build.get(x, top, z) != GRASS or build.get(x, top + 1, z) != AIR:
				continue
			roll = (x * 31 + z * 17 + (x * z) % 7) % 13
			if roll == 0:
				build.set(x, top + 1, z, GLOW_SHROOM)
			elif roll in (5, 9):
				build.set(x, top + 1, z, GLOW_FERN)
	# Vines down the cliff faces, clear of the falls and the stairs.
	for lower, upper in zip(CASCADE_TIERS, CASCADE_TIERS[1:]):
		z = lower["z0"]
		for x in range(build.sx):
			if CASCADE_RIVER_X[0] - 3 <= x <= CASCADE_RIVER_X[1] + 3:
				continue
			if any(a - 1 <= x <= b + 1 for a, b in (CASCADE_PATH_EAST_X, CASCADE_PATH_WEST_X)):
				continue
			for y in range(lower["top"] + 1, upper["top"] + 1):
				if (x * 5 + y) % 7 == 0 and build.get(x, y, z) == AIR:
					build.set(x, y, z, VINE, NORTH)


def build_cascade_clouds(build: Build) -> None:
	"""Soft glowing clouds with morning glories hanging under them, and the
	drape of them over the spring terrace's edge."""
	for cx, cz, cy, rx, rz in CASCADE_CLOUDS:
		for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
			for z in range(int(cz - rz) - 1, int(cz + rz) + 2):
				d = ((x - cx) / rx) ** 2 + ((z - cz) / rz) ** 2
				if d > 1:
					continue
				build.set(x, cy, z, CLOUD)
				if d < 0.45:
					build.set(x, cy + 1, z, CLOUD)
				if (x + 2 * z) % 3 == 0:
					length = 2 + (x * 7 + z * 3) % 3
					for y in range(cy - length, cy):
						build.set(x, y, z, MORNING_GLORY)
	d = CASCADE_DRAPE
	lip = CASCADE_TIERS[-1]["top"]
	for x in range(d["x0"], d["x1"] + 1):
		if x % 2:
			continue
		length = 1 + (x * 5) % 3
		for y in range(lip - length + 1, lip + 1):
			if build.get(x, y, d["z"]) == AIR:
				build.set(x, y, d["z"], MORNING_GLORY)


def build_cascade_geodes(build: Build) -> list[tuple[int, int, int]]:
	"""lw_cascade's gem geodes, set into the walls of the stairs and the
	first terrace's face, where a visitor on the path can reach them. Returns
	them in placing order (red, yellow, blue, red, ...)."""
	geodes: list[tuple[int, int, int]] = []

	def geode(x, y, z):
		if build.get(x, y, z) in (STONE, DIRT, GRASS):
			build.set(x, y, z, GEODES[len(geodes) % len(GEODES)])
			geodes.append((x, y, z))
			# Nothing in front of it to point at instead.
			for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1)):
				if build.get(x + dx, y, z + dz) == VINE:
					build.clear(x + dx, y, z + dz, x + dx, y, z + dz)

	t = CASCADE_TIERS
	for (x0, x1), upper in ((CASCADE_PATH_EAST_X, t[1]), (CASCADE_PATH_EAST_X, t[2]),
			(CASCADE_PATH_WEST_X, t[3]), (CASCADE_PATH_WEST_X, t[4])):
		z1 = upper["z1"]
		lower_top = upper["top"] - 4
		# Head height on the second step, west wall; the third, east wall.
		geode(x0 - 1, lower_top + 3, z1 - 1)
		geode(x1 + 1, lower_top + 4, z1 - 2)
	for x in (3, 7, 12):
		geode(x, SURFACE + 2, t[1]["z1"])
	return geodes


def build_waterfall_cascade() -> Build:
	sx, sy, sz = CASCADE_SIZE
	build = Build(sx, sy, sz)
	build_cascade_terraces(build)
	build_cascade_volcano(build)
	build_cascade_river(build)
	order = build_cascade_path(build)
	for x, y, z, facing in CASCADE_RACKS:
		build.set(x, y, z, BIKE_RACK, facing)
	build_cascade_lamps(build, order)
	build_cascade_flora(build)
	build_cascade_clouds(build)
	build_cascade_geodes(build)
	return build


# --------------------------------------------------------------------------
# 15. Christmas village
# --------------------------------------------------------------------------

# A snowed-in village square at twilight, east of the giant fruit garden: walk
# down the garden's path and out of its east edge, and the spur runs on over
# the water, under two candy-cane arches, to a tall tree whose baubles chase
# round it in a garland and twinkle in between, with presents round its foot
# and a star on top. A workshop cabin with a fire, a sleigh and its reindeer,
# a frozen pond, snowmen and snow-capped pines fill the corners, and snow
# falls round whoever is there (lw_maps' `snow` ambience).
#
# 40 x 24 x 40 is 38,400 cells.
XMAS_SIZE = (40, 24, 40)
# The causeway lands on the west face, on the middle of the path.
XMAS_SPAWN = (0, FLOOR, 20)

XMAS_PATH_Z = (19, 21)
XMAS_ARCHES = (4, 10)                 # x of the candy-cane arches over the path
XMAS_TREE = (20, 20)                  # x, z of the big tree's trunk
XMAS_TREE_BASE = FLOOR + 2            # its lowest course of needles
XMAS_TREE_TOP = FLOOR + 15            # its tip; the star stands on it
XMAS_TREE_RADIUS = 6.0                # at the lowest course
XMAS_SQUARE_RADIUS = 10.5             # the swept square round the tree
XMAS_CABIN = dict(x0=25, x1=35, z0=29, z1=37)
XMAS_CABIN_DOOR_X = (30, 31)
XMAS_SLEIGH = dict(x0=26, x1=31, z0=6, z1=8)
XMAS_REINDEER = ((33, 6), (33, 8), (36, 6), (36, 8))   # (x of the rump, z)
XMAS_POND = (9, 9)
XMAS_POND_RADIUS = 5.0
XMAS_SNOWMEN = ((6, 30), (11, 33))
# (x, z, height) of the snow-capped pines round the edge.
XMAS_PINES = ((3, 3, 7), (17, 3, 6), (37, 14, 6), (37, 23, 7), (21, 36, 6),
	(3, 37, 7), (15, 37, 5), (2, 13, 5))

PRESENTS = tuple("lw_maps:present_" + c for c in ("red", "green", "blue", "gold", "violet"))
BAUBLES = tuple("lw_maps:bauble_" + c for c in ("red", "gold", "blue"))
CANDY = "lw_maps:candy_cane"
STAR = "lw_maps:star"
HOA_HOLIDAY_MEMO = "lw_maps:hoa_holiday_memo"


def cone_radius(y: int, base: int, top: int, radius: float) -> float:
	"""A Christmas tree's radius at course `y`: a cone from `radius` at `base`
	to nothing at `top`, every third course a little wider, so it reads as
	tiers of branches rather than a smooth spike."""
	if y < base or y > top:
		return -1.0
	t = (y - base) / (top - base)
	r = radius * (1 - t)
	if (y - base) % 3 == 0:
		r += 0.7 * (1 - t)
	return max(r, 0.5)


def build_tree_cone(build: Build, cx: int, cz: int, base: int, top: int,
		radius: float, fill: str) -> list[tuple[int, int, int]]:
	"""A cone of `fill`. Returns its outer cells with open air above them —
	the ones a light can sit in with a controller over it — lowest first."""
	reach = int(radius + 1.5)
	cells = set()
	for y in range(base, top + 1):
		r = cone_radius(y, base, top, radius)
		for x in range(cx - reach, cx + reach + 1):
			for z in range(cz - reach, cz + reach + 1):
				if math.hypot(x - cx, z - cz) <= r:
					build.set(x, y, z, fill)
					cells.add((x, y, z))
	exposed = [c for c in cells if (c[0], c[1] + 1, c[2]) not in cells
		and (c[0], c[2]) != (cx, cz)]
	exposed.sort(key=lambda c: (c[1], math.atan2(c[2] - cz, c[0] - cx)))
	return exposed


def garland(cells, cx: int, cz: int, base: int, turn: float, phase: float,
		spread: float = 0.45) -> list[tuple[int, int, int]]:
	"""The exposed cells a garland winding up the tree passes through: one
	turn every `turn` courses, starting at angle `phase`. In chase order,
	bottom to top."""
	picked = []
	for x, y, z in cells:
		want = phase + (y - base) / turn * 2 * math.pi
		got = math.atan2(z - cz, x - cx)
		diff = (got - want + math.pi) % (2 * math.pi) - math.pi
		if abs(diff) <= spread:
			picked.append((x, y, z, (y - base) * 10 + diff))
	picked.sort(key=lambda c: c[3])
	return [(x, y, z) for x, y, z, _ in picked]


def snow_pine(build: Build, x: int, z: int, height: int) -> None:
	"""A small pine with a cap of snow: a brown trunk and a cone of needles."""
	build.set(x, FLOOR, z, wool("brown"))
	top = FLOOR + height - 1
	build_tree_cone(build, x, z, FLOOR + 1, top, 2.2, PINE_LEAVES)
	build.set(x, top + 1, z, SNOW)


def build_xmas_ground(build: Build) -> None:
	"""Snow everywhere, a swept square round the tree, the path in from the
	causeway with its arches and posts, and paths out to the cabin and the
	sleigh."""
	sx, _, sz = build.sx, build.sy, build.sz
	build.ground(SNOW)
	cx, cz = XMAS_TREE
	for x in range(sx):
		for z in range(sz):
			if math.hypot(x - cx, z - cz) <= XMAS_SQUARE_RADIUS:
				build.set(x, SURFACE, z, PACKED_SNOW)
	z0, z1 = XMAS_PATH_Z
	build.box(0, SURFACE, z0, cx, SURFACE, z1, PAVING)
	# Paths out of the square: north-east to the cabin door, south-east to
	# the sleigh.
	d0, d1 = XMAS_CABIN_DOOR_X
	build.box(d0 - 1, SURFACE, 26, d1 + 1, SURFACE, XMAS_CABIN["z0"] - 1, PAVING)
	build.box(27, SURFACE, 10, 29, SURFACE, 13, PAVING)
	# Candy-cane posts along the path, every other node, both sides, and a
	# lamp post every five.
	for x in range(1, 13):
		if x in XMAS_ARCHES:
			continue
		if x % 2 == 0:
			build.set(x, FLOOR, z0 - 1, CANDY)
			build.set(x, FLOOR, z1 + 1, CANDY)
	for x in (2, 7, 13):
		for z in (z0 - 2, z1 + 2):
			build.box(x, FLOOR, z, x, FLOOR + 1, z, COLUMN)
			build.set(x, FLOOR + 2, z, LANTERN)
	# The arches: candy-cane posts, a lintel four over the path, and a red
	# bauble and a star on top.
	for x in XMAS_ARCHES:
		for z in (z0 - 1, z1 + 1):
			build.box(x, FLOOR, z, x, FLOOR + 3, z, CANDY)
		build.box(x, FLOOR + 4, z0 - 1, x, FLOOR + 4, z1 + 1, CANDY)
		build.set(x, FLOOR + 5, (z0 + z1) // 2, STAR)
		for z in (z0 - 1, z1 + 1):
			build.set(x, FLOOR + 5, z, BAUBLES[0])
	# The HOA's holiday notice, on a pedestal by the first arch, facing the
	# path.
	build.set(6, FLOOR, z1 + 2, PEDESTAL)
	build.set(6, FLOOR + 1, z1 + 2, HOA_HOLIDAY_MEMO, NORTH)


def build_xmas_tree(build: Build) -> list[tuple[int, int, int]]:
	"""The big tree: trunk, tiers, a chasing garland, twinkling baubles, the
	star, and presents round its foot. Returns the garland in chase order."""
	cx, cz = XMAS_TREE
	build.box(cx, FLOOR, cz, cx, XMAS_TREE_TOP - 1, cz, wool("brown"))
	exposed = build_tree_cone(build, cx, cz, XMAS_TREE_BASE, XMAS_TREE_TOP,
		XMAS_TREE_RADIUS, PINE_LEAVES)
	# Two garlands, half a turn apart, each in its own colour run.
	lights = []
	taken = set()
	for phase in (0.0, math.pi):
		for cell in garland(exposed, cx, cz, XMAS_TREE_BASE, 5.0, phase):
			if cell not in taken:
				taken.add(cell)
				lights.append(cell)
	lights.sort(key=lambda c: (c[1], (math.atan2(c[2] - cz, c[0] - cx)
		- (c[1] - XMAS_TREE_BASE) / 5.0 * 2 * math.pi) % math.pi))
	for index, (x, y, z) in enumerate(lights):
		build.set(x, y, z, BAUBLES[index % len(BAUBLES)] + "_off")
		build.set(x, y + 1, z, CHASE, index % 8)
	# Twinkling baubles in between, under flicker.
	for x, y, z in exposed:
		if (x, y, z) in taken or y >= XMAS_TREE_TOP - 1:
			continue
		if (x * 7 + y * 13 + z * 5) % 5 == 0:
			build.set(x, y, z, BAUBLES[(x + z + y) % len(BAUBLES)])
			build.set(x, y + 1, z, FLICKER)
	# The star: a cross standing on the tip, facing the path.
	top = XMAS_TREE_TOP
	build.box(cx, top + 1, cz, cx, top + 3, cz, STAR)
	build.set(cx, top + 2, cz - 1, STAR)
	build.set(cx, top + 2, cz + 1, STAR)
	# Presents round the foot, with a gap on each side to get in to the tree.
	for index in range(28):
		angle = index / 28 * 2 * math.pi
		if any(abs((angle - gap + math.pi) % (2 * math.pi) - math.pi) < 0.3
				for gap in (0, math.pi / 2, math.pi, 3 * math.pi / 2)):
			continue
		radius = 7 + (index % 2)
		x = int(round(cx + radius * math.cos(angle)))
		z = int(round(cz + radius * math.sin(angle)))
		build.set(x, FLOOR, z, PRESENTS[index % len(PRESENTS)])
	# Lamp posts on the square's diagonals.
	for dx, dz in ((-7, -7), (7, -7), (-7, 7), (7, 7)):
		build.box(cx + dx, FLOOR, cz + dz, cx + dx, FLOOR + 2, cz + dz, COLUMN)
		build.set(cx + dx, FLOOR + 3, cz + dz, LANTERN)
	return lights


def build_xmas_cabin(build: Build) -> None:
	"""The workshop: plank walls on beam corners, lit windows, a snowy gable
	roof with lights along the eaves, a fire and a chimney, a workbench piled
	with presents."""
	c = XMAS_CABIN
	x0, x1, z0, z1 = c["x0"], c["x1"], c["z0"], c["z1"]
	wall_top = FLOOR + 3
	build.box(x0, SURFACE, z0, x1, SURFACE, z1, PLANKS)
	for y in range(FLOOR, wall_top + 1):
		for x in range(x0, x1 + 1):
			for z in range(z0, z1 + 1):
				if x0 < x < x1 and z0 < z < z1:
					continue
				corner = x in (x0, x1) and z in (z0, z1)
				window = (y in (FLOOR + 1, FLOOR + 2) and not corner and (
					(z in (z0, z1) and x % 3 == 0) or (x in (x0, x1) and z % 3 == 0)))
				build.set(x, y, z, BEAM if corner else GLASS if window else PLANKS)
	build.clear(x0 + 1, FLOOR, z0 + 1, x1 - 1, wall_top, z1 - 1)
	# The door.
	d0, d1 = XMAS_CABIN_DOOR_X
	build.clear(d0, FLOOR, z0, d1, FLOOR + 2, z0)
	# The roof: courses stepping in from both long sides, red under snow.
	span = (z1 - z0) // 2 + 1
	for k in range(span + 1):
		y = wall_top + 1 + k
		lo, hi = z0 - 1 + k, z1 + 1 - k
		if lo > hi:
			break
		build.box(x0 - 1, y, lo, x1 + 1, y, hi, wool("red"))
		# Gable ends, and the attic's hollow behind them.
		if hi - lo >= 2:
			build.clear(x0 + 1, y, lo + 1, x1 - 1, y, hi - 1)
		for x in range(x0 - 1, x1 + 2):
			build.set(x, y + 1, lo, SNOW_SLAB)
			build.set(x, y + 1, hi, SNOW_SLAB)
	# Lights along both eaves.
	for x in range(x0 - 1, x1 + 2):
		for z in (z0 - 1, z1 + 1):
			if x % 2 == 0:
				build.set(x, wall_top, z, BAUBLES[(x // 2) % len(BAUBLES)])
	# A ceiling to keep the attic out of sight, lit from under it.
	build.box(x0 + 1, wall_top + 1, z0 + 1, x1 - 1, wall_top + 1, z1 - 1, PLANKS)
	for x in (x0 + 3, x1 - 3):
		build.set(x, wall_top, (z0 + z1) // 2, HIDDEN_LIGHT)
	# The fireplace on the north wall, its chimney up through the roof.
	fx = (d0 + d1) // 2
	build.box(fx - 2, FLOOR, z1 - 1, fx + 3, FLOOR + 3, z1 - 1, BRICK)
	build.clear(fx, FLOOR, z1 - 1, fx + 1, FLOOR + 1, z1 - 1)
	build.box(fx, FLOOR, z1 - 1, fx + 1, FLOOR, z1 - 1, FIRE)
	build.box(fx, SURFACE, z1 - 1, fx + 1, SURFACE, z1 - 1, BRICK)
	build.box(fx, wall_top + 1, z1, fx + 1, wall_top + span + 2, z1, BRICK)
	# A rug in front of it, a workbench with presents along the west wall,
	# and a small tree in the south-east corner.
	build.box(fx - 1, FLOOR, z1 - 4, fx + 2, FLOOR, z1 - 2, CARPET)
	build.box(x0 + 1, FLOOR, z0 + 2, x0 + 1, FLOOR, z1 - 2, PLANKS)
	for z in range(z0 + 2, z1 - 1, 2):
		build.set(x0 + 1, FLOOR + 1, z, PRESENTS[z % len(PRESENTS)])
	build.set(x1 - 1, FLOOR, z0 + 1, wool("brown"))
	build.box(x1 - 1, FLOOR + 1, z0 + 1, x1 - 1, FLOOR + 2, z0 + 1, PINE_LEAVES)
	build.set(x1 - 1, FLOOR + 3, z0 + 1, STAR)


def build_xmas_sleigh(build: Build) -> None:
	"""A red sleigh on gold runners, piled with presents, and four reindeer
	in harness in front of it, the leader with a red nose."""
	s = XMAS_SLEIGH
	x0, x1, z0, z1 = s["x0"], s["x1"], s["z0"], s["z1"]
	for z in (z0, z1):
		build.box(x0, FLOOR, z, x1, FLOOR, z, GOLD)
		build.set(x1 + 1, FLOOR + 1, z, GOLD)
	build.box(x0, FLOOR + 1, z0, x1, FLOOR + 1, z1, wool("red"))
	for z in (z0, z1):
		build.box(x0, FLOOR + 2, z, x1 - 1, FLOOR + 2, z, wool("red"))
		build.set(x1, FLOOR + 2, z, GOLD)
	build.box(x0, FLOOR + 2, z0, x0, FLOOR + 3, z1, wool("red"))
	build.box(x0, FLOOR + 4, z0, x0, FLOOR + 4, z1, GOLD)
	for index, x in enumerate(range(x0 + 1, x1)):
		build.set(x, FLOOR + 2, (z0 + z1) // 2, PRESENTS[index % len(PRESENTS)])
	build.set(x0 + 1, FLOOR + 3, (z0 + z1) // 2, PRESENTS[3])
	for index, (x, z) in enumerate(XMAS_REINDEER):
		build.set(x, FLOOR, z, FENCE)
		build.set(x + 1, FLOOR, z, FENCE)
		build.box(x, FLOOR + 1, z, x + 1, FLOOR + 1, z, wool("brown"))
		build.set(x + 2, FLOOR + 2, z, wool("brown"))
		# Antlers: up off the head, and one tine back over the neck.
		build.set(x + 2, FLOOR + 3, z, DEAD_WOOD)
		build.set(x + 1, FLOOR + 4, z, DEAD_WOOD)
		if index >= 2:
			build.set(x + 3, FLOOR + 2, z, BAUBLES[0] if index == 2 else wool("black"))


def build_xmas_corners(build: Build) -> None:
	"""The pond, the snowmen and the pines."""
	px, pz = XMAS_POND
	for x in range(px - 6, px + 7):
		for z in range(pz - 6, pz + 7):
			d = math.hypot(x - px, z - pz)
			if d <= XMAS_POND_RADIUS:
				build.set(x, SURFACE, z, ICE)
			elif d <= XMAS_POND_RADIUS + 1 and (x + z) % 3 == 0:
				build.set(x, FLOOR, z, SNOW_SLAB)
	# A bench on the pond's north bank, facing the ice.
	for x in (px - 1, px, px + 1):
		build.set(x, FLOOR, pz + 6, PLANK_STAIR, NORTH)
	for cx, cz in XMAS_SNOWMEN:
		build.sphere(cx, FLOOR + 1, cz, 1.5, SNOW)
		build.set(cx, FLOOR + 3, cz, SNOW)
		build.set(cx + 1, FLOOR + 3, cz, wool("orange"))
		build.box(cx, FLOOR + 4, cz, cx, FLOOR + 5, cz, wool("black"))
		build.set(cx + 1, FLOOR + 2, cz, wool("black"))
		build.set(cx, FLOOR + 2, cz - 1, wool("red"))
		build.set(cx, FLOOR + 2, cz + 1, wool("red"))
	for x, z, height in XMAS_PINES:
		snow_pine(build, x, z, height)


def build_christmas() -> Build:
	sx, sy, sz = XMAS_SIZE
	build = Build(sx, sy, sz)
	build_xmas_ground(build)
	build_xmas_corners(build)
	build_xmas_tree(build)
	build_xmas_cabin(build)
	build_xmas_sleigh(build)
	return build


# --------------------------------------------------------------------------
# 16. Weeks on Fire Christmas
# --------------------------------------------------------------------------

# Christmas the Weeks on Fire way, south of the laser serpent: walk off the
# south side of its ash field and the spur crosses the water onto a mirror
# colonnade under a neon arch. Snow falls on ash. At the end of the walk a
# Christmas tree is on fire — ember needles under flicker controllers, a neon
# garland chasing up it, crystal baubles, a star — and festive anyway, with
# presents round it, embers rising off it, and lasers spiralling up it like
# tinsel (lw_maps' laser show with the serpent's `coil` pattern). Beyond it a
# cabaret stage puts on a Christmas revue: velvet curtain, mirror wings,
# chasing bulbs, crystal trees and a console that switches the lasers; a
# mirror ball hangs over the dance floor. Two HOA boards keep the holiday
# memos.
#
# 36 x 22 x 40 is 31,680 cells.
WOF_XMAS_SIZE = (36, 22, 40)
# The causeway lands on the north face, on the middle of the walk.
WOF_XMAS_SPAWN = (18, FLOOR, 39)

WOF_XMAS_WALK_X = (17, 19)
WOF_XMAS_WALK_Z0 = 31                # the walk runs from here to the north edge
WOF_XMAS_ARCH_Z = 37
WOF_XMAS_COLONNADE_X = (14, 22)
WOF_XMAS_PILLARS_Z = (31, 34, 37)
WOF_XMAS_TREE = (18, 24)
WOF_XMAS_TREE_BASE = FLOOR + 1
WOF_XMAS_TREE_TOP = FLOOR + 13
WOF_XMAS_TREE_RADIUS = 5.0
WOF_XMAS_PLAZA_RADIUS = 9.5
# The lasers' `coil`: a helix outside the tree, which the emitters climb.
# lw_maps' wof_christmas `lasers.coil` is the same; the test checks both.
WOF_XMAS_COIL = dict(x=18, z=24, radius=7.0, y0=FLOOR + 1, rise=11, turns=3.0,
	start=math.pi / 2)
WOF_XMAS_STAGE = dict(x0=7, x1=28, z0=2, z1=7)    # the deck; stand on it at +1
WOF_XMAS_STAGE_STAIRS = ((8, 9), (26, 27))
WOF_XMAS_CONSOLE = (18, FLOOR + 1, 3)
WOF_XMAS_DANCE = dict(x0=8, x1=27, z0=9, z1=14)
WOF_XMAS_BALL = (18, FLOOR + 8, 11)
WOF_XMAS_PYLONS = ((2, 2), (33, 2), (2, 37), (33, 37))
WOF_XMAS_PYLON_TOP = FLOOR + 11
WOF_XMAS_MEMOS = ((21, FLOOR + 1, 38, EAST), (5, FLOOR + 1, 11, WEST))


def build_wof_xmas_ground(build: Build) -> None:
	"""Snow on ash, the scorched plaza round the tree, the walk in and its
	neon, the arch and the mirror colonnade, the pylons."""
	sx, _, sz = build.sx, build.sy, build.sz
	build.ground(SNOW, sub=STONE)
	for x in range(sx):
		for z in range(sz):
			if (x * 5 + z * 3 + (x * z) % 7) % 9 < 2:
				build.set(x, SURFACE, z, wool("dark_grey"))
	cx, cz = WOF_XMAS_TREE
	for x in range(sx):
		for z in range(sz):
			d = math.hypot(x - cx, z - cz)
			if d <= WOF_XMAS_PLAZA_RADIUS:
				build.set(x, SURFACE, z, PACKED_BASALT)
	x0, x1 = WOF_XMAS_WALK_X
	build.box(x0, SURFACE, WOF_XMAS_WALK_Z0, x1, SURFACE, sz - 1, PACKED_BASALT)
	for z in range(WOF_XMAS_WALK_Z0, sz - 2):
		build.set(x0 - 1, FLOOR, z, NEON, EAST)
		build.set(x1 + 1, FLOOR, z, NEON, EAST)
	# The arch: candy-cane posts and a lintel of glowing serpent scales.
	z = WOF_XMAS_ARCH_Z
	for x in (x0 - 2, x1 + 2):
		build.box(x, FLOOR, z, x, FLOOR + 3, z, CANDY)
	build.box(x0 - 2, FLOOR + 4, z, x1 + 2, FLOOR + 4, z, SERPENT_SCALE)
	build.set((x0 + x1) // 2, FLOOR + 5, z, STAR)
	# Pylons at the corners, a laser emitter on each: the `sweep` pattern's
	# emitters race round from cap to cap.
	for x, z in WOF_XMAS_PYLONS:
		build.box(x, SURFACE, z, x, WOF_XMAS_PYLON_TOP - 1, z, PACKED_BASALT)
		build.set(x, WOF_XMAS_PYLON_TOP, z, LASER_BLOCK)
	for mx, my, mz, facing in WOF_XMAS_MEMOS:
		build.set(mx, my - 1, mz, PEDESTAL)
		build.set(mx, my, mz, HOA_HOLIDAY_MEMO, facing)


def build_wof_xmas_colonnade(build: Build) -> list[tuple[int, int, int]]:
	"""Mirror pillars either side of the walk, glass between them, a crystal
	on each that chases down one side and back up the other."""
	lamps = []
	for side, x in enumerate(WOF_XMAS_COLONNADE_X):
		zs = WOF_XMAS_PILLARS_Z if side == 0 else tuple(reversed(WOF_XMAS_PILLARS_Z))
		for z in zs:
			build.box(x, FLOOR, z, x, FLOOR + 2, z, MIRROR)
			build.set(x, FLOOR + 3, z, CRYSTAL_DIM)
			build.set(x, FLOOR + 4, z, CHASE, len(lamps) % 8)
			lamps.append((x, FLOOR + 3, z))
		for a, b in zip(WOF_XMAS_PILLARS_Z, WOF_XMAS_PILLARS_Z[1:]):
			build.box(x, FLOOR, a + 1, x, FLOOR + 1, b - 1, GLASS)
	return lamps


def build_burning_tree(build: Build) -> list[tuple[int, int, int]]:
	"""The tree on fire: a charred trunk, needles of ember blocks that
	flicker, a neon garland chasing up it, crystal baubles, a star with a
	laser at its heart, and presents round the foot. Returns the garland."""
	cx, cz = WOF_XMAS_TREE
	base, top = WOF_XMAS_TREE_BASE, WOF_XMAS_TREE_TOP
	build.box(cx, FLOOR, cz, cx, top - 1, cz, PACKED_BASALT)
	exposed = build_tree_cone(build, cx, cz, base, top, WOF_XMAS_TREE_RADIUS, EMBER_OFF)
	lights = garland(exposed, cx, cz, base, 4.0, math.pi / 2)
	for index, (x, y, z) in enumerate(lights):
		build.set(x, y, z, SERPENT_SCALE_OFF)
		build.set(x, y + 1, z, CHASE, index % 8)
	taken = set(lights)
	for x, y, z in exposed:
		if (x, y, z) in taken:
			continue
		h = (x * 7 + y * 13 + z * 5) % 6
		if h == 0 and y < top - 1:
			build.set(x, y, z, CRYSTAL)
		elif h in (1, 2, 3):
			build.set(x, y, z, EMBER)
			build.set(x, y + 1, z, FLICKER)
	# Smoulder on the sides as well: two in five of the needles facing out
	# glow without flickering, so the tree reads as alight from any side.
	reach = int(WOF_XMAS_TREE_RADIUS + 2)
	for y in range(base, top + 1):
		for x in range(cx - reach, cx + reach + 1):
			for z in range(cz - reach, cz + reach + 1):
				if build.get(x, y, z) != EMBER_OFF:
					continue
				if any(build.get(x + dx, y, z + dz) == AIR
						for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1))) \
						and (x * 3 + y * 7 + z * 11) % 5 < 2:
					build.set(x, y, z, EMBER)
	build.box(cx, top + 1, cz, cx, top + 3, cz, STAR)
	build.set(cx - 1, top + 2, cz, STAR)
	build.set(cx + 1, top + 2, cz, STAR)
	build.set(cx, top + 2, cz, LASER_BLOCK)
	# Presents, a few of them singed.
	for index in range(24):
		angle = index / 24 * 2 * math.pi
		if abs((angle - math.pi / 2 + math.pi) % (2 * math.pi) - math.pi) < 0.35:
			continue                         # the way in from the walk
		x = int(round(cx + 6.2 * math.cos(angle)))
		z = int(round(cz + 6.2 * math.sin(angle)))
		build.set(x, FLOOR, z, EMBER_OFF if index % 7 == 3 else
			PRESENTS[index % len(PRESENTS)])
	# Uplights in the plaza, pointing at the smoke.
	for dx, dz in ((-8, 0), (8, 0), (0, -8)):
		build.set(cx + dx, FLOOR, cz + dz, UPLIGHT)
	return lights


def build_wof_xmas_stage(build: Build) -> list[tuple[int, int]]:
	"""The revue stage and its dance floor. Returns the proscenium bulbs in
	chase order, west to east."""
	s = WOF_XMAS_STAGE
	x0, x1, z0, z1 = s["x0"], s["x1"], s["z0"], s["z1"]
	top = FLOOR + 6
	build.box(x0, FLOOR, z0, x1, FLOOR, z1, wool("black"))
	build.box(x0, FLOOR, z1, x1, FLOOR, z1, GOLD)
	# Velvet backdrop, mirror wings, gold header and a velvet valance.
	build.box(x0 - 1, SURFACE, z0 - 1, x1 + 1, top, z0 - 1, CURTAIN)
	for x in (x0 - 1, x1 + 1):
		build.box(x, SURFACE, z0, x, top, z1, MIRROR)
	build.box(x0 - 1, top, z1, x1 + 1, top, z1, GOLD)
	build.box(x0, top - 1, z1, x1, top - 1, z1, CURTAIN)
	# Stairs up at each end of the front.
	for a, b in WOF_XMAS_STAGE_STAIRS:
		build.box(a, FLOOR, z1 + 1, b, FLOOR, z1 + 1, PLANK_STAIR, SOUTH)
	# Chasing bulbs in front of the header.
	bulbs = []
	for x in range(x0, x1 + 1, 3):
		build.set(x, top - 1, z1 + 1, LANTERN_OFF)
		build.set(x, top, z1 + 1, CHASE, len(bulbs) % 8)
		bulbs.append((x, z1 + 1))
	# The console, facing the floor, and the revue's set: presents, two
	# crystal trees with stars, and lights hidden in the flies.
	build.set(*WOF_XMAS_CONSOLE, SERPENT_SWITCH, SOUTH)
	for x in (x0 + 2, x0 + 3, x1 - 3, x1 - 2):
		build.set(x, FLOOR + 1, z0 + 1, PRESENTS[x % len(PRESENTS)])
	for tx in (x0 + 4, x1 - 4):
		for y, r in ((FLOOR + 1, 1.5), (FLOOR + 2, 1.0), (FLOOR + 3, 0.5)):
			for x in range(tx - 2, tx + 3):
				for z in range(z0 + 1, z0 + 6):
					if math.hypot(x - tx, z - (z0 + 3)) <= r:
						build.set(x, y, z, CRYSTAL)
		build.set(tx, FLOOR + 4, z0 + 3, STAR)
	for x in (x0 + 6, (x0 + x1) // 2, x1 - 6):
		build.set(x, top - 1, z0 + 2, HIDDEN_LIGHT)
	# The dance floor: black and magenta, a mirror ball over it on a chain.
	d = WOF_XMAS_DANCE
	for x in range(d["x0"], d["x1"] + 1):
		for z in range(d["z0"], d["z1"] + 1):
			build.set(x, SURFACE, z, wool("magenta") if (x // 2 + z // 2) % 2 else wool("black"))
	bx, by, bz = WOF_XMAS_BALL
	build.sphere(bx, by, bz, 1.5, MIRROR)
	build.box(bx, by + 2, bz, bx, by + 4, bz, FENCE)
	# Floating ornaments round the floor: crystals with gold caps, hung from
	# nothing at all.
	for index, (x, z) in enumerate(((10, 10), (14, 13), (22, 13), (26, 10), (12, 16),
			(24, 16))):
		y = FLOOR + 5 + index % 3
		build.set(x, y, z, CRYSTAL if index % 2 == 0 else BAUBLES[index % 3])
		build.set(x, y + 1, z, GOLD)
		build.set(x, y + 2, z, FENCE)
	return bulbs


def build_wof_christmas() -> Build:
	sx, sy, sz = WOF_XMAS_SIZE
	build = Build(sx, sy, sz)
	build_wof_xmas_ground(build)
	build_wof_xmas_colonnade(build)
	build_burning_tree(build)
	build_wof_xmas_stage(build)
	return build


# --------------------------------------------------------------------------
# Driver
# --------------------------------------------------------------------------

@dataclasses.dataclass(frozen=True)
class MapSpec:
	"""One map in the pack: the whole Python side of the add-a-map recipe.

	``name`` is the schematic, ``map_<id>``, where ``<id>`` is what
	``lw_maps.register`` and ``/maps`` call it. ``spawn`` is local and has to
	be where the causeway lands; ``test_luanti_web_maps.py`` checks it against
	the registry and flood-fills the map from it.
	"""
	name: str
	size: tuple[int, int, int]
	spawn: tuple[int, int, int]
	build: typing.Callable[[], Build]

	@property
	def id(self) -> str:
		return self.name[len("map_"):]

	@property
	def volume(self) -> int:
		return self.size[0] * self.size[1] * self.size[2]


SPECS = [
	MapSpec("map_halloween", HALLOWEEN_SIZE, HALLOWEEN_SPAWN, build_halloween),
	MapSpec("map_snow_mountain", SNOW_SIZE, SNOW_SPAWN, build_snow_mountain),
	MapSpec("map_fruit_garden", FRUIT_SIZE, FRUIT_SPAWN, build_fruit_garden),
	MapSpec("map_lighthouse_tide", LIGHTHOUSE_SIZE, LIGHTHOUSE_SPAWN,
		build_lighthouse_tide),
	MapSpec("map_crystal_bazaar", BAZAAR_SIZE, BAZAAR_SPAWN, build_crystal_bazaar),
	MapSpec("map_smoke_caldera", CALDERA_SIZE, CALDERA_SPAWN, build_smoke_caldera),
	MapSpec("map_rainbow_storm", RAINBOW_SIZE, RAINBOW_SPAWN, build_rainbow_storm),
	MapSpec("map_around_arena", ARENA_SIZE, ARENA_SPAWN, build_arena),
	MapSpec("map_halloween_storm", STORM_CHAPEL_SIZE, STORM_CHAPEL_SPAWN,
		build_halloween_storm),
	MapSpec("map_cabaret", CABARET_SIZE, CABARET_SPAWN, build_cabaret),
	MapSpec("map_concert_arena", CONCERT_SIZE, CONCERT_SPAWN, build_concert_arena),
	MapSpec("map_laser_serpent", SERPENT_SIZE, SERPENT_SPAWN, build_laser_serpent),
	MapSpec("map_mirror_hall", MIRROR_SIZE, MIRROR_SPAWN, build_mirror_hall),
	MapSpec("map_waterfall_cascade", CASCADE_SIZE, CASCADE_SPAWN,
		build_waterfall_cascade),
	MapSpec("map_christmas", XMAS_SIZE, XMAS_SPAWN, build_christmas),
	MapSpec("map_wof_christmas", WOF_XMAS_SIZE, WOF_XMAS_SPAWN, build_wof_christmas),
]

MAPS = {spec.name: spec.build for spec in SPECS}
SIZES = {spec.name: spec.size for spec in SPECS}
SPAWNS = {spec.name: spec.spawn for spec in SPECS}

# The pack's node budget, in schematic *volume* (box cells, air included).
#
# lw_world/schems.lua keeps each schematic run-length encoded, a row at a time,
# in two Lua strings: about 0.4 bytes a cell for these maps, 127 KiB for all
# thirteen. The volume therefore no longer sets what the pack keeps in the heap;
# test_luanti_web_maps.py measures that directly and caps it. What volume still
# costs is the high-water mark while a map loads (the engine's read_schematic
# builds one small table per cell, about 250 bytes each, before the loader packs
# it), the work of generating and meshing the cells, and the review burden of a
# map nobody can walk end to end. So there are two volume caps, both creep
# guards: MAX_MAP_VOLUME for one map (its load peak stays under 16 MiB) and
# NODE_BUDGET for the pack. The numbers and the reasoning are in
# wasm_porting.md ("Content Budget") and games/luanti_web/docs/maps.md
# ("Budget").
#
# History: 120,000 cells before the cost was measured, then 200,000 to 272,000
# while the loader kept two Lua arrays with a slot per cell (1 MiB per
# 32,768 cells, so the box was the budget). Run-length storage took the pack
# from 10.0 MiB kept to 110 KiB, and the cell cap was re-based at 512,000:
# roughly the eleven maps of the time again, with their share of room for
# about eight more maps the size of the concert arena. The two Weeks on Fire
# islands (laser serpent, mirror hall) took 36,898 of that: 308,166. The
# waterfall cascade adds 58,240 (the pack's biggest box): 366,406 now.
NODE_BUDGET = 512_000
MAX_MAP_VOLUME = 65_536


def pack_volume() -> int:
	return sum(spec.volume for spec in SPECS)


def schematics() -> dict[str, Schematic]:
	out = {}
	for name, factory in MAPS.items():
		build = factory()
		expected = SIZES[name]
		if (build.sx, build.sy, build.sz) != expected:
			raise SystemExit(f"{name}: built {build.sx}x{build.sy}x{build.sz}, "
				f"expected {expected[0]}x{expected[1]}x{expected[2]}")
		out[name] = build.to_schematic()
	return out


def generate(root: pathlib.Path) -> list[pathlib.Path]:
	target = root / "games/luanti_web/mods/lw_world/schems"
	target.mkdir(parents=True, exist_ok=True)
	written = []
	for name, schem in schematics().items():
		path = target / f"{name}.mts"
		path.write_bytes(write_mts(schem))
		written.append(path)
	return written


def main() -> int:
	parser = argparse.ArgumentParser(description=__doc__,
		formatter_class=argparse.RawDescriptionHelpFormatter)
	parser.add_argument("--root", type=pathlib.Path,
		default=pathlib.Path(__file__).resolve().parents[2],
		help="repository root (default: inferred from this script)")
	parser.add_argument("--dump", metavar="NAME",
		help="print one map as a character map instead of writing files")
	args = parser.parse_args()

	if args.dump:
		built = schematics()
		if args.dump not in built:
			raise SystemExit("unknown map: " + ", ".join(sorted(built)))
		print(to_text(built[args.dump]))
		return 0

	written = generate(args.root)
	total = 0
	for path in written:
		size = path.stat().st_size
		total += size
		print("{} ({:.1f} KiB)".format(path.relative_to(args.root), size / 1024))
	print("{} maps, {:.1f} KiB, {} of {} nodes".format(len(written), total / 1024,
		pack_volume(), NODE_BUDGET))
	if pack_volume() > NODE_BUDGET:
		print("warning: the pack is over its node budget; "
			"test_luanti_web_maps.py will fail", file=sys.stderr)
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
