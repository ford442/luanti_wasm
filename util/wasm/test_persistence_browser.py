#!/usr/bin/env python3
# Luanti
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 The Luanti Contributors
"""Exercise the production IDBFS bootstrap in a real browser origin."""

from __future__ import annotations

import argparse
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
	with tempfile.TemporaryDirectory(prefix="luanti-persistence-") as directory:
		output = Path(directory)
		environment = os.environ.copy()
		environment["EM_CACHE"] = args.em_cache or str(output / "em-cache")
		command = [
			args.emcc,
			str(repo / "util/wasm/persistence_probe.cpp"),
			"-O1",
			"-pthread",
			"-sPROXY_TO_PTHREAD=1",
			"-sFORCE_FILESYSTEM=1",
			"-sEXIT_RUNTIME=0",
			"-lidbfs.js",
			"--pre-js",
			str(repo / "client/web/persistence.js"),
			"--shell-file",
			str(repo / "client/web/shell.html"),
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
					url = f"http://127.0.0.1:{server.server_address[1]}/probe.html"
					page.goto(url)
					page.wait_for_function(
						"Module.luantiPersistenceProbe?.mainStarted === true")
					first = page.evaluate("Module.luantiPersistenceProbe")
					assert first == {
						"mainStarted": True,
						"workerMain": True,
						"storageStateAtMain": "ready",
					}, first

					sentinel = "/home/web_user/.luanti/worlds/browser-sentinel"
					page.evaluate("""async path => {
						window.persistenceEvents = [];
						window.addEventListener("luanti:persistence", event =>
							window.persistenceEvents.push(event.detail));
						FS.writeFile(path, "survived reload");
						await Module.luantiPersistence.requestSync({
							reason: "external", urgent: true
						});
					} """, sentinel)
					events = page.evaluate("window.persistenceEvents")
					assert any(event["state"] == "saved" and
						event["reason"] == "external" and not event["pending"]
						for event in events), events
					assert page.locator("#luanti-persistence-status").inner_text() == "Saved"
					assert page.locator("#luanti-persistence-error").is_hidden()

					page.reload()
					page.wait_for_function(
						"Module.luantiPersistenceProbe?.mainStarted === true")
					restored = page.evaluate(
						"path => FS.readFile(path, {encoding: 'utf8'})", sentinel)
					assert restored == "survived reload", restored
					browser.close()
			finally:
				server.shutdown()

		print("IDBFS browser reload smoke passed")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
