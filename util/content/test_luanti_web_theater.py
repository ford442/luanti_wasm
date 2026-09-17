#!/usr/bin/env python3
# Luanti
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 The Luanti Contributors
"""Checks for theater Tier A (no engine required)."""

from __future__ import annotations

import pathlib
import struct
import subprocess
import sys

SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
ROOT = SCRIPT_DIR.parents[1]
if str(SCRIPT_DIR) not in sys.path:
	sys.path.insert(0, str(SCRIPT_DIR))

from mts_to_text import node_index, read_mts
from generate_luanti_web_textures import (
	CELL, REEL_FRAMES, REEL_H, REEL_W, REELS, SCREEN_COLS, SCREEN_ROWS,
	filmstrip, reel_cell_strips, reel_title_frame,
)


def assert_true(cond: bool, message: str) -> None:
	if not cond:
		raise SystemExit(message)


def png_size(path: pathlib.Path) -> tuple[int, int]:
	data = path.read_bytes()
	assert_true(data[:8] == b"\x89PNG\r\n\x1a\n", f"{path.name} is not a PNG")
	width, height = struct.unpack(">II", data[16:24])
	return width, height


def test_lua_logic() -> None:
	script = SCRIPT_DIR / "test_luanti_web_theater.lua"
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
		assert_true("theater Tier A checks ok" in result.stdout,
			"lua checks did not print the ok line")
		return
	raise SystemExit(f"no lua interpreter found ({last_err})")


def test_reel_contract() -> None:
	assert_true(SCREEN_COLS == 6 and SCREEN_ROWS == 4, "screen grid drifted")
	assert_true(CELL == 32 and REEL_FRAMES == 24, "reel cell/frame contract drifted")
	assert_true(list(REELS) == ["title", "show", "bars"],
		f"reel order drifted: {list(REELS)}")
	assert_true(REEL_W == 192 and REEL_H == 128,
		"whole-frame size drifted from 6x4 of 32px cells")
	title = reel_title_frame(0)
	assert_true(len(title) == REEL_H and len(title[0]) == REEL_W,
		"title frame is not 192x128")
	assert_true(reel_title_frame(0) != reel_title_frame(8),
		"title card 3 and 2 are identical; the wall would not show motion")
	assert_true(reel_title_frame(8) != reel_title_frame(16),
		"title card 2 and 1 are identical")
	strips = reel_cell_strips(reel_title_frame)
	assert_true(len(strips) == SCREEN_COLS * SCREEN_ROWS, "wrong cell count")
	strip = strips[(0, 0)]
	assert_true(len(strip) == CELL * REEL_FRAMES and len(strip[0]) == CELL,
		"cell strip is not 32 x (32*24)")
	assert_true(len(filmstrip([title][:1])) == REEL_H, "filmstrip helper")


def test_committed_filmstrips() -> None:
	folder = ROOT / "games/luanti_web/mods/lw_theater/textures"
	for name in ("lw_chandelier.png", "lw_reel_button.png", "lw_screen_off.png",
			"lw_marquee.png", "lw_seat_top.png"):
		path = folder / name
		assert_true(path.is_file() and path.stat().st_size > 0, f"missing {name}")
	for reel in REELS:
		for row in range(SCREEN_ROWS):
			for col in range(SCREEN_COLS):
				path = folder / f"lw_screen_{reel}_{row}_{col}.png"
				assert_true(path.is_file(), f"missing {path.name}")
				width, height = png_size(path)
				assert_true(width == CELL and height == CELL * REEL_FRAMES,
					f"{path.name} is {width}x{height}, expected {CELL}x{CELL * REEL_FRAMES}")


def test_theater_schematic() -> None:
	path = ROOT / "games/luanti_web/mods/lw_world/schems/theater.mts"
	schem = read_mts(path.read_bytes())
	sx, sy, sz = schem.size
	assert_true(schem.size == (33, 15, 30), f"theater.mts size drifted: {schem.size}")
	names = set(schem.names)
	for required in (
		"lw_theater:screen_off", "lw_theater:seat", "lw_theater:aisle_light",
		"lw_theater:marquee", "lw_nodes:curtain", "lw_nodes:gold_trim",
	):
		assert_true(required in names, f"theater.mts missing {required}")
	counts = {name: 0 for name in names}
	for i, content in enumerate(schem.content):
		counts[schem.names[content]] += 1
	assert_true(counts["lw_theater:screen_off"] == 24, "screen is not 6x4")
	assert_true(counts["lw_theater:seat"] >= 40, "not enough seats")
	assert_true(counts["lw_theater:aisle_light"] >= 8, "aisle lights missing")
	assert_true(counts["lw_theater:marquee"] >= 8, "marquee missing")
	assert_true(counts["lw_nodes:curtain"] >= 100, "proscenium curtains missing")
	# Top-left cell as the audience sees it, matching SCREEN_* in lw_world.
	top_left = node_index(sx, sy, 13, 10, 27)
	assert_true(schem.names[schem.content[top_left]] == "lw_theater:screen_off",
		"top-left screen cell drifted")


def test_source_hooks() -> None:
	theater = (ROOT / "games/luanti_web/mods/lw_theater/init.lua").read_text(
		encoding="utf-8")
	world = (ROOT / "games/luanti_web/mods/lw_world/init.lua").read_text(
		encoding="utf-8")
	assert_true('lw_theater.reels = {"title", "show", "bars"}' in theater,
		"reel order missing")
	assert_true("lw_theater:chandelier" in theater, "chandelier node missing")
	assert_true("function lw_theater.toggle_house_lights" in theater,
		"dimmer hook missing")
	assert_true("pcall(core.sound_play" in theater, "sound degrade path missing")
	assert_true('register_chatcommand("sit"' in theater, "/sit missing")
	assert_true("lw_theater.set_reel(lw_theater.reels[1])" in world,
		"fresh worlds must auto-start a reel")
	assert_true("lw_theater:chandelier" in world, "world does not place chandeliers")
	assert_true("lw_theater:button" in world, "world does not place the reel button")


def test_reel_ogg() -> None:
	path = ROOT / "games/luanti_web/mods/lw_theater/sounds/lw_reel.ogg"
	assert_true(path.is_file(), "missing lw_reel.ogg")
	data = path.read_bytes()
	assert_true(data[:4] == b"OggS", "lw_reel.ogg is not an Ogg bitstream")
	assert_true(b"vorbis" in data[:256], "lw_reel.ogg is not Vorbis")
	# Keep the sting tiny: it is preloaded into luanti.data for every visitor.
	assert_true(path.stat().st_size < 12 * 1024, "lw_reel.ogg is over the 12 KiB budget")


def test_no_mp4_tiles() -> None:
	"""Tier A must not bind an MP4 to a node. That is Tier B."""
	theater = (ROOT / "games/luanti_web/mods/lw_theater/init.lua").read_text(
		encoding="utf-8")
	assert_true("movie.mp4" not in theater, "do not bind MP4 as a tile")
	assert_true('type = "vertical_frames"' in theater, "vertical_frames missing")


def main() -> int:
	test_lua_logic()
	test_reel_contract()
	test_committed_filmstrips()
	test_theater_schematic()
	test_source_hooks()
	test_reel_ogg()
	test_no_mp4_tiles()
	print("theater Tier A checks ok")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
