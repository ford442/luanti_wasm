#!/usr/bin/env python3
# Luanti
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 The Luanti Contributors
"""Checks for the authored themed maps (no engine required).

The interesting property of a hand-authored map is not that it exists, it is
that a visitor can *walk* it: the acceptance criteria on the map-pack issue
are a short loop on each map, a cave you enter on the snow map, a tunnel that
comes out somewhere else, and a watermelon you can stand inside. So the test
below flood-fills each schematic from its spawn under a player's movement
rules and asserts that every landmark is standable and connected.

    python3 util/content/test_luanti_web_maps.py
"""

from __future__ import annotations

import collections
import math
import pathlib
import re
import subprocess
import sys

SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
ROOT = SCRIPT_DIR.parents[1]
if str(SCRIPT_DIR) not in sys.path:
	sys.path.insert(0, str(SCRIPT_DIR))

from mts_to_text import node_index, read_mts, write_mts
import generate_luanti_web_maps as maps

GAME = ROOT / "games/luanti_web"
SCHEM_DIR = GAME / "mods/lw_world/schems"
LW_MAPS = GAME / "mods/lw_maps"

# How far a player falls in one step before the route counts as a drop rather
# than a path. Luanti has no fall damage in this game, but a 12-node plunge is
# not a route anyone would call "the way round".
MAX_FALL = 6


def assert_true(cond: bool, message: str) -> None:
	if not cond:
		raise SystemExit(message)


# --------------------------------------------------------------------------
# A player, reduced to the two rules that decide whether a map is walkable
# --------------------------------------------------------------------------

class World:
	def __init__(self, schem) -> None:
		self.sx, self.sy, self.sz = schem.size
		self.names = schem.names
		self.content = schem.content

	def at(self, x: int, y: int, z: int) -> str:
		if not (0 <= x < self.sx and 0 <= y < self.sy and 0 <= z < self.sz):
			return "air"
		return self.names[self.content[node_index(self.sx, self.sy, x, y, z)]]

	def solid(self, x: int, y: int, z: int) -> bool:
		if y < 0:
			return True
		return self.at(x, y, z) not in maps.NON_WALKABLE

	def standable(self, x: int, y: int, z: int) -> bool:
		"""Feet at y, standing on the node below, head and chest clear."""
		return (0 <= x < self.sx and 0 <= z < self.sz and 0 < y < self.sy
			and self.solid(x, y - 1, z)
			and not self.solid(x, y, z) and not self.solid(x, y + 1, z))

	def reachable(self, start) -> set:
		"""Every cell a walker can get to from `start`: step up one, fall some.

		A step up needs room to jump — the walker's own column clear one above
		their head — unless it is onto a stair or slab, which is half a node
		and walked up. Anything else is a walk across at the walker's own height,
		so the neighbouring column has to be clear there — body and head — and
		only then can they drop down it. Without that, a wall with a cave on
		the far side would count as a way into the cave.
		"""
		assert_true(self.standable(*start),
			f"spawn {start} is not somewhere a player can stand "
			f"(node {self.at(*start)!r}, floor {self.at(start[0], start[1] - 1, start[2])!r})")
		seen = {start}
		queue = collections.deque([start])
		while queue:
			x, y, z = queue.popleft()
			for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1)):
				nx, nz = x + dx, z + dz
				landing = None
				if self.standable(nx, y + 1, nz) and (not self.solid(x, y + 2, z)
						or self.at(nx, y, nz) in maps.HALF_HEIGHT):
					landing = (nx, y + 1, nz)
				elif not self.solid(nx, y, nz) and not self.solid(nx, y + 1, nz):
					for ny in range(y, y - MAX_FALL - 1, -1):
						if self.standable(nx, ny, nz):
							landing = (nx, ny, nz)
							break
						if self.solid(nx, ny - 1, nz):
							break
				if landing is not None and landing not in seen:
					seen.add(landing)
					queue.append(landing)
		return seen


# --------------------------------------------------------------------------
# What each map has to deliver, in its own local coordinates
# --------------------------------------------------------------------------

def halloween_landmarks() -> dict:
	return {
		"lane at the causeway": maps.HALLOWEEN_SPAWN,
		"pumpkin patch": (24, maps.FLOOR, 5),
		"graveyard": (9, maps.FLOOR, 26),
		"house hallway": (24, maps.HOUSE_FLOOR + 1, 27),
		"house attic": (25, maps.HOUSE_CEILING + 1, 27),
		"house cellar": (28, maps.CELLAR_FLOOR + 1, 24),
		"stage deck": (4, maps.FLOOR + 2, 6),
		"stage seating": (9, maps.FLOOR + 1, 8),
	}


def snow_landmarks(schem) -> dict:
	z0, z1 = maps.SHORTCUT_Z
	return {
		"trailhead": maps.SNOW_SPAWN,
		"summit overlook": (int(maps.PEAK[0]) + 2, maps.PEAK_TOP + 1, int(maps.PEAK[1])),
		"ice cave": (9, maps.ICE_CAVE["y"], 19),
		"west cave mouth": (1, maps.ICE_CAVE["y"], maps.ICE_CAVE["z0"] + 4),
		"mineshaft landing": (maps.SHORTCUT_X[1] + 2, maps.SHORTCUT_Y, maps.SHAFT_Z0),
		"mineshaft head": (maps.SHORTCUT_X[1] + 3, maps.SHAFT_TOP,
			maps.SHAFT_Z0 + 1 + maps.SHAFT_TOP - maps.SHORTCUT_Y),
		"tunnel south mouth": (19, maps.SHORTCUT_Y, z0),
		"tunnel north mouth": (19, maps.SHORTCUT_Y, z1),
	}


def fruit_landmarks() -> dict:
	cx, _, cz = maps.MELON
	bx, _, bz = maps.BOWL
	return {
		"path at the causeway": maps.FRUIT_SPAWN,
		"inside the watermelon": (cx, maps.FLOOR + 1, cz),
		"melon amphitheatre": (bx, maps.bowl_surface(0) + 1, bz),
		"under the grape canopy": (21, maps.FLOOR, 30),
		"juice channel": (16, maps.SURFACE, 8),
	}


def lighthouse_landmarks() -> dict:
	cx, cz = maps.TOWER
	t = maps.TIDE_TUNNEL
	mid_z = (t["z0"] + t["z1"]) // 2
	head = maps.JETTY_HEAD
	pool = maps.TIDE_POOLS[1]
	return {
		"shore at the causeway": maps.LIGHTHOUSE_SPAWN,
		"lighthouse door": (cx, maps.FLOOR, cz + 5),
		"foot of the stair": (cx, maps.FLOOR, cz + 3),
		"lantern room": (cx, maps.LANTERN_FLOOR + 1, cz - 2),
		"gallery": (cx, maps.LANTERN_FLOOR + 1, cz - 6),
		"jetty head": ((head["x0"] + head["x1"]) // 2, maps.JETTY_DECK + 1, head["z0"] + 1),
		"tide pool": (pool[0] + 1, maps.JETTY_DECK, pool[2] + 1),
		"tunnel, west mouth": (maps.TUNNEL_WEST_STAIR + 2, t["floor"] + 1, mid_z),
		"tunnel, under the jetty": ((maps.JETTY["x0"] + maps.JETTY["x1"]) // 2,
			t["floor"] + 1, mid_z),
		"tunnel, east mouth": (maps.TUNNEL_EAST_STAIR, t["floor"] + 1, mid_z),
		"east ledge": (maps.TUNNEL_EAST_STAIR + 3, maps.FLOOR, mid_z),
	}


def bazaar_landmarks() -> dict:
	cx, cz = maps.ROTUNDA
	c = maps.CISTERN
	aisle = (maps.AISLE_Z[0] + maps.AISLE_Z[1]) // 2
	return {
		"arcade at the causeway": maps.BAZAAR_SPAWN,
		"stall floor, west wing": (5, maps.FLOOR, maps.AISLE_Z[0]),
		"rotunda under the dome": (cx, maps.FLOOR, cz + 2),
		"far end of the arcade": (maps.BAZAAR_SIZE[0] - 1, maps.FLOOR, aisle),
		"north souk": (10, maps.FLOOR, 30),
		"south souk": (25, maps.FLOOR, 5),
		"rim terrace": (cx, maps.RIM + 1, cz + 7),
		"dome roof": (cx, maps.dome_height(0) + 1, cz),
		"cistern": (c["x0"] + 1, 1, c["z0"] + 1),
	}


def caldera_landmarks() -> dict:
	vx, vz = int(maps.VENT[0]), int(maps.VENT[1])
	z_mid = (maps.TUBE_Z[0] + maps.TUBE_Z[1]) // 2
	inner = int(maps.VENT[0] - maps.CRATER_RADIUS) + 1
	rim = int(maps.VENT[1] + (maps.RIM_INNER + maps.RIM_OUTER) / 2)
	return {
		"trailhead": maps.CALDERA_SPAWN,
		"rim, south": (vx, maps.RIM_TOP + 1, int(maps.VENT[1] - (maps.RIM_INNER + maps.RIM_OUTER) / 2)),
		"rim, north": (vx, maps.RIM_TOP + 1, rim),
		# Just behind the parapet at the lip's tip.
		"observation lip": (vx, maps.RIM_TOP + 1, int(maps.VENT[1] + maps.LIP_REACH + 1.5)),
		"crater floor": (vx, maps.CRATER_FLOOR + 1, int(maps.VENT[1] + maps.CRATER_RADIUS - 1)),
		"lava lake": (vx + 1, maps.CRATER_FLOOR + 1, vz),
		"tube, crater mouth": (inner, maps.CRATER_FLOOR + 1, z_mid),
		"tube, far face": (maps.TUBE_MOUTH_X, maps.FLOOR, z_mid),
	}


def rainbow_landmarks() -> dict:
	mid = (maps.DECK_Z0 + maps.DECK_Z1) // 2
	sx = maps.RAINBOW_SIZE[0]
	marks = {
		"west landing": maps.RAINBOW_SPAWN,
		"east landing": (sx - 1, maps.FLOOR, mid),
	}
	for index, (x, z) in enumerate(maps.RAINBOW_RODS):
		crest = maps.arch_height(x)
		marks[f"crest of arch {index + 1}"] = (x, crest, mid)
		# The deck cell beside the rod: where a visitor stands to watch it hit.
		beside = maps.DECK_Z0 if z < maps.DECK_Z0 else maps.DECK_Z1
		marks[f"base of rod {index + 1}"] = (x, crest, beside)
	return marks


def arena_landmarks() -> dict:
	s = maps.ARENA_STAGE
	mid_x = (s["x0"] + s["x1"]) // 2
	return {
		"causeway, under the marquee": maps.ARENA_SPAWN,
		"dance floor": (mid_x, maps.FLOOR, 9),
		"front of the stage": (mid_x, maps.FLOOR, s["z0"] - 1),
		"stage deck, where the band plays": (mid_x, maps.FLOOR + 1, s["z0"] + 1),
		"back of the stage, by the banners": (mid_x, maps.FLOOR + 1, s["z1"]),
		"stage, audience-left wing": (s["x0"], maps.FLOOR + 1, s["z1"] - 3),
		"stage, audience-right wing": (s["x1"], maps.FLOOR + 1, s["z1"] - 3),
		"under the west truss": (1, maps.FLOOR, 12),
		"under the east truss": (maps.TRUSS_EDGE - 1, maps.FLOOR, 12),
	}


# Every map in the pack, and what it has to deliver. A map the generator
# builds but this table does not name fails test_every_map_has_landmarks: the
# flood-fill is the acceptance test, so it is not optional for a new one.
LANDMARKS = {
	"map_halloween": lambda schem: halloween_landmarks(),
	"map_snow_mountain": snow_landmarks,
	"map_fruit_garden": lambda schem: fruit_landmarks(),
	"map_lighthouse_tide": lambda schem: lighthouse_landmarks(),
	"map_crystal_bazaar": lambda schem: bazaar_landmarks(),
	"map_smoke_caldera": lambda schem: caldera_landmarks(),
	"map_rainbow_storm": lambda schem: rainbow_landmarks(),
	"map_around_arena": lambda schem: arena_landmarks(),
}


def test_every_map_has_landmarks() -> None:
	for spec in maps.SPECS:
		assert_true(spec.name in LANDMARKS,
			f"{spec.name} has no landmarks in test_luanti_web_maps.py; say what a "
			"visitor has to be able to walk to")
	assert_true(set(LANDMARKS) <= {spec.name for spec in maps.SPECS},
		"LANDMARKS names a map the generator does not build")


def test_reachability() -> None:
	built = maps.schematics()
	for spec in maps.SPECS:
		name = spec.name
		landmarks = LANDMARKS[name](built[name])
		world = World(built[name])
		seen = world.reachable(spec.spawn)
		for label, cell in landmarks.items():
			assert_true(cell in seen,
				f"{name}: cannot walk from the spawn to the {label} at {cell} "
				f"(node {world.at(*cell)!r}, floor "
				f"{world.at(cell[0], cell[1] - 1, cell[2])!r})")


def test_snow_goes_through_the_mountain() -> None:
	"""The shortcut has to come out on the *far* face, not double back."""
	z0, z1 = maps.SHORTCUT_Z
	assert_true(z1 - z0 > maps.SNOW_SIZE[2] * 0.7,
		"the through-mountain tunnel does not span the mountain")
	assert_true(z0 < maps.PEAK[1] < z1,
		"the tunnel does not pass under the peak, so it is not a shortcut")
	world = World(maps.schematics()["map_snow_mountain"])
	# Just outside each portal the sky has to be open, or the "mouth" is a
	# pocket inside the mountain rather than a way out of it.
	for z in (z0 - 2, z1 + 2):
		column = [world.solid(19, y, z)
			for y in range(maps.SHORTCUT_Y, maps.SNOW_SIZE[1])]
		assert_true(not any(column), f"the tunnel mouth beside z={z} is buried")


def test_watermelon_is_walk_in() -> None:
	world = World(maps.schematics()["map_fruit_garden"])
	cx, cy, cz = maps.MELON
	inside = world.reachable((cx, maps.FLOOR + 1, cz))
	room = {cell for cell in inside
		if abs(cell[0] - cx) <= 3 and abs(cell[2] - cz) <= 3}
	assert_true(len(room) >= 25,
		f"the watermelon interior is only {len(room)} cells; it has to be a room")
	# And it still has to look like a watermelon from outside: rind, stripes,
	# flesh and seeds all present on the same object.
	shell = collections.Counter(
		world.at(x, y, z)
		for x in range(cx - maps.MELON_RADIUS, cx + maps.MELON_RADIUS + 1)
		for y in range(maps.FLOOR, cy + maps.MELON_RADIUS + 1)
		for z in range(cz - maps.MELON_RADIUS, cz + maps.MELON_RADIUS + 1))
	for part in ("dark_green", "green", "red", "black"):
		assert_true(shell["lw_nodes:wool_" + part] > 0,
			f"the watermelon has no {part} nodes")


def test_lighthouse_tunnel_is_under_water() -> None:
	"""The tunnel is the lagoon's floor, not a corridor beside it.

	Under open water every wall and roof node is glass with water on its far
	side, and the pool on the jetty is water on the same glass the tunnel has
	for a roof — so from inside you look up into the pool, and from the jetty
	down through it into the tunnel.
	"""
	world = World(maps.schematics()["map_lighthouse_tide"])
	t = maps.TIDE_TUNNEL
	top = maps.TIDE_TOP
	submerged = 0
	for x in range(t["x0"], t["x1"] + 1):
		if world.at(x, top, t["z0"] - 2) != maps.WATER:
			continue
		submerged += 1
		for y in range(t["floor"] + 1, top + 1):
			for z in (t["z0"] - 1, t["z1"] + 1):
				assert_true(world.at(x, y, z) == maps.GLASS,
					f"tunnel wall ({x},{y},{z}) under the lagoon is {world.at(x, y, z)}")
		for z in range(t["z0"], t["z1"] + 1):
			assert_true(world.at(x, top, z) == maps.GLASS,
				f"tunnel roof ({x},{top},{z}) under the lagoon is {world.at(x, top, z)}")
			# Head height is below the lagoon's surface: this is under water.
			assert_true(t["floor"] + 2 < top + 1,
				"the tunnel's head room is above the waterline")
	assert_true(submerged >= 10,
		f"only {submerged} columns of the tunnel are under the lagoon")
	x0, x1, z0, z1 = maps.TIDE_POOLS[0]
	for x in range(x0, x1 + 1):
		for z in range(z0, z1 + 1):
			assert_true(world.at(x, maps.JETTY_DECK, z) == maps.WATER,
				f"the tide pool over the tunnel is dry at ({x}, {z})")
			assert_true(world.at(x, maps.JETTY_DECK - 1, z) == maps.GLASS,
				f"the tide pool over the tunnel has no glass floor at ({x}, {z})")
			assert_true(z0 < t["z0"] or z > t["z1"]
				or world.at(x, t["floor"] + 2, z) == maps.AIR,
				f"the pool's glass is not the tunnel's roof at ({x}, {z})")


def test_rainbow_arches_are_a_walk_under_open_sky() -> None:
	"""Seven bands the whole way, no step sooner than four, and sky above."""
	world = World(maps.schematics()["map_rainbow_storm"])
	bands = [maps.wool(color) for color in maps.RAINBOW_BANDS]
	heights = [maps.arch_height(x) for x in range(world.sx)]
	assert_true(heights[0] == maps.FLOOR and heights[-1] == maps.FLOOR,
		"the rainbow's landings are not level with the causeway")
	assert_true(max(heights) == maps.FLOOR + maps.ARCH_RISE,
		f"the arches crest at {max(heights)}, not FLOOR + {maps.ARCH_RISE}")
	last_step = None
	for x, h in enumerate(heights):
		for z, band in zip(range(maps.DECK_Z0, maps.DECK_Z1 + 1), bands):
			assert_true(world.at(x, h - 1, z) == band,
				f"rainbow deck at ({x}, {h - 1}, {z}) is {world.at(x, h - 1, z)!r}, "
				f"not {band}")
			for y in range(h, world.sy):
				assert_true(world.at(x, y, z) == "air",
					f"something stands on the rainbow deck at ({x}, {y}, {z}); "
					"the storm is the sky, not a ceiling")
		if x > 0 and h != heights[x - 1]:
			assert_true(abs(h - heights[x - 1]) == 1,
				f"the rainbow climbs {h - heights[x - 1]} at x {x}")
			assert_true(last_step is None or x - last_step >= maps.ARCH_RUN,
				f"the rainbow steps at x {last_step} and again at x {x}")
			last_step = x
	for x, z in maps.RAINBOW_RODS:
		crest = maps.arch_height(x)
		assert_true(heights[x] == crest == maps.FLOOR + maps.ARCH_RISE,
			f"the rod at x {x} is not on a crest")
		assert_true(world.solid(x, crest, z) and not world.solid(x, crest + 1, z)
			if crest + 1 < world.sy else world.solid(x, crest, z),
			f"the rod at ({x}, {crest}, {z}) is not one node proud of the crest")
		assert_true(not (maps.DECK_Z0 <= z <= maps.DECK_Z1),
			f"the rod at ({x}, {z}) stands on the deck")


def test_lighthouse_stair_climbs_every_turn() -> None:
	"""The spiral goes all the way up: no turn is a jump, none is a ceiling."""
	world = World(maps.schematics()["map_lighthouse_tide"])
	seen = world.reachable(maps.LIGHTHOUSE_SPAWN)
	cx, cz = maps.TOWER
	inside = {cell for cell in seen
		if maps.tower_radius(cell[0], cell[2]) <= maps.TOWER_RADIUS - maps.TOWER_WALL}
	heights = {cell[1] for cell in inside}
	missing = [y for y in range(maps.FLOOR, maps.LANTERN_FLOOR + 1) if y not in heights]
	assert_true(not missing,
		f"the lighthouse stair has no standable tread at heights {missing}")


def test_bazaar_lanterns_chase_round_the_arcade() -> None:
	"""Every chase controller has a lantern under it, and the loop is whole.

	A controller over anything but a registered lamp does nothing, and a loop
	with a missing index has a dark gap that travels round it.
	"""
	schem = maps.schematics()["map_crystal_bazaar"]
	world = World(schem)
	chase = schem.names.index(maps.CHASE)
	indices = []
	for i, content in enumerate(schem.content):
		if content != chase:
			continue
		sx, sy = schem.size[0], schem.size[1]
		x, y, z = i % sx, (i // sx) % sy, i // (sx * sy)
		below = world.at(x, y - 1, z)
		assert_true(below in (maps.LANTERN, maps.LANTERN_OFF),
			f"the chase controller at {(x, y, z)} is over {below}, not a lantern")
		indices.append(schem.param2[i])
	period = 8
	assert_true(len(indices) >= period,
		f"only {len(indices)} lanterns chase; a loop needs at least {period}")
	assert_true(set(indices) == set(range(period)),
		f"the chase loop's places are {sorted(set(indices))}, not 0..{period - 1}")
	# Stall posts carry the lanterns; none stands in the aisle.
	aisle = range(maps.AISLE_Z[0], maps.AISLE_Z[1] + 1)
	for x, z in maps.build_stalls(maps.Build(*maps.BAZAAR_SIZE)):
		assert_true(z not in aisle, f"a stall post at ({x}, {z}) is in the aisle")


def test_bazaar_dome_is_walkable() -> None:
	"""No step up the dome is more than a node: it is walked, not climbed."""
	cx, cz = maps.ROTUNDA
	for x in range(cx - 8, cx + 9):
		for z in range(cz - 8, cz + 9):
			here = maps.dome_height(maps.rotunda_radius(x, z))
			for dx, dz in ((1, 0), (0, 1)):
				there = maps.dome_height(maps.rotunda_radius(x + dx, z + dz))
				assert_true(abs(here - there) <= 1,
					f"the dome steps {abs(here - there)} nodes between "
					f"({x}, {z}) and ({x + dx}, {z + dz})")


def test_caldera_is_a_shell() -> None:
	"""The cone is hollow — the snow mountain already spent the filled-cone
	budget — and sealed, so nothing a visitor can reach looks into the hollow.

	A shell here means no rock more than two nodes from open space, and a
	hollow that open air cannot get into.
	"""
	world = World(maps.schematics()["map_smoke_caldera"])
	mass = {maps.BASALT, maps.STONE}
	cone = [(x, y, z) for x in range(world.sx) for z in range(world.sz)
		for y in range(maps.FLOOR, maps.caldera_height(x, z) + 1)]

	# Open space: air (or anything else not rock) the sky can reach.
	outside = set()
	queue = collections.deque()
	for x in range(world.sx):
		for z in range(world.sz):
			cell = (x, world.sy - 1, z)
			outside.add(cell)
			queue.append(cell)
	while queue:
		x, y, z = queue.popleft()
		for dx, dy, dz in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)):
			n = (x + dx, y + dy, z + dz)
			if n in outside or not (0 <= n[0] < world.sx and maps.FLOOR <= n[1] < world.sy
					and 0 <= n[2] < world.sz):
				continue
			if world.at(*n) in mass:
				continue
			outside.add(n)
			queue.append(n)

	hollow = [cell for cell in cone if world.at(*cell) not in mass
		and cell not in outside]
	rock = [cell for cell in cone if world.at(*cell) in mass]
	assert_true(len(hollow) > len(rock) // 2,
		f"the caldera's cone has {len(rock)} rock nodes and only {len(hollow)} "
		"hollow ones; it is supposed to be a shell")
	# Every rock node is within two of open space or of the hollow's edge: the
	# walls are two thick, not solid.
	near = {}
	queue = collections.deque()
	for cell in cone:
		if world.at(*cell) not in mass:
			near[cell] = 0
			queue.append(cell)
	for x in range(world.sx):
		for z in range(world.sz):
			cell = (x, maps.caldera_height(x, z) + 1, z)
			near.setdefault(cell, 0)
			queue.append(cell)
	while queue:
		x, y, z = queue.popleft()
		if near[(x, y, z)] >= 2:
			continue
		for dx, dy, dz in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)):
			n = (x + dx, y + dy, z + dz)
			if n not in near:
				near[n] = near[(x, y, z)] + 1
				queue.append(n)
	deep = [cell for cell in rock if cell not in near]
	assert_true(not deep, f"{len(deep)} nodes of the caldera's rock are more than "
		f"two from any face, e.g. {deep[:3]}; the cone is filled there")
	# Sealed: a visitor never stands in, or puts their head into, the hollow.
	for x, y, z in world.reachable(maps.CALDERA_SPAWN):
		for cell in ((x, y, z), (x, y + 1, z)):
			assert_true(cell not in hollow,
				f"a visitor at {(x, y, z)} can see into the caldera's hollow")


def test_caldera_goes_through_and_round() -> None:
	"""Up and through, like the snow mountain: the tube comes out on the far
	face from the trailhead, and the rim can be walked all the way round."""
	world = World(maps.schematics()["map_smoke_caldera"])
	z_mid = (maps.TUBE_Z[0] + maps.TUBE_Z[1]) // 2
	assert_true(maps.TUBE_MOUTH_X < maps.VENT[0] < maps.CALDERA_SPAWN[0],
		"the tube does not come out on the far side from the trailhead")
	column = [world.solid(maps.TUBE_MOUTH_X - 1 + 1, y, z_mid)
		for y in range(maps.FLOOR, maps.FLOOR + 2)]
	assert_true(not any(column), "the tube's far mouth is blocked")
	seen = world.reachable(maps.CALDERA_SPAWN)
	bins = {int(maps.vent_angle(x, z) / (2 * math.pi) * 36)
		for (x, y, z) in seen if y == maps.RIM_TOP + 1
		and maps.RIM_INNER < maps.vent_radius(x, z) <= maps.RIM_OUTER + 0.5}
	missing = sorted(set(range(36)) - bins)
	assert_true(not missing,
		f"the rim walkway is broken at bearings {[b * 10 for b in missing]} degrees")
	# The lip is glass over open crater: look down from it and there is air.
	vx = int(maps.VENT[0])
	lip_z = int(maps.VENT[1] + maps.LIP_REACH + 1.5)
	assert_true(world.at(vx, maps.RIM_TOP, lip_z) == maps.GLASS,
		"the observation lip is not glass")
	assert_true(world.at(vx, maps.RIM_TOP - 1, lip_z) == maps.AIR,
		"the observation lip is not out over the crater")


def test_arena_truss_lights_race_round_it() -> None:
	"""32 truss lights in loop order, a whole number of chase periods, so the
	lit pair laps the arena with no seam — the way the emitters race."""
	schem = maps.schematics()["map_around_arena"]
	world = World(schem)
	sx, sy = schem.size[0], schem.size[1]
	chase = schem.names.index(maps.CHASE)
	controllers = {}
	for i, content in enumerate(schem.content):
		if content == chase:
			controllers[(i % sx, (i // sx) % sy, i // (sx * sy))] = schem.param2[i]
	ring = maps.truss_ring()
	assert_true(len(ring) == 96 and len(set(ring)) == 96,
		f"the truss is {len(ring)} cells round, not 96")
	lights = [cell for index, cell in enumerate(ring)
		if index % maps.TRUSS_LIGHT_SPACING == 0]
	assert_true(len(lights) % 8 == 0,
		f"{len(lights)} truss lights do not divide into chase periods of 8")
	assert_true(len(controllers) == len(lights),
		f"{len(controllers)} chase controllers for {len(lights)} truss lights")
	for place, (x, z) in enumerate(lights):
		key = (x, maps.TRUSS_Y + 1, z)
		assert_true(controllers.get(key) == place % 8,
			f"the truss light at {(x, z)} is place {controllers.get(key)} in the chase, "
			f"not {place % 8}")
		assert_true(world.at(x, maps.TRUSS_Y, z) == maps.STAGE_LIGHT_OFF,
			f"the chase controller at {key} is over {world.at(x, maps.TRUSS_Y, z)}")
	for x, z in ring:
		assert_true(world.solid(x, maps.TRUSS_Y, z), f"the truss has a gap at {(x, z)}")


def test_arena_stage_hosts_the_band() -> None:
	"""The cabs are where lw_maps points the amps, and the band and crowd
	lw_dance builds from them have somewhere to stand.

	lw_dance.stage_from_amps puts the band one node behind the middle of the
	line between the sources, at the cabs' own height, and `settle`s the
	crowd onto the floor five and seven nodes in front of that.
	"""
	world = World(maps.schematics()["map_around_arena"])
	harness = run_lua_harness()
	sources = harness["amps"]["around_arena"] if harness else tuple(
		(x, maps.FLOOR + 2, z) for x, z in maps.ARENA_CABS)
	left, right = sources
	schem = maps.schematics()["map_around_arena"]
	for source in sources:
		x, y, z = source
		cab = world.at(x, y - 1, z)
		assert_true(cab == maps.AMP_CAB, f"no amp cab under the sound source {source}: {cab}")
		index = node_index(world.sx, world.sy, x, y - 1, z)
		assert_true(schem.param2[index] == maps.NORTH,
			f"the cab at {(x, y - 1, z)} does not face the floor")
		assert_true(not world.solid(*source), f"the sound source {source} is inside a node")
	assert_true(left[0] < right[0] and left[2] == right[2],
		"the left source is not on the audience's left of a stage facing south")
	assert_true(abs(right[0] - left[0]) >= 6,
		"the cabs are too close together for the stereo to survive")
	# Facing south, `forward` is -z, so the band is one node north of the line.
	band_z = left[2] + 1
	band_y = left[1] - 1
	mid = (left[0] + right[0]) // 2
	for dx in (-2, -1, 0, 1, 2):
		assert_true(world.standable(mid + dx, band_y, band_z),
			f"the band has nowhere to stand at {(mid + dx, band_y, band_z)}")
	for back in (5, 7):
		for dx in range(-5, 6):
			cell = (mid + dx, maps.FLOOR, band_z - back)
			assert_true(world.standable(*cell), f"the crowd has nowhere to stand at {cell}")


def test_arena_banners_are_whole_and_face_the_floor() -> None:
	world = World(maps.schematics()["map_around_arena"])
	schem = maps.schematics()["map_around_arena"]
	# The cell in front of a banner's art, per facedir: the art looks the
	# opposite way to core.facedir_to_dir.
	front = {maps.NORTH: (0, -1), maps.EAST: (-1, 0), maps.WEST: (1, 0)}
	expected = {maps.AROUND_SIGN: 2, maps.LACE_BANNER: 7,
		maps.PORTRAIT_RUBELLA: 1, maps.PORTRAIT_LILLITH: 1}
	for (name, cols, rows), placed in expected.items():
		for index in range(1, cols * rows + 1):
			node = f"{name}_{index}"
			cells = [i for i, c in enumerate(schem.content) if schem.names[c] == node] \
				if node in schem.names else []
			assert_true(len(cells) == placed,
				f"{node} is placed {len(cells)} times, expected {placed}")
			for i in cells:
				x, y, z = i % world.sx, (i // world.sx) % world.sy, i // (world.sx * world.sy)
				dx, dz = front[schem.param2[i]]
				ahead = (x + dx, y, z + dz)
				assert_true(not world.solid(*ahead),
					f"{node} at {(x, y, z)} faces into {world.at(*ahead)}")


def test_arena_lasers_ride_the_truss() -> None:
	"""lw_maps' laser track is the generator's truss, and the emitters ride
	clear of anything on top of it."""
	harness = run_lua_harness()
	if harness is None:
		return
	x0, z0, x1, z1, y = harness["tracks"]["around_arena"]
	assert_true((x0, z0, x1, z1) == (0, 0, maps.TRUSS_EDGE, maps.TRUSS_EDGE),
		f"the laser track {(x0, z0, x1, z1)} is not the truss round the edge")
	assert_true(y == maps.TRUSS_Y, f"the lasers ride at y {y}, the truss is at {maps.TRUSS_Y}")
	world = World(maps.schematics()["map_around_arena"])
	for x, z in maps.truss_ring():
		assert_true(not world.solid(x, y + 1, z),
			f"an emitter would ride through {world.at(x, y + 1, z)} at {(x, y + 1, z)}")


def test_committed_files_match_the_generator() -> None:
	"""A regenerated tree must be an empty diff, like every other asset here."""
	built = maps.schematics()
	for name, schem in built.items():
		path = SCHEM_DIR / f"{name}.mts"
		assert_true(path.exists(),
			f"{path} is missing; run util/content/generate_luanti_web_maps.py")
		assert_true(path.read_bytes() == write_mts(schem),
			f"{path.name} is stale; run util/content/generate_luanti_web_maps.py")
		again = read_mts(path.read_bytes())
		assert_true(again.size == schem.size, f"{name} roundtrip changed size")
		assert_true(again.content == schem.content, f"{name} roundtrip changed content")
		assert_true(again.param2 == schem.param2, f"{name} roundtrip changed param2")


def test_every_node_is_registered() -> None:
	"""No map may name a node nothing defines: that is a hole in the world.

	The registered names come from actually loading the mods under the Lua
	harness, because half of them are built by concatenation
	(``register_stair_and_slab``, the wool loop, the screen cells) and reading
	them out of the source would miss exactly those.
	"""
	harness = run_lua_harness()
	if harness is None:
		print("  (no Lua interpreter; skipped the node-registration check)")
		return
	registered = harness["nodes"]
	for name, schem in maps.schematics().items():
		for node in schem.names:
			if node == "air":
				continue
			assert_true(node in registered,
				f"{name} places {node}, which no mod in {GAME.name} registers")


# Singlenode demos that stay their own games. See maps.md, "Not in this pack".
OTHER_GAMES = ("rollercoaster", "log_ride", "spire_tunnel", "flower_island")
# Ride-system nodes. A decorative name that merely contains "cart" is fine;
# these are the track, flume, and boat pieces those games are built from.
RIDE_NODES = (
	"track_straight", "track_curve", "track_ramp", "track_support",
	"track_ornament", "flume_floor", "flume_wall", "flume_straight",
	"flume_curve", "flume_ramp", "channel_water", "log_boat",
)


def test_other_games_stay_out_of_the_pack() -> None:
	"""Park rides and the other singlenode demos stay out of the plaza pack."""
	def refuse(label: str, node: str) -> None:
		for game in OTHER_GAMES:
			assert_true(not node.startswith(game + ":"),
				f"{label} places {node}")
		for ride in RIDE_NODES:
			assert_true(ride not in node, f"{label} places ride node {node}")

	for path in SCHEM_DIR.glob("*.mts"):
		for game in OTHER_GAMES:
			assert_true(game not in path.name,
				f"{path.name} belongs to {game}; that game stays out of lw_world")
		for node in read_mts(path.read_bytes()).names:
			refuse(path.name, node)
	for name, schem in maps.schematics().items():
		for game in OTHER_GAMES:
			assert_true(game not in name,
				f"{name} is generated as a plaza map")
		for node in schem.names:
			refuse(name, node)
	for spec in maps.SPECS:
		for game in OTHER_GAMES:
			assert_true(game not in spec.name and game not in spec.id,
				f"{spec.name} is registered as a plaza map")
	registered = set(re.findall(r'register\(\s*"([^"]+)"',
		(LW_MAPS / "init.lua").read_text(encoding="utf-8")))
	for ride in RIDE_NODES:
		assert_true(ride not in registered, f"lw_maps registers {ride}")
	for game in OTHER_GAMES:
		assert_true(game not in registered,
			f"lw_maps registers a node from {game}")


def test_param2_survives() -> None:
	"""Seats are the reason schematic_from_cells learned about param2."""
	for name, schem in maps.schematics().items():
		if "lw_theater:seat" not in schem.names:
			continue
		seat = schem.names.index("lw_theater:seat")
		facings = {schem.param2[i]
			for i, content in enumerate(schem.content) if content == seat}
		assert_true(facings and facings != {0},
			f"{name} saved its seats at facedir 0; they would face the wrong way")


# What the pack may cost the Lua heap for the session, measured by running
# lw_world's loader under Lua 5.1 (measure_luanti_web_maps_heap.lua), and the
# high-water mark while the largest map loads. See wasm_porting.md.
HEAP_BUDGET_KIB = 8 * 1024
LOAD_PEAK_BUDGET_KIB = 16 * 1024


def measure_heap():
	"""Returns ({map: (volume, kept KiB, peak KiB)}, kept, peak), or None."""
	import tempfile
	with tempfile.TemporaryDirectory() as tmp:
		dumps = []
		for name, schem in maps.schematics().items():
			path = pathlib.Path(tmp) / f"{name}.dump"
			with path.open("w", encoding="utf-8") as out:
				out.write("%d %d %d\n" % schem.size)
				out.write(" ".join(schem.names) + "\n")
				out.write("\n".join(f"{c} {p}" for c, p in
					zip(schem.content, schem.param2)) + "\n")
			dumps.append(str(path))
		script = SCRIPT_DIR / "measure_luanti_web_maps_heap.lua"
		for binary in ("lua5.1", "lua", "luajit"):
			try:
				result = subprocess.run([binary, str(script), *dumps], cwd=str(ROOT),
					check=False, capture_output=True, text=True)
			except FileNotFoundError:
				continue
			if result.returncode != 0:
				raise SystemExit(result.stdout + result.stderr)
			per_map, kept, peak = {}, None, None
			for line in result.stdout.splitlines():
				fields = line.split()
				if fields[0] == "MAP":
					per_map[fields[1]] = (int(fields[2]), float(fields[3]), float(fields[4]))
				elif fields[0] == "TOTAL":
					kept, peak = float(fields[1]), float(fields[2])
			return per_map, kept, peak
	return None


def test_budget() -> None:
	"""The pack is content, and content is charged against luanti.data."""
	total = sum(path.stat().st_size for path in SCHEM_DIR.glob("map_*.mts"))
	assert_true(total < 64 * 1024,
		f"the map schematics are {total / 1024:.1f} KiB; budget is 64 KiB")
	textures = sorted((LW_MAPS / "textures").glob("*.png"))
	assert_true(len(textures) == 15,
		f"lw_maps ships {len(textures)} textures, expected 15")
	art = sum(path.stat().st_size for path in textures)
	assert_true(art < 16 * 1024,
		f"lw_maps textures are {art / 1024:.1f} KiB; budget is 16 KiB")

	nodes = maps.pack_volume()
	print(f"  pack: {len(maps.SPECS)} maps, {nodes} nodes of {maps.NODE_BUDGET}, "
		f"{total / 1024:.1f} KiB on disk")
	# Each authored node costs two Lua table slots when lw_world loads the
	# schematic, and that lives in the WASM heap for the whole session.
	assert_true(nodes <= maps.NODE_BUDGET,
		f"the maps are {nodes} nodes; the documented budget is {maps.NODE_BUDGET}")
	# Past 32,768 cells a map's arrays double to the next power of two, so it
	# costs what two small maps do. The snow mountain is the pack's one dense
	# map; the next one has to fit or say why in wasm_porting.md.
	dense = [spec.name for spec in maps.SPECS if spec.volume > maps.CHEAP_VOLUME]
	assert_true(len(dense) <= 1,
		f"{dense} are all over {maps.CHEAP_VOLUME} nodes; only one map may be, "
		"because each one costs the heap twice what a smaller map does")

	heap = measure_heap()
	if heap is None:
		print("  (no Lua interpreter; skipped the heap measurement)")
		return
	per_map, kept, peak = heap
	for name, (volume, map_kept, map_peak) in per_map.items():
		print(f"  {name}: {volume} nodes, keeps {map_kept / 1024:.1f} MiB, "
			f"peaks at {map_peak / 1024:.1f} MiB while loading")
	print(f"  heap: keeps {kept / 1024:.1f} MiB of {HEAP_BUDGET_KIB / 1024:.0f}, "
		f"load peak {peak / 1024:.1f} MiB of {LOAD_PEAK_BUDGET_KIB / 1024:.0f}")
	assert_true(kept <= HEAP_BUDGET_KIB,
		f"the loaded maps keep {kept / 1024:.1f} MiB of Lua heap; the budget is "
		f"{HEAP_BUDGET_KIB / 1024:.0f} MiB (see wasm_porting.md)")
	assert_true(peak <= LOAD_PEAK_BUDGET_KIB,
		f"loading one map peaks at {peak / 1024:.1f} MiB of Lua heap; the budget is "
		f"{LOAD_PEAK_BUDGET_KIB / 1024:.0f} MiB (see wasm_porting.md)")


BASE_Y = 5


def test_registry_agrees_with_the_schematics() -> None:
	"""lw_maps' footprints and spawns are the generator's, restated in Lua.

	The two halves cannot import each other, so this is what stops them
	drifting: move a spawn in Python and forget the registry, and a visitor
	arrives in the moat with the map behind them.
	"""
	source = (LW_MAPS / "init.lua").read_text(encoding="utf-8")
	assert_true(f"lw_maps.base_y = {BASE_Y}" in source,
		f"lw_maps.base_y is not {BASE_Y}, so local y {maps.SURFACE} is no "
		"longer the world's GROUND")
	for spec in maps.SPECS:
		name, key = spec.name, spec.id
		sx, sy, sz = spec.size
		block = source.split(f'id = "{key}"', 1)
		assert_true(len(block) == 2, f"lw_maps does not register {key}")
		block = block[1].split("\n})", 1)[0]
		assert_true('schem = ' not in block or f'schem = "{name}"' in block,
			f"lw_maps' {key} does not point at {name}")
		assert_true("size = {x = %d, y = %d, z = %d}" % (sx, sy, sz) in block,
			f"lw_maps has no {sx}x{sy}x{sz} footprint for {key}")
		origin = re.search(r"origin = \{x = (-?\d+), y = BASE, z = (-?\d+)\}", block)
		spawn = re.search(r"spawn = \{x = (-?\d+), y = BASE \+ (\d+), z = (-?\d+)\}",
			block)
		assert_true(origin is not None and spawn is not None,
			f"lw_maps' {key} has no origin/spawn in the expected shape")
		local = spec.spawn
		want = (int(origin.group(1)) + local[0], BASE_Y + local[1],
			int(origin.group(2)) + local[2])
		got = (int(spawn.group(1)), BASE_Y + int(spawn.group(2)),
			int(spawn.group(3)))
		assert_true(want == got,
			f"lw_maps sends visitors to {got} on {key}, but the schematic's "
			f"spawn {local} at that origin is {want}")
	harness = run_lua_harness()
	if harness is not None:
		registered = harness["maps"]
		built = [spec.id for spec in maps.SPECS]
		assert_true(registered == built,
			f"lw_maps registers {registered} but the generator builds {built}; "
			"keep them in the same order so /maps lists them as the docs do")


def test_entities_have_room() -> None:
	"""A moving prop sits in air, on something: the vane on its mast."""
	harness = run_lua_harness()
	if harness is None:
		return
	built = maps.schematics()
	for map_id, entity, (x, y, z) in harness["entities"]:
		world = World(built["map_" + map_id])
		assert_true(0 <= x < world.sx and 0 <= y < world.sy and 0 <= z < world.sz,
			f"{map_id}: {entity} at {(x, y, z)} is outside the map")
		assert_true(not world.solid(x, y, z),
			f"{map_id}: {entity} at {(x, y, z)} is inside {world.at(x, y, z)}")
		assert_true(world.solid(x, y - 1, z),
			f"{map_id}: {entity} at {(x, y, z)} floats; the schematic has nothing "
			"under it")


_HARNESS: list = []


def run_lua_harness():
	"""Run the headless lw_maps harness once; return what it reported.

	A dict with the ``nodes`` it registered, the map ids in registry order
	(``maps``) and the moving props (``entities``). Returns None when no Lua
	interpreter is installed, which is how the checks that depend on it degrade
	instead of failing on a bare container.
	"""
	if _HARNESS:
		return _HARNESS[0]
	script = SCRIPT_DIR / "test_luanti_web_maps.lua"
	for binary in ("lua5.1", "lua", "luajit"):
		try:
			result = subprocess.run([binary, str(script)], cwd=str(ROOT),
				check=False, capture_output=True, text=True)
		except FileNotFoundError:
			continue
		if result.returncode != 0:
			raise SystemExit(result.stdout + result.stderr)
		report = {"nodes": set(), "maps": [], "entities": [], "amps": {}, "tracks": {}}
		for line in result.stdout.splitlines():
			fields = line.split()
			if not fields:
				continue
			if fields[0] == "NODE":
				report["nodes"].add(fields[1])
			elif fields[0] == "MAP":
				report["maps"].append(fields[1])
			elif fields[0] == "AMPS":
				values = [int(v) for v in fields[2:8]]
				report["amps"][fields[1]] = (tuple(values[:3]), tuple(values[3:]))
			elif fields[0] == "TRACK":
				report["tracks"][fields[1]] = tuple(int(v) for v in fields[2:7])
			elif fields[0] == "ENTITY":
				report["entities"].append((fields[1], fields[2],
					tuple(int(v) for v in fields[3:6])))
		assert_true(bool(report["nodes"]), "the Lua harness registered no nodes at all")
		_HARNESS.append(report)
		return report
	_HARNESS.append(None)
	return None


def test_lua_logic() -> None:
	"""The headless lw_maps harness: registry, atmosphere, lamps, /maps, atlas."""
	if run_lua_harness() is None:
		print("  (no Lua interpreter; skipped test_luanti_web_maps.lua)")


def main() -> int:
	for name, test in sorted(globals().items()):
		if name.startswith("test_") and callable(test):
			test()
			print("ok", name)
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
