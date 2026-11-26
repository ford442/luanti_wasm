#!/usr/bin/env python3
# Luanti
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 The Luanti Contributors
"""Generate the lw_flora (plant designer) textures for games/luanti_web.

Every plant tile is greyscale so lw_flora/init.lua can tint it with
``[multiply`` into any of the 16 palette colours. Deterministic; reuses the
standard-library PNG writer from generate_luanti_web_textures.py:

    python3 util/content/generate_luanti_web_flora.py
"""

from __future__ import annotations

import argparse
import pathlib
import sys

SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
	sys.path.insert(0, str(SCRIPT_DIR))

from generate_luanti_web_textures import (  # noqa: E402
	Image, Noise, fill_disc, fill_rect, new_image, put, rgb, save_png, shade,
)

CLEAR = (0, 0, 0, 0)


def grey(v: int, a: int = 255) -> tuple[int, int, int, int]:
	return (v, v, v, a)


def tex_petal() -> Image:
	# Soft overlapping petal lobes with darker veins; a few clear gaps so
	# allfaces_optional reads as petals rather than a cube.
	img = new_image(16, 16, grey(225))
	n = Noise(41)
	for y in range(16):
		for x in range(16):
			v = 215 + int(n.at(x, y) * 40)
			if (x + y) % 8 == 0 or (x - y) % 8 == 0:
				v -= 45
			img[y][x] = grey(min(255, v))
	for cx, cy in ((3, 3), (12, 4), (7, 12), (14, 13)):
		put(img, cx, cy, CLEAR)
	return img


def tex_leaves() -> Image:
	img = new_image(16, 16, CLEAR)
	n = Noise(77)
	for y in range(16):
		for x in range(16):
			r = n.at(x, y)
			if r < 0.14:
				continue
			img[y][x] = grey(110 + int(r * 145))
	return img


def tex_stem() -> Image:
	img = new_image(16, 16, grey(200))
	for y in range(16):
		for x in range(16):
			v = 170 + (25 if x in (6, 7, 8) else 0) - (30 if x in (4, 11) else 0)
			img[y][x] = grey(v)
	return img


def tex_fruit() -> Image:
	img = new_image(16, 16, grey(200))
	n = Noise(5)
	n.grain(img, 0.25)
	fill_rect(img, 3, 3, 5, 5, grey(255))
	return img


def tex_bark() -> Image:
	img = new_image(16, 16, grey(190))
	n = Noise(19)
	for y in range(16):
		for x in range(16):
			v = 160 + int(n.at(x, y // 3) * 70)
			if x % 5 == 0:
				v -= 50
			img[y][x] = grey(max(0, min(255, v)))
	return img


def tex_bark_top() -> Image:
	img = new_image(16, 16, grey(150))
	for r, v in ((7.5, 150), (6, 215), (4.5, 185), (3, 225), (1.5, 190)):
		fill_disc(img, 7.5, 7.5, r, grey(v))
	return img


def tex_tiny_stem() -> Image:
	img = new_image(16, 16, CLEAR)
	green = rgb("#4f9a36")
	for y in range(6, 16):
		put(img, 7, y, green)
	for x, y in ((6, 11), (5, 10), (8, 13), (9, 12)):
		put(img, x, y, shade(green, 1.15))
	return img


def tex_tiny_head() -> Image:
	img = new_image(16, 16, CLEAR)
	for cx, cy in ((7, 2), (5, 4), (9, 4), (7, 6), (4, 2), (10, 2)):
		fill_disc(img, cx, cy, 1.6, grey(235))
	fill_disc(img, 7, 4, 1.0, grey(120))
	return img


def tex_designer() -> Image:
	img = new_image(16, 16, CLEAR)
	stem = rgb("#3f8a2e")
	for y in range(6, 15):
		put(img, 7, y, stem)
	fill_disc(img, 5, 10, 1.5, rgb("#5aa83c"))
	fill_disc(img, 10, 9, 1.5, rgb("#5aa83c"))
	for cx, cy in ((7, 2), (4, 4), (10, 4), (7, 6), (5, 6), (9, 6), (5, 2), (9, 2)):
		fill_disc(img, cx, cy, 1.3, rgb("#e38cae"))
	fill_disc(img, 7, 4, 1.2, rgb("#e6c22f"))
	# Pencil across the corner: this is the editor, not a flower.
	for i in range(6):
		put(img, 9 + i, 15 - i, rgb("#e07a22"))
	put(img, 15, 9, rgb("#1c1c1a"))
	return img


def tex_seed() -> Image:
	img = new_image(16, 16, CLEAR)
	paper = rgb("#c8a97a")
	fill_rect(img, 3, 2, 12, 14, paper)
	fill_rect(img, 3, 2, 12, 3, shade(paper, 0.8))
	fill_disc(img, 7.5, 8.5, 2.5, rgb("#e38cae"))
	fill_disc(img, 7.5, 8.5, 1.0, rgb("#e6c22f"))
	for x, y in ((5, 12), (8, 12), (10, 11)):
		put(img, x, y, rgb("#7b5230"))
	return img


TEXTURES = {
	"lw_flora_petal.png": tex_petal,
	"lw_flora_leaves.png": tex_leaves,
	"lw_flora_stem.png": tex_stem,
	"lw_flora_fruit.png": tex_fruit,
	"lw_flora_bark.png": tex_bark,
	"lw_flora_bark_top.png": tex_bark_top,
	"lw_flora_tiny_stem.png": tex_tiny_stem,
	"lw_flora_tiny_head.png": tex_tiny_head,
	"lw_flora_designer.png": tex_designer,
	"lw_flora_seed.png": tex_seed,
}


def generate(root: pathlib.Path) -> list[pathlib.Path]:
	out = root / "games" / "luanti_web" / "mods" / "lw_flora" / "textures"
	out.mkdir(parents=True, exist_ok=True)
	written = []
	for name, factory in TEXTURES.items():
		path = out / name
		save_png(path, factory())
		written.append(path)
	return written


def main() -> int:
	parser = argparse.ArgumentParser(description=__doc__,
		formatter_class=argparse.RawDescriptionHelpFormatter)
	parser.add_argument("--root", type=pathlib.Path,
		default=pathlib.Path(__file__).resolve().parents[2])
	args = parser.parse_args()
	written = generate(args.root)
	print("{} files, {:.1f} KiB".format(len(written),
		sum(p.stat().st_size for p in written) / 1024))
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
