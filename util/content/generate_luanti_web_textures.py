#!/usr/bin/env python3
# Luanti
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 The Luanti Contributors
"""Generate every texture used by games/luanti_web.

The showcase pack keeps its art in-repo as small indexed-free RGBA PNGs so the
Emscripten ``--preload-file`` payload stays predictable (see the content budget
in ``wasm_porting.md``). Rather than committing binaries nobody can edit, the
tiles are described procedurally here and regenerated with:

    python3 util/content/generate_luanti_web_textures.py

Everything is deterministic: rerunning the script on an unchanged tree produces
byte-identical files, so a regeneration shows up as an empty diff.

Only the standard library is used (zlib + struct) — no Pillow, no NumPy, so it
runs in CI containers and in the Emscripten build image.

Animated tiles are written as vertical filmstrips, the layout Luanti's
``vertical_frames`` animation expects: ``N`` square frames stacked top to
bottom in one image of ``size x (size * N)``. The same convention is what an
ffmpeg-based import would produce, e.g.

    ffmpeg -i clip.mp4 -vf "fps=12,scale=32:32" -frames:v 16 f%02d.png
    magick montage f*.png -tile 1x16 -geometry +0+0 strip.png
"""

from __future__ import annotations

import argparse
from collections.abc import Callable
import math
import pathlib
import struct
import zlib

# --------------------------------------------------------------------------
# Minimal PNG writer
# --------------------------------------------------------------------------

Color = tuple[int, int, int, int]
Image = list[list[Color]]


def new_image(width: int, height: int, fill: Color = (0, 0, 0, 0)) -> Image:
	return [[fill for _ in range(width)] for _ in range(height)]


def _paeth(a: int, b: int, c: int) -> int:
	p = a + b - c
	pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
	if pa <= pb and pa <= pc:
		return a
	return b if pb <= pc else c


def _filter_line(row: bytes, prior: bytes, bpp: int, kind: int) -> bytes:
	length = len(row)
	if kind == 0:
		return row
	out = bytearray(length)
	if kind == 1:
		for i in range(length):
			out[i] = (row[i] - (row[i - bpp] if i >= bpp else 0)) & 0xFF
	elif kind == 2:
		for i in range(length):
			out[i] = (row[i] - prior[i]) & 0xFF
	elif kind == 3:
		for i in range(length):
			left = row[i - bpp] if i >= bpp else 0
			out[i] = (row[i] - ((left + prior[i]) >> 1)) & 0xFF
	else:
		for i in range(length):
			left = row[i - bpp] if i >= bpp else 0
			upper_left = prior[i - bpp] if i >= bpp else 0
			out[i] = (row[i] - _paeth(left, prior[i], upper_left)) & 0xFF
	return bytes(out)


def _scanlines(image: Image) -> list[bytes]:
	return [bytes(value for pixel in row for value in pixel) for row in image]


def _encode_idat(lines: list[bytes], stride: int, bpp: int) -> bytes:
	"""Search filter strategies and deflate settings for the smallest IDAT.

	The repository's CI runs optipng over every committed PNG and fails a file
	it can shrink by more than 3%, so a naive encoder is not good enough: with
	every row stored unfiltered these tiles lose by up to 50%. On images this
	small an exhaustive search is cheap — a few dozen deflates of a few KiB —
	and it keeps the pipeline to the standard library, which is what lets the
	textures be regenerated in any CI container.
	"""
	# Each fixed filter, plus the usual per-row minimum-sum-of-absolute-
	# differences heuristic, which is what beats a fixed filter on photographic
	# content.
	candidates = []
	for kind in range(5):
		raw = bytearray()
		prior = bytes(stride)
		for line in lines:
			raw.append(kind)
			raw.extend(_filter_line(line, prior, bpp, kind))
			prior = line
		candidates.append(bytes(raw))

	def cost(data: bytes) -> int:
		return sum(value if value < 128 else 256 - value for value in data)

	raw = bytearray()
	prior = bytes(stride)
	for line in lines:
		best_kind, best = min(
			((kind, _filter_line(line, prior, bpp, kind)) for kind in range(5)),
			key=lambda entry: cost(entry[1]))
		raw.append(best_kind)
		raw.extend(best)
		prior = line
	candidates.append(bytes(raw))

	strategies = (zlib.Z_DEFAULT_STRATEGY, zlib.Z_FILTERED, zlib.Z_RLE,
		zlib.Z_HUFFMAN_ONLY)
	best_payload = None
	for raw_data in candidates:
		for strategy in strategies:
			compressor = zlib.compressobj(9, zlib.DEFLATED, 15, 9, strategy)
			payload = compressor.compress(raw_data) + compressor.flush()
			if best_payload is None or len(payload) < len(best_payload):
				best_payload = payload
	assert best_payload is not None
	return best_payload


def save_png(path: pathlib.Path, image: Image) -> None:
	height = len(image)
	width = len(image[0])
	bpp = 4

	def chunk(tag: bytes, payload: bytes) -> bytes:
		return (struct.pack(">I", len(payload)) + tag + payload
			+ struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF))

	header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
	data = _encode_idat(_scanlines(image), width * bpp, bpp)
	path.parent.mkdir(parents=True, exist_ok=True)
	path.write_bytes(b"\x89PNG\r\n\x1a\n"
		+ chunk(b"IHDR", header)
		+ chunk(b"IDAT", data)
		+ chunk(b"IEND", b""))


# --------------------------------------------------------------------------
# Colour and drawing helpers
# --------------------------------------------------------------------------


def rgb(value: str, alpha: int = 255) -> Color:
	value = value.lstrip("#")
	return (int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16), alpha)


def clamp(value: float, low: int = 0, high: int = 255) -> int:
	return max(low, min(high, int(round(value))))


def shade(color: Color, factor: float) -> Color:
	return (clamp(color[0] * factor), clamp(color[1] * factor),
		clamp(color[2] * factor), color[3])


def mix(a: Color, b: Color, t: float) -> Color:
	t = max(0.0, min(1.0, t))
	return tuple(clamp(a[i] + (b[i] - a[i]) * t) for i in range(4))  # type: ignore[return-value]


def put(image: Image, x: int, y: int, color: Color) -> None:
	if 0 <= y < len(image) and 0 <= x < len(image[0]):
		image[y][x] = color


def fill_rect(image: Image, x0: int, y0: int, x1: int, y1: int, color: Color) -> None:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			put(image, x, y, color)


def stroke_rect(image: Image, x0: int, y0: int, x1: int, y1: int, color: Color) -> None:
	for x in range(x0, x1 + 1):
		put(image, x, y0, color)
		put(image, x, y1, color)
	for y in range(y0, y1 + 1):
		put(image, x0, y, color)
		put(image, x1, y, color)


def fill_disc(image: Image, cx: float, cy: float, radius: float, color: Color) -> None:
	for y in range(len(image)):
		for x in range(len(image[0])):
			if (x - cx) ** 2 + (y - cy) ** 2 <= radius * radius:
				put(image, x, y, color)


class Noise:
	"""Small deterministic value hash. Seeded per texture, never time-based."""

	def __init__(self, seed: int) -> None:
		self.seed = seed & 0xFFFFFFFF

	def at(self, x: int, y: int) -> float:
		h = (x * 374761393 + y * 668265263 + self.seed * 1274126177) & 0xFFFFFFFF
		h = (h ^ (h >> 13)) * 1274126177 & 0xFFFFFFFF
		h = h ^ (h >> 16)
		return (h & 0xFFFF) / 65535.0

	def grain(self, image: Image, amount: float) -> None:
		for y in range(len(image)):
			for x in range(len(image[0])):
				pixel = image[y][x]
				if pixel[3] == 0:
					continue
				factor = 1.0 + (self.at(x, y) - 0.5) * amount
				image[y][x] = shade(pixel, factor)


# --------------------------------------------------------------------------
# A 3x5 pixel font, enough for labels baked into posters and title cards
# --------------------------------------------------------------------------

FONT = {
	"A": ("010", "101", "111", "101", "101"),
	"B": ("110", "101", "110", "101", "110"),
	"C": ("011", "100", "100", "100", "011"),
	"D": ("110", "101", "101", "101", "110"),
	"E": ("111", "100", "110", "100", "111"),
	"F": ("111", "100", "110", "100", "100"),
	"G": ("011", "100", "101", "101", "011"),
	"H": ("101", "101", "111", "101", "101"),
	"I": ("111", "010", "010", "010", "111"),
	"J": ("001", "001", "001", "101", "010"),
	"K": ("101", "110", "100", "110", "101"),
	"L": ("100", "100", "100", "100", "111"),
	"M": ("101", "111", "111", "101", "101"),
	"N": ("101", "111", "111", "111", "101"),
	"O": ("010", "101", "101", "101", "010"),
	"P": ("110", "101", "110", "100", "100"),
	"Q": ("010", "101", "101", "111", "011"),
	"R": ("110", "101", "110", "101", "101"),
	"S": ("011", "100", "010", "001", "110"),
	"T": ("111", "010", "010", "010", "010"),
	"U": ("101", "101", "101", "101", "011"),
	"V": ("101", "101", "101", "101", "010"),
	"W": ("101", "101", "111", "111", "101"),
	"X": ("101", "101", "010", "101", "101"),
	"Y": ("101", "101", "010", "010", "010"),
	"Z": ("111", "001", "010", "100", "111"),
	"0": ("111", "101", "101", "101", "111"),
	"1": ("010", "110", "010", "010", "111"),
	"2": ("110", "001", "010", "100", "111"),
	"3": ("110", "001", "010", "001", "110"),
	"4": ("101", "101", "111", "001", "001"),
	"5": ("111", "100", "110", "001", "110"),
	"6": ("011", "100", "110", "101", "010"),
	"7": ("111", "001", "010", "010", "010"),
	"8": ("010", "101", "010", "101", "010"),
	"9": ("010", "101", "011", "001", "110"),
	".": ("000", "000", "000", "000", "010"),
	"-": ("000", "000", "111", "000", "000"),
	"!": ("010", "010", "010", "000", "010"),
	" ": ("000", "000", "000", "000", "000"),
}

GLYPH_W = 3
GLYPH_H = 5


def text_width(text: str, spacing: int = 1, scale: int = 1) -> int:
	if not text:
		return 0
	return (len(text) * (GLYPH_W + spacing) - spacing) * scale


def draw_text(image: Image, x: int, y: int, text: str, color: Color,
		spacing: int = 1, scale: int = 1) -> None:
	cursor = x
	for char in text.upper():
		glyph = FONT.get(char)
		if glyph is not None:
			for row, bits in enumerate(glyph):
				for col, bit in enumerate(bits):
					if bit == "1":
						fill_rect(image,
							cursor + col * scale, y + row * scale,
							cursor + col * scale + scale - 1,
							y + row * scale + scale - 1, color)
		cursor += (GLYPH_W + spacing) * scale


# --------------------------------------------------------------------------
# Palette
# --------------------------------------------------------------------------

# 16 dyed cubes. lw_nodes tints one greyscale weave with [multiply, so these
# values also drive the pixel art in the gallery (games/luanti_web/mods/lw_world).
WOOL_COLORS: dict[str, str] = {
	"white": "e9e9e4",
	"grey": "9a9a95",
	"dark_grey": "4c4c48",
	"black": "1c1c1a",
	"red": "bf2f31",
	"orange": "e07a22",
	"yellow": "e6c22f",
	"green": "5aa83c",
	"dark_green": "2d6b2d",
	"cyan": "31b0ae",
	"blue": "2f5cba",
	"violet": "6c3fb8",
	"magenta": "b43196",
	"pink": "e38cae",
	"brown": "7b5230",
	"tan": "c8a97a",
}


# --------------------------------------------------------------------------
# Static node tiles (16x16)
# --------------------------------------------------------------------------

S = 16


def tex_stone() -> Image:
	base = rgb("7e7e7e")
	image = new_image(S, S, base)
	noise = Noise(11)
	for y in range(S):
		for x in range(S):
			image[y][x] = shade(base, 0.82 + 0.34 * noise.at(x, y))
	# A couple of darker pits so the surface is not pure static.
	for cx, cy in ((3, 11), (11, 4), (8, 13)):
		fill_disc(image, cx, cy, 1.4, shade(base, 0.68))
	return image


def tex_stone_brick() -> Image:
	base = rgb("8a8780")
	mortar = rgb("5f5d58")
	image = new_image(S, S, base)
	noise = Noise(23)
	for y in range(S):
		for x in range(S):
			image[y][x] = shade(base, 0.88 + 0.22 * noise.at(x, y))
	for y in (3, 7, 11, 15):
		fill_rect(image, 0, y, S - 1, y, mortar)
	for row, y0 in enumerate((0, 4, 8, 12)):
		offset = 0 if row % 2 == 0 else 8
		for x in (offset, offset + 8):
			fill_rect(image, x % S, y0, x % S, y0 + 3, mortar)
	# Top-light the courses so the wall reads in flat GLES2 shading.
	for y in (0, 4, 8, 12):
		for x in range(S):
			if image[y][x] != mortar:
				image[y][x] = shade(image[y][x], 1.12)
	return image


def tex_polished_stone() -> Image:
	base = rgb("9d9c97")
	image = new_image(S, S, base)
	for y in range(S):
		for x in range(S):
			sheen = 1.0 + 0.10 * math.sin((x + y) * 0.38)
			image[y][x] = shade(base, sheen)
	Noise(31).grain(image, 0.05)
	stroke_rect(image, 0, 0, S - 1, S - 1, shade(base, 0.82))
	stroke_rect(image, 1, 1, S - 2, S - 2, shade(base, 1.10))
	return image


def tex_planks() -> Image:
	light = rgb("a87a4e")
	dark = rgb("6d4a2c")
	image = new_image(S, S, light)
	noise = Noise(41)
	for y in range(S):
		for x in range(S):
			grain = 0.86 + 0.24 * noise.at(x // 1, y * 3)
			image[y][x] = shade(light, grain)
	for y in (0, 5, 10, 15):
		fill_rect(image, 0, y, S - 1, y, dark)
	for x, y0, y1 in ((6, 1, 4), (11, 6, 9), (3, 11, 14)):
		fill_rect(image, x, y0, x, y1, shade(dark, 1.15))
	return image


def tex_beam_side() -> Image:
	image = tex_planks()
	dark = rgb("5c3d24")
	for y in range(S):
		image[y][0] = dark
		image[y][S - 1] = dark
	for y in (2, 13):
		for x in (2, 13):
			fill_rect(image, x, y, x + 1, y + 1, rgb("6b6b66"))
	return image


def tex_beam_end() -> Image:
	image = new_image(S, S, rgb("9a6d45"))
	noise = Noise(43)
	for y in range(S):
		for x in range(S):
			ring = math.hypot(x - 7.5, y - 7.5)
			factor = 0.86 + 0.16 * math.sin(ring * 1.7) + 0.10 * noise.at(x, y)
			image[y][x] = shade(rgb("9a6d45"), factor)
	stroke_rect(image, 0, 0, S - 1, S - 1, rgb("5c3d24"))
	return image


def tex_glass() -> Image:
	pane = rgb("cfe6ef", 60)
	image = new_image(S, S, pane)
	frame = rgb("dff1f7", 190)
	stroke_rect(image, 0, 0, S - 1, S - 1, frame)
	for i in range(5, 12):
		put(image, i, i - 4, rgb("ffffff", 120))
		put(image, i + 1, i - 4, rgb("ffffff", 90))
	return image


def tex_bars() -> Image:
	image = new_image(S, S)
	metal = rgb("adb2b8")
	for x in (2, 7, 12):
		fill_rect(image, x, 0, x + 1, S - 1, metal)
		fill_rect(image, x, 0, x, S - 1, shade(metal, 1.15))
	fill_rect(image, 0, 1, S - 1, 2, shade(metal, 0.86))
	fill_rect(image, 0, 13, S - 1, 14, shade(metal, 0.86))
	return image


def tex_gold() -> Image:
	base = rgb("d8a92c")
	image = new_image(S, S, base)
	for y in range(S):
		for x in range(S):
			image[y][x] = shade(base, 0.86 + 0.26 * ((x + y) % 4) / 3.0)
	stroke_rect(image, 0, 0, S - 1, S - 1, shade(base, 0.68))
	fill_rect(image, 2, 7, S - 3, 8, shade(base, 1.22))
	return image


def tex_curtain() -> Image:
	base = rgb("7a1226")
	image = new_image(S, S, base)
	for y in range(S):
		for x in range(S):
			fold = 0.74 + 0.34 * (0.5 + 0.5 * math.sin(x * 1.05))
			image[y][x] = shade(base, fold)
	Noise(53).grain(image, 0.06)
	return image


def tex_carpet() -> Image:
	base = rgb("8d2436")
	image = new_image(S, S, base)
	noise = Noise(59)
	for y in range(S):
		for x in range(S):
			weave = 1.06 if (x + y) % 2 == 0 else 0.94
			image[y][x] = shade(base, weave * (0.94 + 0.12 * noise.at(x, y)))
	return image


def tex_column_side() -> Image:
	base = rgb("d9d5c8")
	image = new_image(S, S, base)
	for y in range(S):
		for x in range(S):
			flute = 0.80 + 0.30 * (0.5 + 0.5 * math.cos((x - 7.5) * 0.85))
			image[y][x] = shade(base, flute)
	Noise(61).grain(image, 0.05)
	return image


def tex_column_top() -> Image:
	base = rgb("d9d5c8")
	image = new_image(S, S, base)
	Noise(67).grain(image, 0.08)
	stroke_rect(image, 1, 1, S - 2, S - 2, shade(base, 0.80))
	fill_disc(image, 7.5, 7.5, 4.0, shade(base, 1.06))
	return image


def tex_fence() -> Image:
	image = tex_planks()
	for y in range(S):
		for x in range(S):
			image[y][x] = shade(image[y][x], 0.92)
	return image


def tex_lamp() -> Image:
	glass = rgb("fff3cf")
	image = new_image(S, S, glass)
	for y in range(S):
		for x in range(S):
			glow = 1.0 - 0.22 * (math.hypot(x - 7.5, y - 7.5) / 10.6)
			image[y][x] = shade(glass, glow)
	stroke_rect(image, 0, 0, S - 1, S - 1, rgb("b9a36a"))
	stroke_rect(image, 1, 1, S - 2, S - 2, rgb("ffffff"))
	return image


def tex_uplight() -> Image:
	image = new_image(S, S, rgb("3b3f44"))
	Noise(71).grain(image, 0.08)
	fill_disc(image, 7.5, 7.5, 4.6, rgb("ffe9a8"))
	fill_disc(image, 7.5, 7.5, 2.6, rgb("fffdf2"))
	stroke_rect(image, 0, 0, S - 1, S - 1, rgb("2b2e32"))
	return image


def tex_pedestal_side() -> Image:
	base = rgb("cdc8ba")
	image = new_image(S, S, base)
	Noise(73).grain(image, 0.06)
	fill_rect(image, 0, 0, S - 1, 1, shade(base, 1.12))
	fill_rect(image, 0, S - 2, S - 1, S - 1, shade(base, 0.82))
	fill_rect(image, 0, 7, S - 1, 8, shade(base, 0.90))
	return image


def tex_pedestal_top() -> Image:
	base = rgb("e2ddd0")
	image = new_image(S, S, base)
	Noise(79).grain(image, 0.05)
	stroke_rect(image, 0, 0, S - 1, S - 1, shade(base, 0.78))
	return image


def tex_frame() -> Image:
	# Opaque: this is a moulding block, used both as a picture frame and as the
	# edge of the poster panel, so it has to read from any side.
	wood = rgb("6b4322")
	image = new_image(S, S, wood)
	Noise(137).grain(image, 0.10)
	stroke_rect(image, 0, 0, S - 1, S - 1, shade(wood, 0.72))
	stroke_rect(image, 1, 1, S - 2, S - 2, shade(wood, 1.20))
	stroke_rect(image, 3, 3, S - 4, S - 4, rgb("d8a92c"))
	fill_rect(image, 5, 5, S - 6, S - 6, shade(wood, 0.88))
	return image


def tex_poster() -> Image:
	size = 32
	image = new_image(size, size, rgb("101a2b"))
	for y in range(size):
		for x in range(size):
			image[y][x] = mix(rgb("16233a"), rgb("2c1f4a"), y / (size - 1))
	# Simple voxel skyline so the poster reads as exhibition art, not a swatch.
	for x0, height, color in ((3, 9, "3f7f4f"), (9, 14, "56a367"), (16, 7, "2f6d55"),
			(21, 12, "4a8f9c"), (26, 5, "355f7a")):
		fill_rect(image, x0, size - height - 4, x0 + 4, size - 5, rgb(color))
	fill_disc(image, 24, 7, 3.2, rgb("f3d98a"))
	fill_rect(image, 0, size - 4, size - 1, size - 1, rgb("0b1220"))
	draw_text(image, 3, size - 27, "LUANTI", rgb("dfe9d8"))
	draw_text(image, 4, size - 3 - GLYPH_H + 2, "WEB", rgb("9fd7a6"))
	stroke_rect(image, 0, 0, size - 1, size - 1, rgb("d8a92c"))
	return image


def tex_stanchion() -> Image:
	image = new_image(S, S)
	brass = rgb("c9a12f")
	fill_rect(image, 6, 2, 9, S - 1, brass)
	fill_rect(image, 6, 2, 6, S - 1, shade(brass, 1.18))
	fill_rect(image, 9, 2, 9, S - 1, shade(brass, 0.80))
	fill_rect(image, 4, 0, 11, 2, shade(brass, 1.10))
	fill_rect(image, 3, 4, 12, 5, rgb("8d2436"))
	return image


def tex_grass_top() -> Image:
	base = rgb("5f9e46")
	image = new_image(S, S, base)
	noise = Noise(83)
	for y in range(S):
		for x in range(S):
			image[y][x] = shade(base, 0.84 + 0.30 * noise.at(x, y))
	return image


def tex_dirt() -> Image:
	base = rgb("6b4a2f")
	image = new_image(S, S, base)
	noise = Noise(89)
	for y in range(S):
		for x in range(S):
			image[y][x] = shade(base, 0.82 + 0.34 * noise.at(x, y))
	return image


def tex_grass_side() -> Image:
	image = tex_dirt()
	grass = tex_grass_top()
	noise = Noise(97)
	for x in range(S):
		depth = 3 + int(noise.at(x, 5) * 3)
		for y in range(depth):
			image[y][x] = grass[y][x]
		put(image, x, depth, mix(grass[depth % S][x], image[depth][x], 0.5))
	return image


def tex_sand() -> Image:
	base = rgb("d9c98f")
	image = new_image(S, S, base)
	noise = Noise(101)
	for y in range(S):
		for x in range(S):
			image[y][x] = shade(base, 0.90 + 0.18 * noise.at(x, y))
	return image


def tex_paving() -> Image:
	base = rgb("b6b0a2")
	image = new_image(S, S, base)
	noise = Noise(103)
	for y in range(S):
		for x in range(S):
			image[y][x] = shade(base, 0.90 + 0.18 * noise.at(x, y))
	joint = shade(base, 0.74)
	fill_rect(image, 0, 7, S - 1, 8, joint)
	fill_rect(image, 7, 0, 8, S - 1, joint)
	for x0, y0 in ((0, 0), (9, 0), (0, 9), (9, 9)):
		stroke_rect(image, x0, y0, x0 + 6, y0 + 6, shade(base, 1.08))
	return image


def tex_wool() -> Image:
	# Greyscale weave; lw_nodes tints it per colour with [multiply.
	base = rgb("ffffff")
	image = new_image(S, S, base)
	noise = Noise(107)
	for y in range(S):
		for x in range(S):
			weave = 1.0 if (x // 2 + y // 2) % 2 == 0 else 0.90
			image[y][x] = shade(base, weave * (0.94 + 0.10 * noise.at(x, y)))
	return image


def tex_hidden_light() -> Image:
	# Airlike nodes still need an inventory image for the material library.
	image = new_image(S, S, rgb("ffe9a8", 70))
	stroke_rect(image, 0, 0, S - 1, S - 1, rgb("ffd76a", 200))
	draw_text(image, 3, 6, "LT", rgb("6b5a22", 230))
	return image


def tex_seat_side() -> Image:
	base = rgb("6d1326")
	image = new_image(S, S, base)
	for y in range(S):
		for x in range(S):
			image[y][x] = shade(base, 0.82 + 0.26 * (0.5 + 0.5 * math.sin(x * 0.9)))
	fill_rect(image, 0, 0, S - 1, 1, shade(base, 1.30))
	fill_rect(image, 0, S - 3, S - 1, S - 1, rgb("2c2c30"))
	return image


def tex_seat_top() -> Image:
	base = rgb("87182f")
	image = new_image(S, S, base)
	Noise(109).grain(image, 0.08)
	stroke_rect(image, 2, 2, S - 3, S - 3, shade(base, 0.78))
	return image


def tex_aisle_light() -> Image:
	image = new_image(S, S, rgb("26262b"))
	Noise(113).grain(image, 0.06)
	fill_rect(image, 3, 6, S - 4, 9, rgb("ffd98c"))
	fill_rect(image, 5, 7, S - 6, 8, rgb("fff6de"))
	return image


def tex_remote() -> Image:
	image = new_image(S, S)
	body = rgb("2b2f36")
	fill_rect(image, 4, 1, 11, 14, body)
	fill_rect(image, 4, 1, 4, 14, shade(body, 1.25))
	fill_rect(image, 11, 1, 11, 14, shade(body, 0.76))
	fill_rect(image, 5, 3, 10, 5, rgb("9fd7a6"))
	for y in (7, 10):
		for x in (5, 8):
			fill_rect(image, x, y, x + 2, y + 1, rgb("d8a92c"))
	return image


def tex_screen_off() -> Image:
	base = rgb("14161c")
	image = new_image(S, S, base)
	for y in range(S):
		for x in range(S):
			sheen = 1.0 + 0.16 * math.sin((x - y) * 0.4)
			image[y][x] = shade(base, sheen)
	stroke_rect(image, 0, 0, S - 1, S - 1, rgb("0a0b0e"))
	return image


def tex_marquee_frame() -> Image:
	image = new_image(S, S, rgb("2a1f16"))
	Noise(127).grain(image, 0.06)
	stroke_rect(image, 0, 0, S - 1, S - 1, rgb("d8a92c"))
	return image


STATIC_NODE_TEXTURES: dict[str, Callable[[], Image]] = {
	"lw_stone.png": tex_stone,
	"lw_stone_brick.png": tex_stone_brick,
	"lw_polished_stone.png": tex_polished_stone,
	"lw_planks.png": tex_planks,
	"lw_beam_side.png": tex_beam_side,
	"lw_beam_end.png": tex_beam_end,
	"lw_glass.png": tex_glass,
	"lw_bars.png": tex_bars,
	"lw_gold.png": tex_gold,
	"lw_curtain.png": tex_curtain,
	"lw_carpet.png": tex_carpet,
	"lw_column_side.png": tex_column_side,
	"lw_column_top.png": tex_column_top,
	"lw_fence.png": tex_fence,
	"lw_lamp.png": tex_lamp,
	"lw_uplight.png": tex_uplight,
	"lw_pedestal_side.png": tex_pedestal_side,
	"lw_pedestal_top.png": tex_pedestal_top,
	"lw_frame.png": tex_frame,
	"lw_poster.png": tex_poster,
	"lw_stanchion.png": tex_stanchion,
	"lw_grass_top.png": tex_grass_top,
	"lw_grass_side.png": tex_grass_side,
	"lw_dirt.png": tex_dirt,
	"lw_sand.png": tex_sand,
	"lw_paving.png": tex_paving,
	"lw_wool.png": tex_wool,
	"lw_hidden_light.png": tex_hidden_light,
}

THEATER_STATIC_TEXTURES: dict[str, Callable[[], Image]] = {
	"lw_seat_side.png": tex_seat_side,
	"lw_seat_top.png": tex_seat_top,
	"lw_aisle_light.png": tex_aisle_light,
	"lw_remote.png": tex_remote,
	"lw_screen_off.png": tex_screen_off,
	"lw_marquee_frame.png": tex_marquee_frame,
}


# --------------------------------------------------------------------------
# Animated filmstrips
# --------------------------------------------------------------------------


def filmstrip(frames: list[Image]) -> Image:
	strip: Image = []
	for frame in frames:
		strip.extend(frame)
	return strip


WATER_FRAMES = 8


def water_frame(index: int) -> Image:
	base = rgb("2a6cb0", 190)
	image = new_image(S, S, base)
	phase = index / WATER_FRAMES * math.tau
	for y in range(S):
		for x in range(S):
			wave = math.sin(x * 0.7 + phase) + math.sin(y * 0.5 - phase * 1.3)
			image[y][x] = shade(base, 0.86 + 0.16 * (wave + 2) / 4 * 2)
	for x in range(S):
		crest = int((math.sin(x * 0.55 + phase) * 0.5 + 0.5) * (S - 1))
		put(image, x, crest, rgb("bfe2f5", 210))
	return image


TICKER_FRAMES = 16


def ticker_frame(index: int) -> Image:
	"""LED ticker for the kinetic courtyard: a scrolling wave of lit cells."""
	image = new_image(S, S, rgb("0d1512"))
	offset = index
	for cy in range(4):
		for cx in range(4):
			wave = math.sin((cx * 2 + cy + offset) * 0.55)
			level = (wave + 1) / 2
			color = mix(rgb("11301f"), rgb("7ef0a6"), level)
			fill_rect(image, cx * 4 + 1, cy * 4 + 1, cx * 4 + 2, cy * 4 + 2, color)
	return image


MARQUEE_FRAMES = 8


def marquee_frame(index: int) -> Image:
	image = new_image(S, S, rgb("2a1f16"))
	Noise(131).grain(image, 0.06)
	stroke_rect(image, 0, 0, S - 1, S - 1, rgb("8c6a25"))
	bulbs = [(3, 2), (8, 2), (13, 2), (13, 8), (13, 13), (8, 13), (3, 13), (3, 8)]
	for i, (x, y) in enumerate(bulbs):
		lit = (i - index) % len(bulbs) < 3
		color = rgb("fff2c4") if lit else rgb("6b5b33")
		fill_rect(image, x - 1, y - 1, x + 1, y + 1, color)
	return image


# --- Cinema reels ---------------------------------------------------------

SCREEN_COLS = 6
SCREEN_ROWS = 4
CELL = 32
REEL_FRAMES = 16
REEL_W = SCREEN_COLS * CELL
REEL_H = SCREEN_ROWS * CELL


def reel_bars_frame(index: int) -> Image:
	"""Reel 1: broadcast test pattern with a sweeping bar and a ticking counter."""
	image = new_image(REEL_W, REEL_H, rgb("101010"))
	bars = ["c0c0c0", "c0c000", "00c0c0", "00c000", "c000c0", "c00000", "0000c0"]
	band = REEL_H * 2 // 3
	width = REEL_W / len(bars)
	for i, color in enumerate(bars):
		fill_rect(image, int(i * width), 0, int((i + 1) * width) - 1, band - 1, rgb(color))
	# Lower third: a gradient ramp plus the reel label.
	for x in range(REEL_W):
		fill_rect(image, x, band, x, REEL_H - 1,
			mix(rgb("101010"), rgb("e8e8e8"), x / (REEL_W - 1)))
	sweep = int((index / REEL_FRAMES) * REEL_W)
	for dx in range(-3, 4):
		x = (sweep + dx) % REEL_W
		for y in range(REEL_H):
			image[y][x] = mix(image[y][x], rgb("ffffff"), 0.55 - abs(dx) * 0.12)
	label = "TEST PATTERN"
	draw_text(image, (REEL_W - text_width(label, scale=2)) // 2, band + 8, label,
		rgb("101010"), scale=2)
	counter = "{:02d}".format(index)
	draw_text(image, REEL_W - text_width(counter, scale=2) - 6, 6, counter,
		rgb("101010"), scale=2)
	return image


def reel_show_frame(index: int) -> Image:
	"""Reel 2: a short looping animation — sunrise over a voxel skyline."""
	image = new_image(REEL_W, REEL_H, rgb("0b1020"))
	t = index / REEL_FRAMES
	horizon = REEL_H * 3 // 4
	for y in range(horizon):
		sky = mix(rgb("1b2a5c"), rgb("e8a05a"), (y / horizon) ** 1.6)
		sky = mix(sky, rgb("f6cf8d"), 0.35 * math.sin(t * math.tau) ** 2)
		fill_rect(image, 0, y, REEL_W - 1, y, sky)
	# Sun rises and sets across the loop so the clip reads as motion at a glance.
	sun_y = horizon - 6 - int(18 * math.sin(t * math.pi))
	sun_x = int(REEL_W * (0.18 + 0.64 * t))
	fill_disc(image, sun_x, sun_y, 9.0, rgb("ffe7a8"))
	fill_disc(image, sun_x, sun_y, 6.0, rgb("fff8e2"))
	# Parallax hills.
	for layer, (color, height, speed) in enumerate((
			("22405c", 22, 0.5), ("1d5240", 15, 1.0), ("14301f", 9, 1.8))):
		shift = int(t * REEL_W * speed * 0.25)
		for x in range(REEL_W):
			wave = math.sin((x + shift) * 0.08 + layer) + 0.5 * math.sin((x + shift) * 0.21)
			top = horizon - height - int(wave * height * 0.45)
			fill_rect(image, x, max(0, top), x, horizon - 1, rgb(color))
	fill_rect(image, 0, horizon, REEL_W - 1, REEL_H - 1, rgb("0d1a12"))
	# Foreground: a cart trundling along the bottom of the frame.
	cart_x = int((t * 1.2 % 1.0) * (REEL_W + 24)) - 24
	fill_rect(image, cart_x, horizon + 4, cart_x + 17, horizon + 13, rgb("8a4b25"))
	fill_rect(image, cart_x + 2, horizon + 2, cart_x + 15, horizon + 4, rgb("c07c3f"))
	for wheel in (cart_x + 4, cart_x + 13):
		fill_disc(image, wheel, horizon + 15, 2.4, rgb("2c2c30"))
	title = "LUANTI IN YOUR BROWSER"
	draw_text(image, (REEL_W - text_width(title, scale=2)) // 2, 8, title,
		rgb("f2f6ee"), scale=2)
	return image


REELS: dict[str, Callable[[int], Image]] = {
	"bars": reel_bars_frame,
	"show": reel_show_frame,
}


def reel_cell_strips(frame_fn: Callable[[int], Image]) -> dict[tuple[int, int], Image]:
	"""Slice every reel frame into node-sized cells and stack them per cell.

	The theater screen is a wall of ``SCREEN_COLS x SCREEN_ROWS`` nodes. Each
	node owns one cell of the picture and animates through that cell's frames,
	so the wall shows a single large moving image rather than a tiled thumbnail.
	"""
	frames = [frame_fn(i) for i in range(REEL_FRAMES)]
	strips: dict[tuple[int, int], Image] = {}
	for row in range(SCREEN_ROWS):
		for col in range(SCREEN_COLS):
			cell_frames = []
			for frame in frames:
				cell = [frame[row * CELL + y][col * CELL:(col + 1) * CELL]
					for y in range(CELL)]
				cell_frames.append(cell)
			strips[(row, col)] = filmstrip(cell_frames)
	return strips


# --------------------------------------------------------------------------
# Menu art
# --------------------------------------------------------------------------


def menu_background() -> Image:
	width, height = 256, 256
	image = new_image(width, height, rgb("0f1a14"))
	for y in range(height):
		fill_rect(image, 0, y, width - 1, y,
			mix(rgb("13261b"), rgb("070d09"), y / (height - 1)))
	noise = Noise(211)
	for y in range(height):
		for x in range(width):
			if noise.at(x, y) > 0.995:
				image[y][x] = rgb("9fd7a6")
	return image


def menu_header() -> Image:
	width, height = 384, 160
	image = new_image(width, height, rgb("101c15"))
	for y in range(height):
		fill_rect(image, 0, y, width - 1, y,
			mix(rgb("16301f"), rgb("0a140e"), y / (height - 1)))
	# Plaza silhouette: a colonnade along the bottom, the lit theater screen
	# above it on the right, and the wordmark clear of both on the left.
	fill_rect(image, 0, height - 26, width - 1, height - 1, rgb("1d2b22"))
	for x in range(40, width - 40, 44):
		fill_rect(image, x, height - 92, x + 13, height - 27, rgb("cdc8ba"))
		fill_rect(image, x - 3, height - 97, x + 16, height - 92, rgb("e2ddd0"))
	fill_rect(image, 214, 16, 360, 62, rgb("14161c"))
	fill_rect(image, 218, 20, 356, 58, rgb("3f7fa8"))
	for x in range(218, 356, 24):
		fill_rect(image, x, 20, x + 11, 58, rgb("5fa8c9"))
	draw_text(image, 16, 14, "LUANTI WEB", rgb("f2f6ee"), scale=4)
	draw_text(image, 18, 44, "SHOWCASE", rgb("9fd7a6"), scale=2)
	return image


def menu_icon() -> Image:
	size = 128
	image = new_image(size, size, rgb("13261b"))
	for y in range(size):
		fill_rect(image, 0, y, size - 1, y,
			mix(rgb("1b3a26"), rgb("0a140e"), y / (size - 1)))
	fill_rect(image, 18, 30, size - 19, 82, rgb("14161c"))
	fill_rect(image, 22, 34, size - 23, 78, rgb("3f7fa8"))
	for x in range(22, size - 22, 18):
		fill_rect(image, x, 34, x + 8, 78, rgb("5fa8c9"))
	fill_rect(image, 10, 88, size - 11, 96, rgb("cdc8ba"))
	for x in (26, 58, 90):
		fill_rect(image, x, 96, x + 12, size - 12, rgb("8d2436"))
	stroke_rect(image, 0, 0, size - 1, size - 1, rgb("d8a92c"))
	return image


# --------------------------------------------------------------------------
# Shared pixel font for the world builder
# --------------------------------------------------------------------------


def font_lua() -> str:
	"""Emit the 3x5 font as a Lua table.

	lw_world spells the plaza banner and the gallery labels out of wool nodes.
	Exporting the same glyphs the textures use keeps in-world text and baked
	text identical instead of letting two hand-typed copies drift apart.
	"""
	lines = [
		"-- Luanti",
		"-- SPDX-License-Identifier: LGPL-2.1-or-later",
		"-- Copyright (C) 2026 The Luanti Contributors",
		"",
		"-- GENERATED FILE - do not edit.",
		"-- Regenerate with util/content/generate_luanti_web_textures.py.",
		"",
		"-- A 3x5 pixel font. Each glyph is 5 rows of 3 columns, top row first;",
		"-- \"1\" is a set pixel. Shared with the baked textures so the banner in",
		"-- the plaza and the title card on the screen use the same letterforms.",
		"",
		"return {",
		"\tglyph_width = {},".format(GLYPH_W),
		"\tglyph_height = {},".format(GLYPH_H),
		"\tglyphs = {",
	]
	for char in sorted(FONT):
		rows = ", ".join('"{}"'.format(row) for row in FONT[char])
		key = '[" "]' if char == " " else '["{}"]'.format(char)
		lines.append("\t\t{} = {{{}}},".format(key, rows))
	lines.extend(["\t},", "}", ""])
	return "\n".join(lines)


# --------------------------------------------------------------------------
# Driver
# --------------------------------------------------------------------------


def generate(root: pathlib.Path) -> list[pathlib.Path]:
	game = root / "games" / "luanti_web"
	nodes = game / "mods" / "lw_nodes" / "textures"
	theater = game / "mods" / "lw_theater" / "textures"
	written: list[pathlib.Path] = []

	def emit(path: pathlib.Path, image: Image) -> None:
		save_png(path, image)
		written.append(path)

	for name, factory in STATIC_NODE_TEXTURES.items():
		emit(nodes / name, factory())
	emit(nodes / "lw_water.png",
		filmstrip([water_frame(i) for i in range(WATER_FRAMES)]))
	emit(nodes / "lw_ticker.png",
		filmstrip([ticker_frame(i) for i in range(TICKER_FRAMES)]))

	for name, factory in THEATER_STATIC_TEXTURES.items():
		emit(theater / name, factory())
	emit(theater / "lw_marquee.png",
		filmstrip([marquee_frame(i) for i in range(MARQUEE_FRAMES)]))
	for reel, frame_fn in REELS.items():
		for (row, col), strip in reel_cell_strips(frame_fn).items():
			emit(theater / "lw_screen_{}_{}_{}.png".format(reel, row, col), strip)

	font_path = game / "mods" / "lw_world" / "font.lua"
	font_path.parent.mkdir(parents=True, exist_ok=True)
	font_path.write_text(font_lua(), encoding="utf-8")
	written.append(font_path)

	emit(game / "menu" / "background.png", menu_background())
	emit(game / "menu" / "header.png", menu_header())
	emit(game / "menu" / "icon.png", menu_icon())
	return written


def main() -> int:
	parser = argparse.ArgumentParser(description=__doc__,
		formatter_class=argparse.RawDescriptionHelpFormatter)
	parser.add_argument("--root", type=pathlib.Path,
		default=pathlib.Path(__file__).resolve().parents[2],
		help="repository root (default: inferred from this script)")
	parser.add_argument("--quiet", action="store_true")
	args = parser.parse_args()

	written = generate(args.root)
	total = sum(path.stat().st_size for path in written)
	if not args.quiet:
		for path in written:
			print(path.relative_to(args.root))
	print("{} files, {:.1f} KiB".format(len(written), total / 1024))
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
