#!/usr/bin/env python3
# Luanti
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 The Luanti Contributors
"""WebGL context creation and loss handling in the generated client.

Scenarios (each loads the game into a world):

* ``lose``: after the first frames, force ``WEBGL_lose_context.loseContext()``.
  The page must show the recoverable overlay, keep the engine responsive (no
  page errors, no crash), flush persistence, and the reload button must bring
  the launcher back. The context then comes back with ``?glrestore=fail`` (in
  proxy mode the page restores it; in offscreen mode the engine replaces it),
  so the engine's rebuild fails on purpose and the overlay must stay with its
  reload button: the fallback for a failed restore.
* ``restore``: lose the context and get it back (proxy: the page restores it;
  offscreen: the engine puts a new context in its place on its worker), and
  the engine must rebuild its GL resources in place: the overlay goes away
  without a reload, the world is drawn again, frames keep coming, a dig
  reaches the server, and the world saved before the loss is still there.
* ``webgl1``: ``?webgl=1`` forces the WebGL1 fallback; the engine must still
  reach the world and report a version-1 context.
* ``render``: the render mode actually chosen matches ``--render``, the canvas
  shows a rendered world (not a blank or single-colour frame), frames keep
  coming after the viewport is resized and the engine's backing store follows
  the new size, and pointer lock engages on a click.

``--render proxy|offscreen|auto`` runs every scenario in that render mode
(``?render=``); without it the build default is used. In offscreen mode the
context is lost through the engine (the page cannot reach it). It is never
restored, because the worker never runs the event that would allow it; the
engine replaces it with a new context on the same worker instead
(``CIrrDeviceSDL::restoreAfterContextLoss()``).

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
import test_first_playable as playable

BASE_QUERY = "?game=devtest&view=60&name=Gl_Player&autostart=1"


def format_page_error(error: object) -> str:
	return str(getattr(error, "stack", None) or error)


def open_game(browser: Browser, base: str, extra: str,
		console: list[str], errors: list[str], seed_config: bool = False) -> Page:
	page = browser.new_page(viewport={"width": 1280, "height": 720})
	page.on("console", lambda m: console.append(f"{m.type}: {m.text}"))
	page.on("pageerror", lambda e: errors.append(format_page_error(e)))
	if seed_config:
		# give/interact privileges for the dig, as test_first_playable.py
		# does: read once at startup, applied when the player is created.
		page.goto(base + "/luanti.html?game=devtest" + extra,
			wait_until="domcontentloaded", timeout=60_000)
		playable.wait_for_launcher(page)
		page.evaluate("text => FS.writeFile('%s', text)" % playable.CONFIG,
			playable.CONFIG_TEXT)
		playable.sync_filesystem(page)
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


def scenario_lose(browser: Browser, base: str, extra: str) -> None:
	console: list[str] = []
	errors: list[str] = []
	page = open_game(browser, base, extra + "&glrestore=fail", console, errors)
	try:
		info = page.evaluate("Module.luantiWebGLInfo")
		assert info and info["version"] in (1, 2), info
		page.wait_for_timeout(2000)

		page.evaluate("""() => {
			window.glTicks = 0;
			setInterval(() => window.glTicks++, 20);
		}""")
		offscreen = info.get("render") == "offscreen"
		lost = page.evaluate("Module.luantiLauncher.debugLoseContext()")
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

		# Get the context back with a rebuild that fails (?glrestore=fail):
		# the overlay must stay and keep its reload button. Proxy: the page
		# restores the context. Offscreen: the engine replaces it on its own.
		if not offscreen:
			page.evaluate("window.luantiLoseContextExt.restoreContext()")
		page.wait_for_function(
			"Module.luantiLauncher.getGLState().restoreFailed >= 1", timeout=30_000)
		assert any("WebGL context restore failed" in line for line in console), console[-30:]
		if offscreen:
			assert any("WebGL context replaced on the render worker" in line
				for line in console), console[-30:]
		assert not page.is_disabled("#luanti-gl-lost-reload")
		assert page.is_visible("#luanti-gl-lost")
		assert page.evaluate("Module.luantiLauncher.getGLState().recovered") == 0
		assert not errors, {"pageErrors": errors, "console": console[-30:]}
		assert any("WebGL context lost" in line for line in console), console[-30:]

		# The button reloads the page. Wait for the navigation itself, or the
		# check below can still see the old page; a marker on the old window
		# proves it is gone (?autostart=1 restarts the game, so "started" says
		# nothing).
		page.evaluate("window.luantiBeforeReload = true")
		with page.expect_navigation(timeout=120_000):
			page.click("#luanti-gl-lost-reload")
		page.wait_for_function(
			"Module.luantiLauncher?.getState().runtimeReady === true",
			timeout=120_000)
		assert not page.evaluate("window.luantiBeforeReload === true")
		print("context loss: overlay, responsiveness and reload passed")
	finally:
		page.close()


def world_files(page: Page) -> dict:
	"""What the world on disk looks like: world.mt and the two databases.

	The databases of a world on OPFS (client/web/storage.js) are read from
	OPFS, as test_first_playable.read_stored() does; everything else from
	the Emscripten FS."""
	return page.evaluate("""async world => {
		const storage = Module.luantiStorage;
		const id = storage ? storage.readMarker(world) : null;
		const root = id ? await (await navigator.storage.getDirectory())
			.getDirectoryHandle(storage.opfsRoot) : null;
		const read = async path => {
			const name = path.slice(path.lastIndexOf("/") + 1);
			if (root && /\\.sqlite$/.test(name)) {
				try {
					const file = await (await (await root.getDirectoryHandle(id))
						.getFileHandle(name)).getFile();
					return new Uint8Array(await file.arrayBuffer());
				} catch (e) {
					return null;
				}
			}
			return FS.analyzePath(path).exists ? FS.readFile(path) : null;
		};
		const hash = async bytes => bytes ? Array.from(new Uint8Array(
			await crypto.subtle.digest("SHA-256", bytes)),
			b => b.toString(16).padStart(2, "0")).join("") : null;
		const header = bytes => bytes ?
			new TextDecoder().decode(bytes.subarray(0, 15)) : null;
		const map = await read(world + "/map.sqlite");
		const players = await read(world + "/players.sqlite");
		return {
			storage: id ? "opfs" : "fs",
			worldMt: await hash(await read(world + "/world.mt")),
			mapHeader: header(map),
			mapSize: map ? map.length : 0,
			playersHeader: header(players)
		};
	}""", f"{playable.WORLDS}/devtest")


def scenario_restore(browser: Browser, base: str, extra: str,
		screenshots: Path | None) -> None:
	console: list[str] = []
	errors: list[str] = []
	page = open_game(browser, base, extra, console, errors, seed_config=True)
	try:
		info = page.evaluate("Module.luantiWebGLInfo")
		offscreen = info.get("render") == "offscreen"
		page.wait_for_timeout(4000)
		before_colours = canvas_colours(page)
		assert before_colours >= 8, f"canvas blank before the loss ({before_colours})"
		if screenshots:
			page.screenshot(path=str(screenshots / "restore-before.png"))
		playable.sync_filesystem(page)
		saved = world_files(page)
		assert saved["mapHeader"] == "SQLite format 3", saved

		start = len(console)
		assert page.evaluate("Module.luantiLauncher.debugLoseContext()")
		page.wait_for_function(
			"Module.luantiLauncher.getGLState().lost >= 1", timeout=10_000)
		if not offscreen:
			# The engine replaces an offscreen context by itself, possibly
			# before the overlay could be seen here.
			page.wait_for_selector("#luanti-gl-lost", state="visible", timeout=10_000)
			page.wait_for_timeout(1000)
			page.evaluate("window.luantiLoseContextExt.restoreContext()")
		page.wait_for_function(
			"Module.luantiLauncher.getGLState().recovered >= 1", timeout=60_000)
		page.wait_for_selector("#luanti-gl-lost", state="hidden", timeout=10_000)
		state = page.evaluate("Module.luantiLauncher.getGLState()")
		assert state["lost"] == 1 and state["restoreFailed"] == 0, state
		assert not any("WebGL context restore failed" in line
			for line in console[start:]), console[-40:]
		if offscreen:
			assert any("WebGL context replaced on the render worker" in line
				for line in console[start:]), console[-40:]
		after_info = page.evaluate("Module.luantiWebGLInfo")
		assert after_info["render"] == info["render"], (info, after_info)
		# Rebuilt before any frame is drawn on the revived context: a frame
		# drawn with the dead objects shows up as WebGL INVALID_OPERATION
		# warnings (and enough of them make Chrome stop reporting errors).
		recovered_at = len(console)
		stale_marks = ("does not belong to this context", "not from the associated program",
			"no texture bound", "no valid shader program")

		# The world is drawn again, and keeps being drawn.
		frames = page.evaluate("Module.luantiPerf.cursor()")
		page.wait_for_timeout(3000)
		assert page.evaluate("Module.luantiPerf.cursor()") > frames, "no frames after restore"
		after_colours = canvas_colours(page)
		if screenshots:
			page.screenshot(path=str(screenshots / "restore-after.png"))
		assert after_colours >= max(8, before_colours // 2), \
			f"canvas after restore has {after_colours} colours, {before_colours} before"

		stale_before = [line for line in console[start:recovered_at]
			if any(mark in line for mark in stale_marks)]
		stale_after = [line for line in console[recovered_at:]
			if any(mark in line for mark in stale_marks)]
		print(f"context restore ({info['render']}): {before_colours} -> {after_colours} colours, no reload; "
			f"stale-object GL warnings: {len(stale_before)} until recovered, "
			f"{len(stale_after)} after")
		assert not stale_before and not stale_after, (stale_before + stale_after)[:12]

		# Nothing reloaded the page, and the world saved before the loss is
		# still there.
		assert page.evaluate("Module.luantiLauncher.getState().started")
		playable.sync_filesystem(page)
		now = world_files(page)
		assert now["worldMt"] == saved["worldMt"], (saved, now)
		assert now["mapHeader"] == "SQLite format 3" and now["mapSize"] >= saved["mapSize"], (saved, now)
		assert now["playersHeader"] == "SQLite format 3", now
		print("context restore: saved world intact, page not reloaded")

		# The same session still plays: a dig the server logs.
		playable.grab_pointer(page)
		playable.send_chat(page, console, "/clearinv", "clears singleplayer's inventory")
		playable.send_chat(page, console, f"/giveme {playable.PLACE_ITEMS['devtest']} 10")
		playable.send_chat(page, console, f"/giveme {playable.DIG_ITEMS['devtest']}")
		# The engine drops the first camera movement after the window
		# becomes active (Game::updateCameraDirection), and dig_nodes()
		# pitches the view down with a single movement; without these turns
		# the player can stay looking at the horizon, out of reach of
		# anything to dig, with or without a context loss before. The pitch
		# clamps at straight down, so extra turns do no harm.
		# test_first_playable.py's placing step turns before its dig too.
		for _ in range(3):
			playable.look(page, 0, 40)
		dig_start = len(console)
		dug = playable.dig_nodes(page, console)
		# Proxy mode starves the internal server on SwiftShader (steps lag by
		# tens of seconds; docs/wasm-issues/06-first-playable-gate-results.md),
		# so its log can trail the clicks well past dig_nodes()' own wait.
		deadline = time.monotonic() + 120
		while not dug and time.monotonic() < deadline:
			page.wait_for_timeout(1000)
			dug = playable.count(console, dig_start, "digs ")
		assert dug >= 1, "no dig reached the server after the restore"

		assert not errors, {"pageErrors": errors, "console": console[-30:]}
		print(f"context restore: dug {dug} after the restore")
	finally:
		page.close()


def scenario_webgl1(browser: Browser, base: str, extra: str) -> None:
	console: list[str] = []
	errors: list[str] = []
	page = open_game(browser, base, "&webgl=1" + extra, console, errors)
	try:
		info = page.evaluate("Module.luantiWebGLInfo")
		assert info and info["version"] == 1, info
		page.wait_for_timeout(3000)
		assert not errors, {"pageErrors": errors, "console": console[-30:]}
		print("WebGL1 fallback passed:", info)
	finally:
		page.close()


# Distinct colours in a coarse sample of the canvas, read from a screenshot so
# it works whichever thread owns the context. A blank or uniformly cleared
# frame has one or two.
def canvas_colours(page: Page) -> int:
	png = page.locator("#canvas").screenshot()
	return page.evaluate("""async bytes => {
		const blob = new Blob([new Uint8Array(bytes)], {type: "image/png"});
		const bitmap = await createImageBitmap(blob);
		const c = new OffscreenCanvas(64, 36);
		const g = c.getContext("2d");
		g.drawImage(bitmap, 0, 0, 64, 36);
		const data = g.getImageData(0, 0, 64, 36).data;
		const seen = new Set();
		for (let i = 0; i < data.length; i += 4)
			seen.add((data[i] >> 4) << 8 | (data[i + 1] >> 4) << 4 | data[i + 2] >> 4);
		return seen.size;
	}""", list(png))


def scenario_render(browser: Browser, base: str, extra: str,
		expected: str | None, screenshots: Path | None) -> None:
	console: list[str] = []
	errors: list[str] = []
	page = open_game(browser, base, extra, console, errors)
	try:
		info = page.evaluate("Module.luantiWebGLInfo")
		assert info and info.get("render") in ("proxy", "offscreen"), info
		if expected:
			assert info["render"] == expected, info
		page.wait_for_timeout(3000)
		colours = canvas_colours(page)
		assert colours >= 8, f"canvas looks blank ({colours} colours): {info}"
		if screenshots:
			page.screenshot(path=str(screenshots / f"render-{info['render']}.png"))

		# Resize: frames keep coming and the backing store follows the box.
		page.set_viewport_size({"width": 960, "height": 600})
		page.wait_for_function("""() => {
			const c = Module.canvas;
			return Math.abs(c.width - c.clientWidth) <= 1 &&
				Math.abs(c.height - c.clientHeight) <= 1 && c.clientWidth < 1000;
		}""", timeout=30_000)
		before = page.evaluate("Module.luantiPerf.cursor()")
		page.wait_for_timeout(3000)
		after = page.evaluate("Module.luantiPerf.cursor()")
		assert after > before, f"no frames after resize ({before} -> {after})"
		size = page.evaluate("[Module.canvas.width, Module.canvas.height]")
		assert canvas_colours(page) >= 8, "canvas blank after resize"

		page.click("#canvas", position={"x": 480, "y": 300})
		page.wait_for_function(
			"document.pointerLockElement === Module.canvas", timeout=30_000)
		assert not errors, {"pageErrors": errors, "console": console[-30:]}
		print(f"render mode {info['render']}: {colours} colours, "
			f"{after - before} frames after resize to {size}, pointer lock ok")
	finally:
		page.close()


def main() -> int:
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument("--browser", default=shutil.which("google-chrome"))
	parser.add_argument("--build", default="build-wasm")
	parser.add_argument("--scenario", choices=["lose", "restore", "webgl1", "render", "all"],
		default="all")
	parser.add_argument("--screenshot-dir",
		help="save the render scenario's frame here")
	parser.add_argument("--render", choices=["proxy", "offscreen", "auto"],
		help="render mode for every scenario (default: the build default)")
	args = parser.parse_args()
	if not args.browser:
		parser.error("Google Chrome was not found")

	repo = Path(__file__).resolve().parents[2]
	output = (repo / args.build / "bin").resolve()
	if not (output / "luanti.html").exists():
		parser.error(f"generated client not found under {output}")

	screenshots = Path(args.screenshot_dir) if args.screenshot_dir else None
	if screenshots:
		screenshots.mkdir(parents=True, exist_ok=True)

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
				extra = f"&render={args.render}" if args.render else ""
				# "auto" may legitimately pick either mode.
				expected = args.render if args.render != "auto" else None
				if args.scenario in ("render", "all"):
					scenario_render(browser, base, extra, expected, screenshots)
				if args.scenario in ("lose", "all"):
					scenario_lose(browser, base, extra)
				if args.scenario in ("restore", "all"):
					scenario_restore(browser, base, extra, screenshots)
				if args.scenario in ("webgl1", "all"):
					scenario_webgl1(browser, base, extra)
				browser.close()
		finally:
			server.shutdown()
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
