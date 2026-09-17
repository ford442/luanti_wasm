#!/usr/bin/env python3
# Luanti
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 The Luanti Contributors
"""Checks for the luanti_web authoring toolkit (no engine required)."""

from __future__ import annotations

import pathlib
import subprocess
import sys

SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
ROOT = SCRIPT_DIR.parents[1]
if str(SCRIPT_DIR) not in sys.path:
	sys.path.insert(0, str(SCRIPT_DIR))

from mts_to_text import read_mts


def assert_true(cond: bool, message: str) -> None:
	if not cond:
		raise SystemExit(message)


def test_lua_logic() -> None:
	script = SCRIPT_DIR / "test_luanti_web_tools.lua"
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
		assert_true("authoring tools checks ok" in result.stdout,
			"lua checks did not print the ok line")
		return
	raise SystemExit(f"no lua interpreter found ({last_err})")


def test_kit_and_hook_in_source() -> None:
	core = (ROOT / "games/luanti_web/mods/lw_core/init.lua").read_text(encoding="utf-8")
	for item in (
		"lw_tools:param2",
		"lw_tools:paint",
		"lw_tools:clone",
		"lw_tools:light_wand",
		"lw_theater:remote",
		"lw_tools:stamp",
	):
		assert_true(item in core, f"starter kit missing {item}")
	assert_true("give_initial_stuff" in core, "give_initial_stuff alias missing")
	assert_true('register_chatcommand("stuff"' in core, "/stuff missing")

	tools = (ROOT / "games/luanti_web/mods/lw_tools/init.lua").read_text(encoding="utf-8")
	assert_true("tool_capabilities" not in tools, "tools must not have durability")
	assert_true("register_craftitem" in tools, "tools should be craftitems, not worn tools")

	theater = (ROOT / "games/luanti_web/mods/lw_theater/init.lua").read_text(encoding="utf-8")
	assert_true("function lw_theater.on_remote" in theater, "remote hook missing")
	assert_true("The Screen Remote does nothing until the theater is loaded."
		in theater, "remote no-op hint missing")
	assert_true('lw_theater.REMOTE_ACTIONS' in theater, "remote action list missing")

	logic = (ROOT / "games/luanti_web/mods/lw_tools/logic.lua").read_text(encoding="utf-8")
	assert_true("MAX_CLONE_VOLUME = 32 * 32 * 32" in logic, "32³ cap missing")


def test_textures_exist() -> None:
	folder = ROOT / "games/luanti_web/mods/lw_tools/textures"
	for name in ("lw_param2.png", "lw_paint.png", "lw_clone.png",
			"lw_light_wand.png", "lw_stamp.png"):
		path = folder / name
		assert_true(path.is_file() and path.stat().st_size > 0, f"missing {name}")


def test_column_stamp_matches_plaza_column() -> None:
	"""The stamp's column must stay a one-click plaza_column, not a new design."""
	schem = read_mts(
		(ROOT / "games/luanti_web/mods/lw_world/schems/plaza_column.mts").read_bytes())
	assert_true(schem.size == (1, 6, 1), "plaza_column size drifted")
	# y=0..3 column, y=4 gold, y=5 lamp — same as lw_tools.stamp_nodes("column").
	expected = (
		"lw_nodes:column",
		"lw_nodes:column",
		"lw_nodes:column",
		"lw_nodes:column",
		"lw_nodes:gold_trim",
		"lw_nodes:lamp",
	)
	for y, name in enumerate(expected):
		content = schem.content[y]  # x=0,z=0, index = y * sx = y
		assert_true(schem.names[content] == name,
			f"plaza_column y={y} is {schem.names[content]}, stamp expects {name}")


def main() -> int:
	test_lua_logic()
	test_kit_and_hook_in_source()
	test_textures_exist()
	test_column_stamp_matches_plaza_column()
	print("authoring tools checks ok")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
