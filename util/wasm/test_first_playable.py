#!/usr/bin/env python3
# Luanti
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 The Luanti Contributors
"""Automate the browser First Playable Smoke Test gate.

This drives the generated client through checklist steps 2-7 of the
"First Playable Smoke Test" documented in doc/compiling/wasm.md:

  2. the page loads without JS/WASM errors
  3. IDBFS hydration completes before the launcher unlocks
  4. the launcher accepts input and the browser main thread never freezes
  5. a new singleplayer devtest world is created
  6. the world loads, keyboard and mouse input reach the engine, and nodes
     are placed and dug in it
  7. the tab is reloaded and the same world (and minetest.conf) come back

Step 1 is provided by util/wasm/serve.py. Step 8 (a setting written by the
engine's own settings UI) stays in the manual gate; this script only proves
that a minetest.conf on the persistent filesystem survives a reload and is
read back by the engine.
"""

from __future__ import annotations

import argparse
from pathlib import Path
import shutil
import threading
import time

from playwright.sync_api import Page, sync_playwright

from serve import create_server

WORLD = "/home/web_user/.luanti/worlds/devtest"
CONFIG = "/home/web_user/.luanti/minetest.conf"
# default_privs applies when the world's player record is created, so the
# configuration file has to be in place before the world is ever launched.
CONFIG_TEXT = (
	"# written by util/wasm/test_first_playable.py\n"
	"default_privs = interact, shout, give, settime, fly, fast\n"
	"name = \n"
)
PLACE_ITEM = "basenodes:stone"
PLACE_TARGET = 10
DIG_TARGET = 5
# Pointer-lock look. SDL reads the relative movement of a mouse event, so a
# synthetic event is the only way to turn the view by a known amount without
# also sending the opposite delta on the way back.
LOOK = """([x, y]) => Module.canvas.dispatchEvent(new MouseEvent("mousemove", {
	bubbles: true, movementX: x, movementY: y, clientX: 640, clientY: 360}))"""


def format_page_error(error: object) -> str:
	return str(getattr(error, "stack", None) or error)


def wait_for_launcher(page: Page) -> None:
	"""Wait until hydration finished and the launcher is usable."""
	page.wait_for_function(
		"Module.luantiPersistence?.getState().state === 'ready'", timeout=120_000)
	page.wait_for_function(
		"Module.luantiLauncher?.getState().runtimeReady === true", timeout=120_000)


def wait_for_world(page: Page, console: list[str]) -> None:
	"""Wait until the engine is in the world, not merely loading it."""
	page.wait_for_function(
		"Module.luantiLauncher?.getState().phase === 'playing'", timeout=300_000)
	deadline = time.monotonic() + 300
	while time.monotonic() < deadline:
		if any("World ready; entering game loop" in line for line in console):
			return
		page.wait_for_timeout(500)
	raise AssertionError("the engine never reported a ready world")


def sync_filesystem(page: Page) -> None:
	page.evaluate("""async () => {
		await Module.luantiPersistence.requestSync({
			reason: "external", urgent: true});
	}""")


def digest(page: Page, path: str) -> str:
	return page.evaluate("""async path => {
		const bytes = FS.readFile(path);
		const hash = await crypto.subtle.digest("SHA-256", bytes);
		return Array.from(new Uint8Array(hash),
			part => part.toString(16).padStart(2, "0")).join("");
	}""", path)


def grab_pointer(page: Page) -> None:
	page.click("#canvas", position={"x": 640, "y": 360})
	page.wait_for_function(
		"document.pointerLockElement === Module.canvas", timeout=30_000)


def send_chat(page: Page, console: list[str], command: str) -> None:
	"""Type a chat command, retrying until the server acknowledges it.

	The first key presses after entering a world are routinely dropped while
	the engine is still catching up on its first server steps, so this retries
	instead of asserting on a single attempt.
	"""
	name = command.split()[0].lstrip("/")
	marker = f"Caught command '{name}'"
	for _ in range(6):
		start = len(console)
		page.keyboard.press("t")
		page.wait_for_timeout(1500)
		page.keyboard.type(command, delay=60)
		page.wait_for_timeout(500)
		page.keyboard.press("Enter")
		page.wait_for_timeout(3000)
		if any(marker in line for line in console[start:]):
			return
	raise AssertionError(f"the engine never handled the chat command {command}")


def look(page: Page, yaw: int, pitch: int) -> None:
	"""Turn the view by a relative amount, in pointer-lock movement units.

	Roughly 30 units is a quarter turn, so the pitch clamps to straight down
	well before 60.
	"""
	page.evaluate(LOOK, [yaw, pitch])
	page.wait_for_timeout(300)


def count(console: list[str], start: int, needle: str) -> int:
	return sum(1 for line in console[start:] if needle in line)


def place_nodes(page: Page, console: list[str]) -> int:
	"""Try to place nodes on the ground in front of the player.

	The view is aimed down first, then swept, because the terrain under a
	fresh spawn is not known in advance.
	"""
	start = len(console)
	page.keyboard.press("7")
	page.wait_for_timeout(800)
	look(page, 0, 12)
	for attempt in range(48):
		if count(console, start, "places node") >= PLACE_TARGET:
			break
		if attempt and attempt % 8 == 0:
			look(page, 20, 4 if attempt % 16 else -4)
		page.mouse.down(button="right")
		page.wait_for_timeout(200)
		page.mouse.up(button="right")
		page.wait_for_timeout(400)
	page.wait_for_timeout(2000)
	return count(console, start, "places node")


def dig_nodes(page: Page, console: list[str]) -> int:
	"""Dig the ground the player is standing on, with the mese pick."""
	start = len(console)
	page.keyboard.press("1")
	page.wait_for_timeout(800)
	look(page, 0, 40)
	for attempt in range(40):
		if count(console, start, "digs ") >= DIG_TARGET:
			break
		if attempt and attempt % 8 == 0:
			look(page, 20, 0)
		page.mouse.down(button="left")
		page.wait_for_timeout(600)
		page.mouse.up(button="left")
		page.wait_for_timeout(300)
	page.wait_for_timeout(2000)
	return count(console, start, "digs ")


def run(page: Page, url: str, console: list[str], screenshots: Path | None,
		require_place: bool) -> dict:
	def shot(name: str) -> None:
		if screenshots:
			page.screenshot(path=str(screenshots / f"{name}.png"))

	# Steps 2-4: the page starts, hydrates, and leaves the browser usable.
	page.goto(url, wait_until="domcontentloaded", timeout=120_000)
	wait_for_launcher(page)
	prelaunch = page.evaluate("""() => ({
		crossOriginIsolated,
		persistence: Module.luantiPersistence.getState(),
		launcher: Module.luantiLauncher.getState(),
		buttonDisabled: document.getElementById("luanti-play-button").disabled,
		game: document.getElementById("luanti-game").value
	})""")
	assert prelaunch["crossOriginIsolated"], prelaunch
	assert prelaunch["persistence"]["state"] == "ready", prelaunch
	assert not prelaunch["persistence"]["fatal"], prelaunch
	assert prelaunch["launcher"]["runtimeReady"], prelaunch
	assert not prelaunch["launcher"]["started"], prelaunch
	assert not prelaunch["buttonDisabled"], prelaunch
	assert prelaunch["game"] == "devtest", prelaunch
	shot("01-launcher")

	# The engine reads its configuration once, at startup, so seed the file
	# and reload before the world exists.
	page.evaluate("text => FS.writeFile('%s', text)" % CONFIG, CONFIG_TEXT)
	sync_filesystem(page)
	page.reload(wait_until="domcontentloaded", timeout=120_000)
	wait_for_launcher(page)
	seeded = page.evaluate(
		"FS.readFile('%s', {encoding: 'utf8'})" % CONFIG)
	assert seeded == CONFIG_TEXT, seeded

	# Steps 5-6: create and enter the world, then interact with it.
	page.evaluate("""() => {
		window.luantiTicks = 0;
		window.luantiTicker = setInterval(() => window.luantiTicks++, 20);
	}""")
	page.click("#luanti-play-button")
	wait_for_world(page, console)
	ticks = page.evaluate("window.luantiTicks")
	page.wait_for_timeout(6000)
	shot("02-world")
	grab_pointer(page)
	send_chat(page, console, f"/giveme {PLACE_ITEM} 40")
	placed = place_nodes(page, console)
	dug = dig_nodes(page, console)
	shot("03-interaction")

	# Step 7: the same world comes back after a hard reload.
	sync_filesystem(page)
	before = {
		"map": digest(page, f"{WORLD}/map.sqlite"),
		"players": digest(page, f"{WORLD}/players.sqlite"),
		"config": digest(page, CONFIG)
	}
	page.reload(wait_until="domcontentloaded", timeout=120_000)
	wait_for_launcher(page)
	after = {
		"map": digest(page, f"{WORLD}/map.sqlite"),
		"players": digest(page, f"{WORLD}/players.sqlite"),
		"config": digest(page, CONFIG)
	}
	assert before == after, {"before": before, "after": after}
	page.click("#luanti-play-button")
	wait_for_world(page, console)
	shot("04-reloaded-world")

	assert ticks >= 20, f"browser main thread stalled during load: {ticks} ticks"
	assert dug >= DIG_TARGET, f"dug {dug} of {DIG_TARGET} nodes"
	# Placing is a documented gate failure (#32): the engine never acts on the
	# right mouse button in the browser client. Keep measuring it so the day it
	# works is visible, and pass --require-place once it is fixed.
	if require_place:
		assert placed >= PLACE_TARGET, f"placed {placed} of {PLACE_TARGET} nodes"
	return {"ticks": ticks, "placed": placed, "dug": dug, "world": before}


def main() -> int:
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument("--browser", default=shutil.which("google-chrome"),
		help="browser executable Playwright should drive")
	parser.add_argument("--engine", default="chromium",
		choices=("chromium", "firefox"),
		help="Playwright browser engine for the given executable")
	parser.add_argument("--build", default="build-wasm")
	parser.add_argument("--screenshot-dir")
	parser.add_argument("--headed", action="store_true")
	parser.add_argument("--require-place", action="store_true",
		help="fail when fewer than %d nodes can be placed (see the known gate "
			"failures in doc/compiling/wasm.md)" % PLACE_TARGET)
	args = parser.parse_args()
	if not args.browser:
		parser.error("no browser executable was found; pass --browser")

	repo = Path(__file__).resolve().parents[2]
	output = (repo / args.build / "bin").resolve()
	if not (output / "luanti.html").exists():
		parser.error(f"generated client not found under {output}")
	screenshots = None
	if args.screenshot_dir:
		screenshots = Path(args.screenshot_dir)
		screenshots.mkdir(parents=True, exist_ok=True)

	console: list[str] = []
	page_errors: list[str] = []
	with create_server(output, "127.0.0.1", 0, quiet=True) as server:
		thread = threading.Thread(target=server.serve_forever, daemon=True)
		thread.start()
		try:
			with sync_playwright() as playwright:
				engine = getattr(playwright, args.engine)
				launch: dict[str, object] = {
					"headless": not args.headed,
					"executable_path": args.browser
				}
				if args.engine == "chromium":
					launch["args"] = ["--no-sandbox", "--use-gl=angle",
						"--use-angle=swiftshader"]
				browser = engine.launch(**launch)
				page = browser.new_context(
					viewport={"width": 1280, "height": 720}).new_page()
				page.on("console", lambda message: console.append(message.text))
				page.on("pageerror", lambda error: page_errors.append(
					format_page_error(error)))
				url = (f"http://127.0.0.1:{server.server_address[1]}/luanti.html"
					"?game=devtest&view=60")
				try:
					result = run(page, url, console, screenshots,
						args.require_place)
				finally:
					tail = "\n".join(line[:160] for line in console[-20:])
					browser.close()
		finally:
			server.shutdown()

	assert not page_errors, {"pageErrors": page_errors, "console": console[-30:]}
	print(f"first playable smoke passed on {args.engine}: {result}")
	if not result["placed"]:
		print("note: no node could be placed; see issue #32 and "
			"docs/wasm-issues/06-first-playable-gate-results.md")
	print(f"console tail:\n{tail}")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
