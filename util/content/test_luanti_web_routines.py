#!/usr/bin/env python3
# Luanti
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 The Luanti Contributors
"""Checks for the dance director and its stages (no engine required)."""

from __future__ import annotations

import pathlib
import re
import subprocess
import sys

SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
ROOT = SCRIPT_DIR.parents[1]
if str(SCRIPT_DIR) not in sys.path:
	sys.path.insert(0, str(SCRIPT_DIR))

from mts_to_text import node_index, read_mts

GAME = ROOT / "games/luanti_web"
SCHEMS = GAME / "mods/lw_world/schems"


def assert_true(cond: bool, message: str) -> None:
	if not cond:
		raise SystemExit(message)


def test_lua_logic() -> None:
	script = SCRIPT_DIR / "test_luanti_web_routines.lua"
	# Prefer lua5.1: that is the engine's dialect. Fall back to whatever
	# `lua` is, then luajit.
	candidates = ("lua5.1", "lua", "luajit")
	last_err = None
	for binary in candidates:
		try:
			result = subprocess.run(
				[binary, str(script)],
				cwd=str(ROOT),
				check=False,
				capture_output=True,
				text=True,
			)
		except FileNotFoundError as err:
			last_err = err
			continue
		if result.returncode != 0:
			sys.stderr.write(result.stdout)
			sys.stderr.write(result.stderr)
			raise SystemExit(f"{binary} {script.name} failed")
		assert_true("dance routine checks ok" in result.stdout,
			"lua checks did not print the ok line")
		return
	raise SystemExit(f"no lua interpreter found ({last_err})")


def node_at(schem, x: int, y: int, z: int) -> str:
	sx, sy, sz = schem.size
	if not (0 <= x < sx and 0 <= y < sy and 0 <= z < sz):
		return "out-of-bounds"
	return schem.names[schem.content[node_index(sx, sy, x, y, z)]]


# Every dancer position the world places, in the coordinates of the schematic
# it sits on: (local x, y, z, what has to be under it). A mark has to stand in
# air with something solid below, or the cast comes out buried or floating.
#
# These mirror maps.lua; the point of the check is that regenerating a map
# cannot quietly move the floor out from under a dance.
MAP_STAGES = {
	"map_halloween.mts": [
		(5, 6, 8, "lw_nodes:planks"),      # mark_lead, porch deck
		(4, 6, 6, "lw_nodes:planks"),      # mark_1
		(4, 6, 10, "lw_nodes:planks"),     # mark_2
		(3, 6, 9, "lw_nodes:planks"),      # the director node
	],
	"map_fruit_garden.mts": [
		(28, 2, 11, "lw_nodes:wool_red"),  # mark_lead, the melon bowl floor
		(26, 4, 20, "lw_nodes:dirt"),      # the director node, on the spine
	],
}


def test_map_stages() -> None:
	for name, cells in MAP_STAGES.items():
		schem = read_mts((SCHEMS / name).read_bytes())
		for x, y, z, floor in cells:
			here = node_at(schem, x, y, z)
			assert_true(here == "air",
				f"{name}: ({x},{y},{z}) holds {here}, so a dance mark or the "
				f"director node would be buried in it")
			under = node_at(schem, x, y - 1, z)
			assert_true(under == floor,
				f"{name}: ({x},{y - 1},{z}) is {under}, not {floor}; the dancer "
				f"there would have nothing to stand on")


def test_map_stages_match_the_world() -> None:
	"""The cells checked above are the cells lw_world actually stamps.

	MAP_STAGES is a copy of coordinates that live in maps.lua, so it is only
	worth anything if the two cannot drift apart.
	"""
	text = (GAME / "mods/lw_world/maps.lua").read_text(encoding="utf-8")
	placed = set()
	for x, y, z in re.findall(r'\{(\d+), (\d+), (\d+), "mark_\w+"\}', text):
		placed.add((int(x), int(y), int(z)))
	for x, y, z in re.findall(r"node = \{(\d+), (\d+), (\d+)\}", text):
		placed.add((int(x), int(y), int(z)))
	checked = {(x, y, z) for cells in MAP_STAGES.values() for x, y, z, _ in cells}
	assert_true(placed == checked,
		f"maps.lua places dancers at {sorted(placed)} but the schematic check "
		f"looks at {sorted(checked)}")


def test_theater_stage() -> None:
	"""The theater's own stage strip, in front of the screen and clear of seats."""
	schem = read_mts((SCHEMS / "theater.mts").read_bytes())
	# theater.mts is stamped with its minimum corner at (-16, GROUND - 1, 33).
	ox, oy, oz = -16, 7, 33
	for wz in range(56, 60):
		for wx in (-2, 0, 2, 6):
			floor = node_at(schem, wx - ox, 8 - oy, wz - oz)
			assert_true(floor == "lw_nodes:carpet",
				f"theater.mts: ({wx},8,{wz}) is {floor}, not the carpet the "
				f"stage strip is laid over")
			above = node_at(schem, wx - ox, 9 - oy, wz - oz)
			assert_true(above == "air",
				f"theater.mts: ({wx},9,{wz}) holds {above}; the stage has to be "
				f"clear for the marks and the cast")


def test_routine_files() -> None:
	"""Every routine file is a committed Lua table under the game, not a mod."""
	folder = GAME / "routines"
	files = sorted(p.name for p in folder.glob("*.lua"))
	assert_true(files, "no routine files are committed")
	assert_true("chorus_line_v1.lua" in files,
		"the showcase routine is not committed")
	for name in files:
		text = (folder / name).read_text(encoding="utf-8")
		assert_true(text.startswith("-- Luanti\n"),
			f"{name} is missing the licence header")
		assert_true(re.search(r"\breturn\s*\{", text) is not None,
			f"{name} does not return a table")
		assert_true("id =" in text, f"{name} has no id")


def test_no_hardcoded_cast() -> None:
	"""The director drives the catalog, not its own private move list."""
	director = (GAME / "mods/lw_dance/director.lua").read_text(encoding="utf-8")
	assert_true("lw_dance.moves" not in director.replace("S.moves", ""),
		"director.lua indexes the move table directly instead of going "
		"through the shared driver")
	assert_true("S.play_move" in director,
		"director.lua does not use the shared play_move")
	driver = (GAME / "mods/lw_dance/driver.lua").read_text(encoding="utf-8")
	assert_true("get_player_name" not in driver,
		"driver.lua is supposed to work on any object, not only players")


def main() -> int:
	test_lua_logic()
	test_map_stages()
	test_map_stages_match_the_world()
	test_theater_stage()
	test_routine_files()
	test_no_hardcoded_cast()
	print("dance director checks ok")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
