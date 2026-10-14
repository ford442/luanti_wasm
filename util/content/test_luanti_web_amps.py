#!/usr/bin/env python3
# Luanti
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 The Luanti Contributors
"""Checks for the stage amps and the songs they play (no engine required)."""

from __future__ import annotations

import pathlib
import re
import struct
import subprocess
import sys

SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
ROOT = SCRIPT_DIR.parents[1]
GAME = ROOT / "games/luanti_web"
AMPS = GAME / "mods/lw_amps"
SOUNDS = AMPS / "sounds"

# The songs are the one large thing in the web pack. The budget in
# wasm_porting.md was raised for them; this keeps them from growing past it
# unnoticed.
SONG_BUDGET = 30 * 1024 * 1024


def assert_true(cond: bool, message: str) -> None:
	if not cond:
		raise SystemExit(message)


def test_lua_logic() -> None:
	script = SCRIPT_DIR / "test_luanti_web_amps.lua"
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
		assert_true("stage amp checks ok" in result.stdout,
			"lua checks did not print the ok line")
		return
	raise SystemExit(f"no lua interpreter found ({last_err})")


def registered_songs() -> dict[str, float]:
	"""Song name -> length, read out of lw_amps/init.lua."""
	text = (AMPS / "init.lua").read_text(encoding="utf-8")
	songs = {name: float(length) for name, length in
		re.findall(r'\{"([a-z0-9_]+)",\s*([0-9.]+),', text)}
	assert_true(songs, "no songs found in lw_amps/init.lua")
	return songs


def vorbis_info(path: pathlib.Path) -> tuple[int, int, float]:
	"""(channels, sample rate, duration) from the Ogg/Vorbis headers."""
	data = path.read_bytes()
	assert_true(data[:4] == b"OggS", f"{path.name} is not an Ogg bitstream")
	ident = data.find(b"\x01vorbis")
	assert_true(0 <= ident < 256, f"{path.name} is not Vorbis")
	channels = data[ident + 11]
	rate = struct.unpack_from("<I", data, ident + 12)[0]
	# The last page's granule position is the sample count of the stream.
	last = data.rfind(b"OggS")
	granule = struct.unpack_from("<q", data, last + 6)[0]
	return channels, rate, granule / rate


def test_song_files() -> None:
	songs = registered_songs()
	total = 0
	expected = set()
	for name, length in songs.items():
		pair = []
		for side in ("l", "r"):
			path = SOUNDS / f"lw_amps_{name}_{side}.ogg"
			expected.add(path.name)
			assert_true(path.is_file(), f"missing {path.relative_to(ROOT)}")
			channels, rate, duration = vorbis_info(path)
			# Luanti only places a mono sound in the world; a stereo file
			# would play with no position at all.
			assert_true(channels == 1, f"{path.name} has {channels} channels, not 1")
			assert_true(rate == 44100, f"{path.name} is {rate} Hz, not 44100")
			assert_true(abs(duration - length) < 0.01,
				f"{path.name} lasts {duration:.3f}s but is registered as {length}s")
			pair.append(path.stat().st_size)
			total += path.stat().st_size
		# Not identical: the two channels are different signals. Similar,
		# though, or one side is a different cut of the song.
		assert_true(abs(pair[0] - pair[1]) <= 0.05 * max(pair),
			f"the {name} pair differs in size by more than 5%")
	extra = {p.name for p in SOUNDS.glob("*.ogg")} - expected
	assert_true(not extra, f"unregistered sound files: {sorted(extra)}")
	assert_true(total <= SONG_BUDGET,
		f"the songs are {total / 2**20:.1f} MiB; the budget is {SONG_BUDGET / 2**20:.0f} MiB")
	assert_true((SOUNDS / "README.md").is_file(), "lw_amps/sounds has no README")


def test_routine_follows_the_songs() -> None:
	"""The Around dance map names only songs the amps can play."""
	songs = registered_songs()
	text = (GAME / "routines/lace_waterfall_around.lua").read_text(encoding="utf-8")
	block = re.search(r"songs\s*=\s*\{(.*?)\}", text, re.S)
	assert_true(block is not None, "the Around routine names no songs")
	named = re.findall(r'"([a-z0-9_]+)"', block.group(1))
	assert_true(named, "the Around routine's song list is empty")
	for name in named:
		assert_true(name in songs, f"the Around routine names {name}, which lw_amps lacks")
	assert_true("bpm = 175" in text, "the Around routine is not at 175 bpm")


def main() -> int:
	test_lua_logic()
	test_song_files()
	test_routine_follows_the_songs()
	print("stage amp checks ok")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
