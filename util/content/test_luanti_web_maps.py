#!/usr/bin/env python3
# Luanti
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 The Luanti Contributors
"""Checks for the three authored themed maps (no engine required).

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
		"""Every cell a walker can get to from `start`: step up one, fall some."""
		assert_true(self.standable(*start),
			f"spawn {start} is not somewhere a player can stand "
			f"(node {self.at(*start)!r}, floor {self.at(start[0], start[1] - 1, start[2])!r})")
		seen = {start}
		queue = collections.deque([start])
		while queue:
			x, y, z = queue.popleft()
			for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1)):
				nx, nz = x + dx, z + dz
				for ny in [y + 1] + list(range(y, y - MAX_FALL - 1, -1)):
					if not self.standable(nx, ny, nz):
						continue
					if (nx, ny, nz) not in seen:
						seen.add((nx, ny, nz))
						queue.append((nx, ny, nz))
					break
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


def test_reachability() -> None:
	built = maps.schematics()
	cases = {
		"map_halloween": (maps.HALLOWEEN_SPAWN, halloween_landmarks()),
		"map_snow_mountain": (maps.SNOW_SPAWN, snow_landmarks(built["map_snow_mountain"])),
		"map_fruit_garden": (maps.FRUIT_SPAWN, fruit_landmarks()),
	}
	for name, (spawn, landmarks) in cases.items():
		world = World(built[name])
		seen = world.reachable(spawn)
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
	registered = run_lua_harness()
	if registered is None:
		print("  (no Lua interpreter; skipped the node-registration check)")
		return
	for name, schem in maps.schematics().items():
		for node in schem.names:
			if node == "air":
				continue
			assert_true(node in registered,
				f"{name} places {node}, which no mod in {GAME.name} registers")


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


def test_budget() -> None:
	"""The pack is content, and content is charged against luanti.data."""
	total = sum(path.stat().st_size for path in SCHEM_DIR.glob("map_*.mts"))
	assert_true(total < 64 * 1024,
		f"the three map schematics are {total / 1024:.1f} KiB; budget is 64 KiB")
	textures = sorted((LW_MAPS / "textures").glob("*.png"))
	assert_true(len(textures) == 10,
		f"lw_maps ships {len(textures)} textures, expected 10")
	art = sum(path.stat().st_size for path in textures)
	assert_true(art < 16 * 1024,
		f"lw_maps textures are {art / 1024:.1f} KiB; budget is 16 KiB")
	nodes = sum(size[0] * size[1] * size[2] for size in maps.SIZES.values())
	# Each authored node costs two Lua table slots when lw_world loads the
	# schematic, and that lives in the WASM heap for the whole session.
	assert_true(nodes < 120_000,
		f"the three maps are {nodes} nodes; the documented budget is 120k")


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
	for name, (sx, sy, sz) in maps.SIZES.items():
		key = name[len("map_"):]
		block = source.split(f'id = "{key}"', 1)
		assert_true(len(block) == 2, f"lw_maps does not register {key}")
		block = block[1].split("})", 1)[0]
		assert_true(f'schem = "{name}"' in block,
			f"lw_maps' {key} does not point at {name}")
		assert_true("size = {x = %d, y = %d, z = %d}" % (sx, sy, sz) in block,
			f"lw_maps has no {sx}x{sy}x{sz} footprint for {key}")
		origin = re.search(r"origin = \{x = (-?\d+), y = BASE, z = (-?\d+)\}", block)
		spawn = re.search(r"spawn = \{x = (-?\d+), y = BASE \+ (\d+), z = (-?\d+)\}",
			block)
		assert_true(origin is not None and spawn is not None,
			f"lw_maps' {key} has no origin/spawn in the expected shape")
		local = maps.SPAWNS[name]
		want = (int(origin.group(1)) + local[0], BASE_Y + local[1],
			int(origin.group(2)) + local[2])
		got = (int(spawn.group(1)), BASE_Y + int(spawn.group(2)),
			int(spawn.group(3)))
		assert_true(want == got,
			f"lw_maps sends visitors to {got} on {key}, but the schematic's "
			f"spawn {local} at that origin is {want}")


_HARNESS: list | None = []


def run_lua_harness():
	"""Run the headless lw_maps harness once; return the nodes it registered.

	Returns None when no Lua interpreter is installed, which is how the checks
	that depend on it degrade instead of failing on a bare container.
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
		nodes = {line[len("NODE "):].strip()
			for line in result.stdout.splitlines() if line.startswith("NODE ")}
		assert_true(bool(nodes), "the Lua harness registered no nodes at all")
		_HARNESS.append(nodes)
		return nodes
	_HARNESS.append(None)
	return None


def test_lua_logic() -> None:
	"""The headless lw_maps harness: registry, atmosphere, flicker, /maps."""
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
