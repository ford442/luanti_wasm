#!/usr/bin/env python3
# Luanti
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 The Luanti Contributors
"""Checks for the kinetic courtyard content (no engine required)."""

from __future__ import annotations

import pathlib
import sys

SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
ROOT = SCRIPT_DIR.parents[1]
if str(SCRIPT_DIR) not in sys.path:
	sys.path.insert(0, str(SCRIPT_DIR))

from mts_to_text import PROB_NEVER, read_mts, schematic_from_cells, write_mts
from generate_luanti_web_living import FRAME_COUNT, SX, SY, SZ, check, diff_count, frames
from generate_luanti_web_textures import (
	CELL, FIRE_FRAMES, REEL_FRAMES, SCREEN_COLS, SCREEN_ROWS, TICKER_FRAMES,
	WATER_FRAMES, fire_frame, filmstrip, water_frame,
)


def assert_true(cond: bool, message: str) -> None:
	if not cond:
		raise SystemExit(message)


def test_mts_roundtrip() -> None:
	fountain = ROOT / "games/luanti_web/mods/lw_world/schems/plaza_fountain.mts"
	original = fountain.read_bytes()
	schem = read_mts(original)
	rewritten = write_mts(schem)
	again = read_mts(rewritten)
	assert_true(again.size == schem.size, "roundtrip changed size")
	assert_true(list(again.names) == list(schem.names), "roundtrip changed names")
	assert_true(again.content == schem.content, "roundtrip changed content")
	assert_true(again.param1 == schem.param1, "roundtrip changed param1")
	assert_true(again.param2 == schem.param2, "roundtrip changed param2")

	cells = {(0, 0, 0): "lw_nodes:stone", (1, 0, 0): "air"}
	built = schematic_from_cells(2, 1, 1, cells)
	assert_true(read_mts(write_mts(built)).names[0] in ("air", "lw_nodes:stone"),
		"tiny schematic did not intern names")


def test_living_frames() -> None:
	built = frames()
	check(built)
	assert_true(len(built) == FRAME_COUNT, "wrong frame count")
	for schem in built:
		assert_true((schem.param1[0] & 0x7F) == PROB_NEVER,
			"controller cell must be never-place")
	# Ping-pong seam: last → first is the wrap the Lua sequence avoids, but
	# the files themselves still have to be a cheap swap if someone loops.
	worst = max(diff_count(built[i], built[(i + 1) % FRAME_COUNT])
		for i in range(FRAME_COUNT))
	assert_true(worst <= 24, f"frame diffs too large: {worst}")
	volume = SX * SY * SZ
	assert_true(volume == 80, "living pavilion grew; revisit the WASM swap budget")


def test_apply_diff_skips_never_and_unloaded() -> None:
	"""Mirror schems.apply_diff: never-place cells stay put, ignore aborts."""
	built = frames()
	volume = SX * SY * SZ

	def names_of(schem):
		out = []
		for i in range(volume):
			if (schem.param1[i] & 0x7F) == PROB_NEVER:
				out.append(None)
			else:
				out.append(schem.names[schem.content[i]])
		return out

	world = names_of(built[0])
	# Controller occupies the origin, which every frame leaves unplaced.
	world[0] = "lw_world:living"
	swaps = 0
	for i, target in enumerate(names_of(built[4])):
		if target is None:
			continue
		if world[i] != target:
			world[i] = target
			swaps += 1
	assert_true(world[0] == "lw_world:living", "controller cell was overwritten")
	assert_true(0 < swaps <= 24, f"unexpected swap count {swaps}")


def test_filmstrip_layout() -> None:
	water = filmstrip([water_frame(i) for i in range(WATER_FRAMES)])
	assert_true(len(water) == 16 * WATER_FRAMES and len(water[0]) == 16,
		"water strip is not 16 x (16*frames)")
	fire = filmstrip([fire_frame(i) for i in range(FIRE_FRAMES)])
	assert_true(len(fire) == 16 * FIRE_FRAMES and len(fire[0]) == 16,
		"fire strip is not 16 x (16*frames)")
	# Theater contract used by docs/filmstrips.md and lw_theater.
	assert_true(SCREEN_COLS == 6 and SCREEN_ROWS == 4, "screen grid drifted")
	assert_true(CELL == 32 and REEL_FRAMES == 16, "reel cell/frame contract drifted")
	assert_true(TICKER_FRAMES == 16, "ticker frame count drifted")


def test_committed_living_files() -> None:
	built = frames()
	for index, schem in enumerate(built):
		path = ROOT / "games/luanti_web/mods/lw_world/schems" / f"living_{index}.mts"
		assert_true(path.is_file(), f"missing {path.name}")
		on_disk = read_mts(path.read_bytes())
		assert_true(on_disk.size == schem.size, f"{path.name} size mismatch")
		assert_true(on_disk.content == schem.content, f"{path.name} is stale; regenerate")


def main() -> int:
	test_mts_roundtrip()
	test_living_frames()
	test_apply_diff_skips_never_and_unloaded()
	test_filmstrip_layout()
	test_committed_living_files()
	print("kinetic courtyard checks ok")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
