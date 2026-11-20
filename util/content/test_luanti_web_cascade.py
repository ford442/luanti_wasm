#!/usr/bin/env python3
# Luanti
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 The Luanti Contributors
"""Checks for the waterfall cascade's bicycles and gems (no engine required).

    python3 util/content/test_luanti_web_cascade.py

Runs test_luanti_web_cascade.lua (fusing, gems on the ground, racks, a ride
that ends in a breakdown) and checks the media lw_cascade points at is in the
tree and small.
"""

from __future__ import annotations

import pathlib
import re
import subprocess
import sys

SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
ROOT = SCRIPT_DIR.parents[1]
MOD = ROOT / "games/luanti_web/mods/lw_cascade"
LW_MAPS = ROOT / "games/luanti_web/mods/lw_maps"
LW_NODES = ROOT / "games/luanti_web/mods/lw_nodes"


def assert_true(cond: bool, message: str) -> None:
	if not cond:
		raise SystemExit(message)


def test_lua_logic() -> None:
	script = SCRIPT_DIR / "test_luanti_web_cascade.lua"
	last_err = None
	for binary in ("lua5.1", "lua", "luajit"):
		try:
			result = subprocess.run([binary, str(script)], cwd=str(ROOT), check=False,
				capture_output=True, text=True)
		except FileNotFoundError as err:
			last_err = err
			continue
		if result.returncode != 0:
			sys.stderr.write(result.stdout)
			sys.stderr.write(result.stderr)
			raise SystemExit(f"{binary} {script.name} failed")
		assert_true("cascade checks ok" in result.stdout, "lua checks did not print the ok line")
		return
	raise SystemExit(f"no lua interpreter found ({last_err})")


def test_media_is_in_the_tree() -> None:
	"""Every texture and mesh lw_cascade names exists in a mod that ships it."""
	source = "\n".join(path.read_text(encoding="utf-8") for path in MOD.glob("*.lua"))
	media = set(re.findall(r'"(lw_[a-z_]+\.(?:png|obj))', source))
	media |= set(re.findall(r'[\^(](lw_[a-z_]+\.png)', source))
	assert_true(media, "lw_cascade names no media at all")
	shipped = {path.name for folder in (MOD / "textures", MOD / "models",
		LW_MAPS / "textures", LW_NODES / "textures") for path in folder.glob("*")}
	missing = sorted(media - shipped)
	assert_true(not missing, f"lw_cascade uses media nothing ships: {missing}")


def test_media_is_small() -> None:
	"""No large model and no heavy art: the WASM package carries all of it."""
	textures = list((MOD / "textures").glob("*.png"))
	assert_true(len(textures) == 4, f"lw_cascade ships {len(textures)} textures, expected 4")
	art = sum(path.stat().st_size for path in textures)
	assert_true(art < 4 * 1024, f"lw_cascade textures are {art} bytes; budget is 4 KiB")
	model = MOD / "models/lw_bicycle.obj"
	assert_true(model.is_file(), "the bicycle mesh is missing")
	assert_true(model.stat().st_size < 32 * 1024,
		f"the bicycle mesh is {model.stat().st_size} bytes; budget is 32 KiB")
	faces = sum(1 for line in model.read_text().splitlines() if line.startswith("f "))
	assert_true(faces < 400, f"the bicycle has {faces} faces; keep it low-poly")
	assert_true(not list((MOD / "sounds").glob("*")) if (MOD / "sounds").exists() else True,
		"lw_cascade ships no audio")


def test_no_damage_and_nothing_saved_that_should_not_be() -> None:
	source = (MOD / "init.lua").read_text(encoding="utf-8")
	for hurt in ("set_hp", "damage_groups", ":punch("):
		assert_true(hurt not in source, f"lw_cascade must not hurt anyone ({hurt})")
	assert_true(source.count("set_armor_groups({immortal = 1})") == 2,
		"bikes and gems are immortal, so a punch only rides or pushes them")
	bike = source.split('core.register_entity("lw_cascade:bicycle"', 1)[1].split("\n})", 1)[0]
	assert_true("static_save = false" in bike, "a bike must never be saved")


def test_wired_into_the_game() -> None:
	luacheck = (ROOT / "games/luanti_web/.luacheckrc").read_text(encoding="utf-8")
	assert_true('"lw_cascade"' in luacheck, "lw_cascade is not a luacheck global")
	conf = (MOD / "mod.conf").read_text(encoding="utf-8")
	assert_true("name = lw_cascade" in conf and "lw_maps" in conf, "mod.conf is wrong")
	ci = (ROOT / ".github/workflows/lua.yml").read_text(encoding="utf-8")
	assert_true("test_luanti_web_cascade.py" in ci, "CI does not run the cascade checks")


def main() -> int:
	for name, test in sorted(globals().items()):
		if name.startswith("test_") and callable(test):
			test()
			print("ok", name)
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
