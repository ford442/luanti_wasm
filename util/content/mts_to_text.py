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
