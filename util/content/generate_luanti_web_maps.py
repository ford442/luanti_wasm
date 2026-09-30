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

    [ smoke caldera ]                    [ crystal bazaar ]
    [ halloween ]------[ hub ]------[ fruit garden ]
                         |
    [ lighthouse ]  [ snow mountain ]

The diagonal three are reached by causeways that turn in the open water;
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


def wool(color: str) -> str:
	return "lw_nodes:wool_" + color


# Everything a player walks through rather than on. Used by the reachability
# check in test_luanti_web_maps.py, and kept here so it stays next to the node
# names it talks about — a new decorative node that is secretly solid would
# otherwise wall off a route and nothing would notice.
NON_WALKABLE = frozenset({
	AIR, WATER, COBWEB, TORCH, FIRE, VINE, HIDDEN_LIGHT, FLICKER, CHASE,
	JUICE_RED, JUICE_GREEN,
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
]

MAPS = {spec.name: spec.build for spec in SPECS}
SIZES = {spec.name: spec.size for spec in SPECS}
SPAWNS = {spec.name: spec.spawn for spec in SPECS}

# The pack's node budget, in schematic *volume*: lw_world/schems.lua loads a
# schematic into two Lua arrays with a slot for every cell, air included, and
# they stay in the WASM heap for the session. A sparse map is still cheaper to
# mesh and to diff, but it is not cheaper to hold, so the cap counts the box.
#
# The heap is what the cap protects, and test_luanti_web_maps.py measures it
# directly as well: Lua sizes an array part to a power of two, so a map keeps
# 1 MiB up to 32,768 cells and 2 MiB up to 65,536. That step, not the node
# count, is what makes a 36x24x36 map cheap and a 40x24x40 one twice the
# price. The numbers and the reasoning are in wasm_porting.md ("Content
# Budget") and games/luanti_web/docs/maps.md ("Budget").
NODE_BUDGET = 200_000
CHEAP_VOLUME = 32_768


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
