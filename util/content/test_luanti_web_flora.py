#!/usr/bin/env python3
# Luanti
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 The Luanti Contributors
"""Checks for the luanti_web plant designer (no engine required)."""

from __future__ import annotations

import pathlib
import subprocess
import sys

SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
ROOT = SCRIPT_DIR.parents[1]
MOD = ROOT / "games/luanti_web/mods/lw_flora"


def run_lua() -> None:
	script = SCRIPT_DIR / "test_luanti_web_flora.lua"
	for binary in ("lua5.1", "lua", "luajit"):
		try:
			result = subprocess.run([binary, str(script)], cwd=str(ROOT),
				check=False, capture_output=True, text=True)
		except FileNotFoundError:
			continue
		if result.returncode != 0 or "plant designer checks ok" not in result.stdout:
			sys.stderr.write(result.stdout + result.stderr)
			raise SystemExit(f"{binary} {script.name} failed")
		return
	raise SystemExit("no lua interpreter found")


def check_sources() -> None:
	init = (MOD / "init.lua").read_text(encoding="utf-8")
	core = (ROOT / "games/luanti_web/mods/lw_core/init.lua").read_text(encoding="utf-8")
	if '"lw_flora:designer"' not in core:
		raise SystemExit("lw_flora:designer missing from the starter kit")
	for tex in sorted(set(__import__("re").findall(r"lw_flora_[a-z_]+\.png", init))):
		if not (MOD / "textures" / tex).is_file():
			raise SystemExit(f"missing texture {tex} (run generate_luanti_web_flora.py)")


if __name__ == "__main__":
	run_lua()
	check_sources()
	print("lw_flora checks ok")
