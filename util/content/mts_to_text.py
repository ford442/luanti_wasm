#!/usr/bin/env python3
# Luanti
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 The Luanti Contributors
"""Print a Luanti schematic (.mts) as plain text, one horizontal layer at a time.

An .mts file is a zlib blob, so ``git diff`` on its own only says "binary files
differ". Registered as a textconv driver, this script turns a schematic change
into a diff a reviewer can read:

    git config diff.mts.textconv "python3 util/content/mts_to_text.py"

(``.gitattributes`` already maps ``*.mts`` to the ``mts`` driver.) It also works
on its own:

    python3 util/content/mts_to_text.py games/luanti_web/mods/lw_world/schems/*.mts

Layers are printed bottom up. Inside a layer north (+z) is at the top and east
(+x) to the right, the way a map reads. ``.`` is air, ``_`` is a node the
schematic never places (probability 0), and every other symbol is keyed in the
legend. Non-zero param2 and non-default probabilities are listed after the
layer they belong to, so a rotated seat or a force-placed node is not lost.

Only the standard library is used.
"""

from __future__ import annotations

import string
import struct
import sys
import zlib

SIGNATURE = b"MTSM"
PROB_MASK = 0x7F
PROB_NEVER = 0x00
PROB_ALWAYS = 0x7F
FORCE_PLACE = 0x80

SYMBOLS = string.ascii_letters + string.digits + "#$%&*+-=?@^~<>!:;/|"


class Schematic:
	def __init__(self, size, slice_probs, names, content, param1, param2):
		self.size = size
		self.slice_probs = slice_probs
		self.names = names
		self.content = content
		self.param1 = param1
		self.param2 = param2


def read_mts(blob: bytes) -> Schematic:
	if blob[:4] != SIGNATURE:
		raise ValueError("not an MTS schematic (bad signature)")
	version, sx, sy, sz = struct.unpack(">HHHH", blob[4:12])
	if not 1 <= version <= 4:
		raise ValueError(f"unsupported MTS version {version}")
	offset = 12

	slice_probs = [PROB_ALWAYS] * sy
	if version >= 3:
		slice_probs = list(blob[offset:offset + sy])
		offset += sy

	(count,) = struct.unpack(">H", blob[offset:offset + 2])
	offset += 2
	names = []
	for _ in range(count):
		(length,) = struct.unpack(">H", blob[offset:offset + 2])
		offset += 2
		names.append(blob[offset:offset + length].decode("utf-8"))
		offset += length

	total = sx * sy * sz
	data = zlib.decompress(blob[offset:])
	if len(data) != total * 4:
		raise ValueError(f"node data is {len(data)} bytes, expected {total * 4}")
	content = struct.unpack(f">{total}H", data[:total * 2])
	param1 = data[total * 2:total * 3]
	param2 = data[total * 3:total * 4]
	if version == 1:
		# Version 1 stored no probabilities: every node is always placed.
		param1 = bytes([PROB_ALWAYS]) * total
	return Schematic((sx, sy, sz), slice_probs, names, content, param1, param2)


def node_index(sx: int, sy: int, x: int, y: int, z: int) -> int:
	return z * sy * sx + y * sx + x


def write_mts(schem: Schematic) -> bytes:
	"""Serialize a schematic as MTS version 4."""
	sx, sy, sz = schem.size
	total = sx * sy * sz
	if len(schem.content) != total or len(schem.param1) != total or len(schem.param2) != total:
		raise ValueError("content/param arrays do not match schematic size")
	if len(schem.slice_probs) != sy:
		raise ValueError("slice probability count does not match height")
	header = bytearray(SIGNATURE)
	header += struct.pack(">HHHH", 4, sx, sy, sz)
	header += bytes(p & 0xFF for p in schem.slice_probs)
	header += struct.pack(">H", len(schem.names))
	for name in schem.names:
		encoded = name.encode("utf-8")
		header += struct.pack(">H", len(encoded))
		header += encoded
	body = struct.pack(f">{total}H", *schem.content) + bytes(schem.param1) + bytes(schem.param2)
	return bytes(header) + zlib.compress(body)


# Sentinel for a node the schematic must never place (probability 0).
NEVER = object()


def schematic_from_cells(sx: int, sy: int, sz: int, cells: dict) -> Schematic:
	"""Build a schematic from ``{(x, y, z): value}``.

	A value is a node name, a ``(name, param2)`` pair, or ``NEVER``.

	Missing cells are air. ``NEVER`` writes probability 0 so a later stamp
	leaves whatever is already on the map — the living-building controller
	uses that so swapping frames cannot erase its own timer node. ``param2``
	is what keeps a rotated node rotated: a theater seat saved at facedir 2
	still faces the stage when the map pack stamps it.
	"""
	names = []
	index_of = {}

	def intern(name: str) -> int:
		n = index_of.get(name)
		if n is None:
			n = len(names)
			names.append(name)
			index_of[name] = n
		return n

	air = intern("air")
	total = sx * sy * sz
	content = [air] * total
	param1 = bytearray([PROB_ALWAYS] * total)
	param2 = bytearray(total)
	for (x, y, z), value in cells.items():
		if not (0 <= x < sx and 0 <= y < sy and 0 <= z < sz):
			raise ValueError(f"cell {(x, y, z)} is outside {sx}x{sy}x{sz}")
		i = node_index(sx, sy, x, y, z)
		if value is NEVER:
			param1[i] = PROB_NEVER
		else:
			if isinstance(value, tuple):
				value, param2[i] = value
			content[i] = intern(value)
			param1[i] = PROB_ALWAYS
	return Schematic((sx, sy, sz), [PROB_ALWAYS] * sy, names,
		tuple(content), bytes(param1), bytes(param2))


def to_text(schem: Schematic) -> str:
	sx, sy, sz = schem.size
	used = sorted({c for c in schem.content if c < len(schem.names)},
		key=lambda c: schem.names[c])
	width = 1 if len(used) <= len(SYMBOLS) else 2

	def symbol(n):
		if width == 1:
			return SYMBOLS[n]
		return SYMBOLS[n // len(SYMBOLS)] + SYMBOLS[n % len(SYMBOLS)]

	keys = {}
	legend = []
	for c in used:
		name = schem.names[c]
		if name == "air":
			keys[c] = "." * width
			continue
		keys[c] = symbol(len(legend))
		legend.append(f"  {keys[c]} {name}")

	out = [f"size {sx} {sy} {sz}", "legend:", "  " + "." * width + " air"]
	out += legend

	for y in range(sy):
		prob = schem.slice_probs[y] & PROB_MASK
		header = f"layer y={y}"
		if prob != PROB_ALWAYS:
			header += f" (slice probability {prob}/127)"
		out.append("")
		out.append(header)
		notes = []
		for z in reversed(range(sz)):
			row = []
			for x in range(sx):
				i = z * sy * sx + y * sx + x
				c = schem.content[i]
				p1 = schem.param1[i]
				p2 = schem.param2[i]
				if (p1 & PROB_MASK) == PROB_NEVER:
					row.append("_" * width)
					continue
				row.append(keys.get(c, "?" * width))
				extras = []
				if p2:
					extras.append(f"param2={p2}")
				if (p1 & PROB_MASK) != PROB_ALWAYS:
					extras.append(f"prob={p1 & PROB_MASK}")
				if p1 & FORCE_PLACE:
					extras.append("force")
				if extras:
					name = schem.names[c] if c < len(schem.names) else f"#{c}"
					notes.append(f"  ({x},{y},{z}) {name} " + " ".join(extras))
			out.append("  " + "".join(row))
		out += notes
	return "\n".join(out) + "\n"


def main(argv):
	if len(argv) < 2:
		print(__doc__.strip(), file=sys.stderr)
		return 2
	status = 0
	for path in argv[1:]:
		try:
			with open(path, "rb") as f:
				text = to_text(read_mts(f.read()))
		except (OSError, ValueError, zlib.error, struct.error) as err:
			print(f"{path}: {err}", file=sys.stderr)
			status = 1
			continue
		if len(argv) > 2:
			print(f"== {path}")
		sys.stdout.write(text)
	return status


if __name__ == "__main__":
	try:
		sys.exit(main(sys.argv))
	except BrokenPipeError:
		# `| head` closed the pipe; that is not an error worth a traceback.
		sys.stderr.close()
		sys.exit(0)
