#!/usr/bin/env python3
# Luanti
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 The Luanti Contributors
"""WebGL context creation and loss handling in the generated client.

Scenarios (each loads the game into a world):

* ``lose``: after the first frames, force ``WEBGL_lose_context.loseContext()``.
  The page must show the recoverable overlay, keep the engine responsive (no
  page errors, no crash), flush persistence, and the reload button must bring
  the launcher back.
* ``webgl1``: ``?webgl=1`` forces the WebGL1 fallback; the engine must still
  reach the world and report a version-1 context.

Run after a WASM build::

	python3 util/wasm/test_webgl_context.py --browser "$(command -v google-chrome)"
"""

from __future__ import annotations

import argparse
from pathlib import Path
import shutil
import threading
import time

from playwright.sync_api import Browser, Page, sync_playwright

from serve import create_server

BASE_QUERY = "?game=devtest&view=60&name=Gl_Player&autostart=1"


def format_page_error(error: object) -> str:
	return str(getattr(error, "stack", None) or error)


def open_game(browser: Browser, base: str, extra: str,
		console: list[str], errors: list[str]) -> Page:
	page = browser.new_page(viewport={"width": 1280, "height": 720})
	page.on("console", lambda m: console.append(f"{m.type}: {m.text}"))
	page.on("pageerror", lambda e: errors.append(format_page_error(e)))
	page.goto(base + "/luanti.html" + BASE_QUERY + extra,
		wait_until="domcontentloaded", timeout=60_000)
	page.wait_for_function(
		"Module.luantiLauncher?.getState().phase === 'playing'", timeout=300_000)
	deadline = time.monotonic() + 300
	while time.monotonic() < deadline:
		if any("World ready; entering game loop" in line for line in console):
			return page
		page.wait_for_timeout(500)
	raise AssertionError("the engine never reported a ready world")


def scenario_lose(browser: Browser, base: str) -> None:
	console: list[str] = []
	errors: list[str] = []
	page = open_game(browser, base, "", console, errors)
	try:
		info = page.evaluate("Module.luantiWebGLInfo")
		assert info and info["version"] in (1, 2), info
		page.wait_for_timeout(2000)

		ticks_before = page.evaluate("""() => {
			window.glTicks = 0;
			setInterval(() => window.glTicks++, 20);
			return 0;
		}""")
		lost = page.evaluate("""() => {
			const gl = Module.canvas.getContext("webgl2") ||
				Module.canvas.getContext("webgl");
			const ext = gl && gl.getExtension("WEBGL_lose_context");
			if (!ext) return false;
			ext.loseContext();
			window.glExt = ext;
			return true;
		}""")
		assert lost, "WEBGL_lose_context is unavailable"

		page.wait_for_selector("#luanti-gl-lost", state="visible", timeout=10_000)
		# Persistence flush enables the reload button.
		page.wait_for_function(
			"!document.getElementById('luanti-gl-lost-reload').disabled",
			timeout=60_000)
		assert page.evaluate("Module.luantiLauncher.getGLState().lost") == 1

		# The page must stay responsive while the context is gone.
		page.wait_for_timeout(1500)
		ticks = page.evaluate("window.glTicks")
		assert ticks >= 20, ticks

		# Restore: the overlay must stay (stale GL state) and say so.
		page.evaluate("window.glExt.restoreContext()")
		page.wait_for_function(
			"Module.luantiLauncher.getGLState().restored >= 1", timeout=10_000)
		assert page.is_visible("#luanti-gl-lost")
		assert not errors, {"pageErrors": errors, "console": console[-30:]}
		assert any("WebGL context lost" in line for line in console), console[-30:]

		page.click("#luanti-gl-lost-reload")
		page.wait_for_function(
			"Module.luantiLauncher?.getState().runtimeReady === true",
			timeout=120_000)
		assert not page.evaluate("Module.luantiLauncher.getState().started")
		print("context loss: overlay, responsiveness and reload passed")
	finally:
		page.close()


def scenario_webgl1(browser: Browser, base: str) -> None:
	console: list[str] = []
	errors: list[str] = []
	page = open_game(browser, base, "&webgl=1", console, errors)
	try:
		info = page.evaluate("Module.luantiWebGLInfo")
		assert info and info["version"] == 1, info
		page.wait_for_timeout(3000)
		assert not errors, {"pageErrors": errors, "console": console[-30:]}
		print("WebGL1 fallback passed:", info)
	finally:
		page.close()


def main() -> int:
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument("--browser", default=shutil.which("google-chrome"))
	parser.add_argument("--build", default="build-wasm")
	parser.add_argument("--scenario", choices=["lose", "webgl1", "all"], default="all")
	args = parser.parse_args()
	if not args.browser:
		parser.error("Google Chrome was not found")

	repo = Path(__file__).resolve().parents[2]
	output = (repo / args.build / "bin").resolve()
	if not (output / "luanti.html").exists():
		parser.error(f"generated client not found under {output}")

	with create_server(output, "127.0.0.1", 0, quiet=True) as server:
		threading.Thread(target=server.serve_forever, daemon=True).start()
		base = f"http://127.0.0.1:{server.server_address[1]}"
		try:
			with sync_playwright() as playwright:
				browser = playwright.chromium.launch(
					headless=True, executable_path=args.browser,
					args=["--no-sandbox", "--enable-features=SharedArrayBuffer",
						"--use-gl=angle", "--use-angle=swiftshader",
						"--enable-unsafe-swiftshader"])
				if args.scenario in ("lose", "all"):
					scenario_lose(browser, base)
				if args.scenario in ("webgl1", "all"):
					scenario_webgl1(browser, base)
				browser.close()
		finally:
			server.shutdown()
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
