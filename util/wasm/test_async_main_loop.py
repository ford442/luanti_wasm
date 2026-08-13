#!/usr/bin/env python3
# Luanti
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 The Luanti Contributors
"""Build and browser-test Luanti's Emscripten worker-main contract."""

from __future__ import annotations

import argparse
import contextlib
import functools
import http.server
import os
from pathlib import Path
import shutil
import socketserver
import subprocess
import tempfile
import threading

from playwright.sync_api import sync_playwright


class CrossOriginIsolatedHandler(http.server.SimpleHTTPRequestHandler):
	def end_headers(self) -> None:
		self.send_header("Cross-Origin-Opener-Policy", "same-origin")
		self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
		super().end_headers()

	def log_message(self, format: str, *args: object) -> None:
		pass


class ReusableTCPServer(socketserver.TCPServer):
	allow_reuse_address = True


def main() -> int:
	parser = argparse.ArgumentParser()
	parser.add_argument("--emcc", default=shutil.which("emcc"))
	parser.add_argument("--browser", default=shutil.which("google-chrome"))
	parser.add_argument("--em-cache", default=os.environ.get("EM_CACHE"))
	args = parser.parse_args()
	if not args.emcc:
		parser.error("emcc was not found")
	if not args.browser:
		parser.error("Google Chrome was not found")

	repo = Path(__file__).resolve().parents[2]
	with tempfile.TemporaryDirectory(prefix="luanti-mainloop-") as directory:
		output = Path(directory)
		environment = os.environ.copy()
		environment["EM_CACHE"] = args.em_cache or str(output / "em-cache")
		command = [
			args.emcc,
			str(repo / "util/wasm/mainloop_probe.cpp"),
			"-O1",
			"-pthread",
			"-sUSE_SDL=2",
			"-sPROXY_TO_PTHREAD=1",
			"-sOFFSCREEN_FRAMEBUFFER=1",
			"-sEXIT_RUNTIME=0",
			"--pre-js",
			str(repo / "util/wasm/mainloop_probe_pre.js"),
			"-o",
			str(output / "probe.html"),
		]
		subprocess.run(command, check=True, env=environment)

		handler = functools.partial(CrossOriginIsolatedHandler, directory=output)
		with ReusableTCPServer(("127.0.0.1", 0), handler) as server:
			thread = threading.Thread(target=server.serve_forever, daemon=True)
			thread.start()
			try:
				with sync_playwright() as playwright:
					browser = playwright.chromium.launch(
						headless=True,
						executable_path=args.browser,
						args=["--no-sandbox", "--enable-features=SharedArrayBuffer"],
					)
					page = browser.new_page()
					messages: list[str] = []
					page.on("console", lambda message: messages.append(
						f"console {message.type}: {message.text}"))
					page.on("pageerror", lambda error: messages.append(
						f"pageerror: {getattr(error, 'stack', error)}"))
					page.on("requestfailed", lambda request: messages.append(
						f"requestfailed: {request.url}: {request.failure}"))
					page.goto(f"http://127.0.0.1:{server.server_address[1]}/probe.html")
					try:
						page.wait_for_function(
							"window.luantiMainLoopProbe?.ready === true", timeout=15_000)
					except Exception as error:
						state = page.evaluate("window.luantiMainLoopProbe || null")
						raise RuntimeError(
							f"probe did not start; state={state}; messages={messages}") from error
					page.locator("#canvas").click(position={"x": 30, "y": 30})
					page.wait_for_function("window.luantiMainLoopProbe?.done === true")
					probe = page.evaluate("window.luantiMainLoopProbe")
					browser.close()
			finally:
				server.shutdown()

		assert probe["workerMain"], probe
		assert probe["webgl"], probe
		assert probe["crossOriginIsolated"], probe
		assert probe["ticksAtDone"] - probe["ticksAtReady"] >= 20, probe
		assert probe["mouseCallbacks"] >= 1, probe
		print("worker-main browser smoke passed:", probe)
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
