#!/usr/bin/env python3
# Luanti
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 The Luanti Contributors
"""Load the generated Luanti client and verify its browser startup contract."""

from __future__ import annotations

import argparse
import functools
import http.server
from pathlib import Path
import shutil
import socketserver
import threading

from playwright.sync_api import sync_playwright


class CrossOriginIsolatedHandler(http.server.SimpleHTTPRequestHandler):
	def end_headers(self) -> None:
		self.send_header("Cross-Origin-Opener-Policy", "same-origin")
		self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
		super().end_headers()

	def log_message(self, format: str, *args: object) -> None:
		pass


class ReusableTCPServer(socketserver.ThreadingTCPServer):
	allow_reuse_address = True
	daemon_threads = True


def format_page_error(error: object) -> str:
	stack = getattr(error, "stack", None)
	return str(stack or error)


def main() -> int:
	parser = argparse.ArgumentParser()
	parser.add_argument("--browser", default=shutil.which("google-chrome"))
	parser.add_argument("--build", default="build-wasm")
	parser.add_argument("--screenshot")
	args = parser.parse_args()
	if not args.browser:
		parser.error("Google Chrome was not found")

	repo = Path(__file__).resolve().parents[2]
	output = (repo / args.build / "bin").resolve()
	if not (output / "luanti.html").exists():
		parser.error(f"generated client not found under {output}")

	handler = functools.partial(CrossOriginIsolatedHandler, directory=output)
	with ReusableTCPServer(("127.0.0.1", 0), handler) as server:
		thread = threading.Thread(target=server.serve_forever, daemon=True)
		thread.start()
		try:
			with sync_playwright() as playwright:
				browser = playwright.chromium.launch(
					headless=True, executable_path=args.browser,
					args=["--no-sandbox", "--enable-features=SharedArrayBuffer"])
				page = browser.new_page(viewport={"width": 1280, "height": 720})
				messages: list[str] = []
				page_errors: list[str] = []
				page.on("console", lambda message: messages.append(
					f"{message.type}: {message.text}"))
				page.on("pageerror", lambda error: page_errors.append(
					format_page_error(error)))
				page.goto(
					f"http://127.0.0.1:{server.server_address[1]}/luanti.html",
					wait_until="domcontentloaded", timeout=60_000)
				page.wait_for_function(
					"Module.luantiPersistence?.getState().state === 'ready'",
					timeout=60_000)
				page.wait_for_function(
					"Module.calledRun === true || typeof calledRun !== 'undefined' && calledRun",
					timeout=60_000)
				page.evaluate("""() => {
					window.luantiResponsivenessTicks = 0;
					window.luantiResponsivenessTimer = setInterval(
						() => window.luantiResponsivenessTicks++, 20);
				}""")
				page.wait_for_timeout(1000)
				state = page.evaluate("""() => ({
					crossOriginIsolated,
					persistence: Module.luantiPersistence.getState(),
					network: Module.luantiNetwork.getState(),
					ticks: window.luantiResponsivenessTicks,
					canvas: {width: Module.canvas.width, height: Module.canvas.height}
				})""")
				if args.screenshot:
					page.screenshot(path=args.screenshot)
				browser.close()
		finally:
			server.shutdown()

	assert not page_errors, {"pageErrors": page_errors, "console": messages[-30:]}
	assert state["crossOriginIsolated"], state
	assert state["persistence"]["state"] == "ready", state
	assert state["network"]["state"] == "disabled", state
	assert state["ticks"] >= 20, state
	assert state["canvas"]["width"] > 0 and state["canvas"]["height"] > 0, state
	assert any("application worker" in message for message in messages), {
		"state": state, "console": messages[-30:]}
	print("generated Luanti browser startup passed:", state)
	print("console tail:", messages[-30:])
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
