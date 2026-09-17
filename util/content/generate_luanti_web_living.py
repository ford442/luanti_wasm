#!/usr/bin/env python3
# Luanti
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 The Luanti Contributors
"""Generate the kinetic courtyard's living-building schematic frames.

The pavilion is 4x5x4 (x, y, z) and lives inside the cart loop. Six frames
are a stop-motion loop of windows, cornice and roof lamps — not a rebuild of
the shell — so consecutive stamps differ by a handful of nodes. The courtyard
timer swaps those diffs every few seconds; a full VoxelManip rewrite of the
footprint would be wasted work on the WASM application worker.

    python3 util/content/generate_luanti_web_living.py

Frame 0 is what mapgen stamps. Frames 1–5 leave (0,0,0) unplaced so the
airlike controller node that owns the timer is never overwritten.

Only the standard library is used.
"""

from __future__ import annotations

import argparse
import pathlib
import sys

SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
	sys.path.insert(0, str(SCRIPT_DIR))

from mts_to_text import NEVER, schematic_from_cells, to_text, write_mts

# Must match LIVING_* in games/luanti_web/mods/lw_world/init.lua.
SX, SY, SZ = 4, 5, 4
FRAME_COUNT = 6

BRICK = "lw_nodes:stone_brick"
GOLD = "lw_nodes:gold_trim"
LAMP = "lw_nodes:lamp"
TICKER = "lw_nodes:ticker"
AIR = "air"

WINDOW_BY_FRAME = [
	"lw_nodes:wool_dark_grey",
	"lw_nodes:wool_cyan",
	"lw_nodes:glass",
	"lw_nodes:wool_magenta",
	"lw_nodes:ticker",
	"lw_nodes:wool_yellow",
]


def cell(x: int, y: int, z: int, name, cells: dict) -> None:
	cells[(x, y, z)] = name


def shell(cells: dict, window: str, gold_cornice: bool, lamps: bool) -> None:
	# Floor, walls, doorway on the south face (z = 0) so a visitor inside the
	# cart loop walks in facing north.
	for x in range(SX):
		for z in range(SZ):
			cell(x, 0, z, BRICK, cells)
	for y in (1, 2):
		for x in range(SX):
			for z in range(SZ):
				edge = x in (0, SX - 1) or z in (0, SZ - 1)
				door = z == 0 and x in (1, 2)
				if door:
					cell(x, y, z, AIR, cells)
				elif edge:
					cell(x, y, z, BRICK, cells)
				else:
					cell(x, y, z, AIR, cells)
		# Windows: north wall, and one on each side.
		cell(1, y, SZ - 1, window, cells)
		cell(2, y, SZ - 1, window, cells)
		cell(0, y, 1, window, cells)
		cell(SX - 1, y, 1, window, cells)

	cornice = GOLD if gold_cornice else BRICK
	for x in range(SX):
		for z in range(SZ):
			edge = x in (0, SX - 1) or z in (0, SZ - 1)
			cell(x, 3, z, cornice if edge else AIR, cells)

	# Roof: a brick slab with optional corner lamps. The centre stays air so
	# the courtyard sky still reads through.
	for x in range(SX):
		for z in range(SZ):
			edge = x in (0, SX - 1) or z in (0, SZ - 1)
			if lamps and x in (0, SX - 1) and z in (0, SZ - 1):
				cell(x, 4, z, LAMP, cells)
			elif edge:
				cell(x, 4, z, BRICK, cells)
			else:
				cell(x, 4, z, AIR, cells)

	# Frame 4 puts a ticker strip on the north cornice — an extra animated
	# surface on the living building itself.
	if window == TICKER:
		cell(1, 3, SZ - 1, TICKER, cells)
		cell(2, 3, SZ - 1, TICKER, cells)


def frame_cells(index: int) -> dict:
	cells: dict = {}
	window = WINDOW_BY_FRAME[index]
	gold_cornice = index >= 2
	lamps = index in (3, 4)
	shell(cells, window, gold_cornice, lamps)
	# The controller sits at the origin in every frame. Never-place it so a
	# stamp cannot wipe the node timer that drives the loop.
	cells[(0, 0, 0)] = NEVER
	return cells


def frames() -> list:
	return [schematic_from_cells(SX, SY, SZ, frame_cells(i)) for i in range(FRAME_COUNT)]


def diff_count(a, b) -> int:
	total = SX * SY * SZ
	changed = 0
	for i in range(total):
		name_a = a.names[a.content[i]] if (a.param1[i] & 0x7F) else None
		name_b = b.names[b.content[i]] if (b.param1[i] & 0x7F) else None
		if name_a != name_b:
			changed += 1
	return changed


def generate(root: pathlib.Path) -> list[pathlib.Path]:
	out_dir = root / "games" / "luanti_web" / "mods" / "lw_world" / "schems"
	out_dir.mkdir(parents=True, exist_ok=True)
	written = []
	for index, schem in enumerate(frames()):
		path = out_dir / f"living_{index}.mts"
		path.write_bytes(write_mts(schem))
		written.append(path)
	return written


def check(schems) -> None:
	assert len(schems) == FRAME_COUNT
	for index, schem in enumerate(schems):
		assert schem.size == (SX, SY, SZ), schem.size
		origin = 0
		assert (schem.param1[origin] & 0x7F) == 0
	worst = max(diff_count(schems[i], schems[(i + 1) % FRAME_COUNT])
		for i in range(FRAME_COUNT))
	# The WASM worker swaps only these diffs. Keep the bound tight so a future
	# edit that accidentally rebuilds the shell fails this check.
	if worst > 24:
		raise SystemExit(f"consecutive living frames differ by {worst} nodes (max 24)")


def main() -> int:
	parser = argparse.ArgumentParser(description=__doc__,
		formatter_class=argparse.RawDescriptionHelpFormatter)
	parser.add_argument("--root", type=pathlib.Path,
		default=pathlib.Path(__file__).resolve().parents[2])
	parser.add_argument("--dump", action="store_true",
		help="print the text form of each frame")
	parser.add_argument("--check", action="store_true",
		help="validate frames without writing")
	args = parser.parse_args()

	built = frames()
	check(built)
	if args.dump:
		for index, schem in enumerate(built):
			print(f"== living_{index}.mts")
			sys.stdout.write(to_text(schem))
	if args.check:
		print(f"{FRAME_COUNT} frames, {SX}x{SY}x{SZ}, ok")
		return 0
	written = generate(args.root)
	for path in written:
		print(path.relative_to(args.root))
	print("{} files, {:.1f} KiB".format(
		len(written), sum(p.stat().st_size for p in written) / 1024))
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
