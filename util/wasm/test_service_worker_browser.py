#!/usr/bin/env python3
# Luanti
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 The Luanti Contributors
"""Service-worker regression tests, including the stale-luanti.wasm incident.

An earlier worker intercepted engine assets and, when the network failed,
replayed an old luanti.wasm next to a new luanti.js. This test drives the real
client/web/service-worker.js (stamped by build_packages.py exactly as in a
build) in Chrome against a small fake site whose files are versioned, and
checks that every one of those failure modes now ends in a consistent build,
or in an honest error, never in a mix.

No engine build is needed; run it with:

	python3 util/wasm/test_service_worker_browser.py --browser "$(command -v google-chrome)"
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import shutil
import sys
import tempfile
import threading
import time

from playwright.sync_api import Browser, BrowserContext, Page, sync_playwright

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from build_packages import build_all  # noqa: E402
from serve import create_server  # noqa: E402

REPO = HERE.parents[1]
WORKER = REPO / "client/web/service-worker.js"

PAGE = """<!doctype html>
<meta charset="utf-8"><meta name="build" content="%(version)s">
<title>fake luanti %(version)s</title>
<script src="luanti.js"></script>
"""


def make_config(version: str) -> dict:
	return {
		"schema": 1,
		"packages": {
			"core": {"label": "Core", "eager": True,
				"mounts": [{"src": "data/core", "dest": "/core"}]},
			"extra": {"label": "Extra",
				"mounts": [{"src": "data/extra", "dest": "/extra"}]},
		},
		"games": {"demo": {"packages": ["extra"]}},
		"shell": ["luanti.html", "luanti.js", "luanti.wasm"],
		"verified": ["luanti.js", "luanti.wasm"],
		"serviceWorker": "client/web/service-worker.js",
	}


def deploy(site: Path, work: Path, version: str, *, corrupt_wasm: bool = False,
		omit_wasm: bool = False) -> dict:
	"""Write version `version` of the fake site into `site` (an in-place deploy)."""
	root = work / f"src-{version}"
	shutil.rmtree(root, ignore_errors=True)
	(root / "data/core").mkdir(parents=True)
	(root / "data/extra").mkdir(parents=True)
	(root / "client/web").mkdir(parents=True)
	(root / "data/core/hello.txt").write_text(f"core {version}")
	(root / "data/extra/hello.txt").write_text(f"extra {version}")
	shutil.copy2(WORKER, root / "client/web/service-worker.js")
	build = work / f"build-{version}"
	shutil.rmtree(build, ignore_errors=True)
	build.mkdir()
	(build / "luanti.html").write_text(PAGE % {"version": version})
	(build / "luanti.js").write_text(f"window.engineJs = '{version}';\n")
	(build / "luanti.wasm").write_bytes(f"WASM-{version}".encode())
	manifest = build_all(root, make_config(version), build, shell_dir=build)

	for path in site.iterdir():
		if path.is_dir():
			shutil.rmtree(path)
		else:
			path.unlink()
	shutil.copytree(build, site, dirs_exist_ok=True)
	if corrupt_wasm:
		# Same length, different bytes: only the SHA-256 check can notice.
		(site / "luanti.wasm").write_bytes(f"WASM-XXXXXX".encode()[:len(f"WASM-{version}")])
	if omit_wasm:
		(site / "luanti.wasm").unlink()
	return manifest


def wait_until(predicate, what: str, timeout: float = 20.0):
	deadline = time.monotonic() + timeout
	while time.monotonic() < deadline:
		value = predicate()
		if value:
			return value
		time.sleep(0.1)
	raise AssertionError(f"timed out waiting for {what}")


def observed(page: Page) -> dict:
	"""What the page actually got: its own build marker and the wasm bytes."""
	return page.evaluate("""async () => {
		const response = await fetch("luanti.wasm", {cache: "no-store"});
		return {
			page: document.querySelector('meta[name="build"]').content,
			engine: window.engineJs,
			wasmStatus: response.status,
			wasm: response.ok ? await response.text() : null,
		};
	}""")


def worker_state(page: Page) -> dict:
	return page.evaluate("""async () => {
		const registration = await navigator.serviceWorker.getRegistration();
		return {
			controlled: !!navigator.serviceWorker.controller,
			active: !!(registration && registration.active),
			waiting: !!(registration && registration.waiting),
			installing: !!(registration && registration.installing),
			caches: (await caches.keys()).sort(),
		};
	}""")


def shell_caches(page: Page) -> list[str]:
	return [name for name in worker_state(page)["caches"] if name.startswith("luanti-shell:")]


def run(browser: Browser) -> None:
	work = Path(tempfile.mkdtemp(prefix="luanti-sw-test-"))
	site = work / "site"
	site.mkdir()
	manifest1 = deploy(site, work, "v1")
	server = create_server(site, "127.0.0.1", 0, quiet=True)
	threading.Thread(target=server.serve_forever, daemon=True).start()
	url = f"http://127.0.0.1:{server.server_address[1]}/luanti.html"
	context: BrowserContext = browser.new_context(service_workers="allow")
	page = context.new_page()
	errors: list[str] = []
	page.on("pageerror", lambda error: errors.append(str(error)))
	try:
		# 1. First visit: the worker installs the verified shell and claims the page.
		page.goto(url)
		page.evaluate("navigator.serviceWorker.register('service-worker.js', {scope: './'})")
		wait_until(lambda: worker_state(page)["active"], "first worker activation")
		page.reload()
		wait_until(lambda: worker_state(page)["controlled"], "page control")
		state = worker_state(page)
		assert shell_caches(page) == [f"luanti-shell:{manifest1['buildId']}"], state
		assert observed(page) == {"page": "v1", "engine": "v1", "wasmStatus": 200,
			"wasm": "WASM-v1"}, observed(page)

		# 2. Offline: the cached, verified v1 set serves the whole page.
		context.set_offline(True)
		page.reload()
		assert observed(page)["page"] == "v1" and observed(page)["wasm"] == "WASM-v1"
		# The eager engine package was precached for offline use.
		core_url = manifest1["packages"]["core"]["url"]
		assert page.evaluate("u => fetch(u).then(r => r.ok)", core_url), "core asset offline"
		context.set_offline(False)

		# 3. THE INCIDENT. v2 is deployed and the page is reloaded online. The old
		# worker must not answer from its v1 cache: the page gets v2 everywhere.
		manifest2 = deploy(site, work, "v2")
		page.reload()
		got = observed(page)
		assert got == {"page": "v2", "engine": "v2", "wasmStatus": 200, "wasm": "WASM-v2"}, \
			f"stale engine served after a deploy: {got}"

		# ...and a v2 deploy that lost its wasm is an honest 404, not v1's binary.
		(site / "luanti.wasm").unlink()
		got = observed(page)
		assert got["wasmStatus"] == 404 and got["wasm"] is None, \
			f"HTTP error was papered over with a cached binary: {got}"
		(site / "luanti.wasm").write_bytes(b"WASM-v2")

		# 4. The update installs next to v1 and waits; nothing switches by itself.
		wait_until(lambda: worker_state(page)["waiting"], "v2 worker to wait")
		assert worker_state(page)["controlled"]
		assert len(shell_caches(page)) == 2, shell_caches(page)

		# 5. Accepting the update activates v2 and drops v1's cache.
		page.evaluate("""async () => {
			const registration = await navigator.serviceWorker.getRegistration();
			registration.waiting.postMessage({type: "SKIP_WAITING"});
		}""")
		wait_until(lambda: shell_caches(page) == [f"luanti-shell:{manifest2['buildId']}"],
			"old shell cache removal")
		context.set_offline(True)
		page.reload()
		got = observed(page)
		assert got["page"] == "v2" and got["wasm"] == "WASM-v2", got
		context.set_offline(False)

		# 6. A deploy whose wasm differs from its manifest (the SHA-256 check)
		# must not install: v2 stays, complete, and still works offline.
		deploy(site, work, "v3", corrupt_wasm=True)
		page.reload()
		page.evaluate("navigator.serviceWorker.getRegistration().then(r => r.update()).catch(() => {})")
		time.sleep(4)  # let the install attempt run and fail
		wait_until(lambda: not worker_state(page)["installing"], "v3 install attempt to end")
		state = worker_state(page)
		assert not state["waiting"], f"corrupt v3 installed: {state}"
		assert shell_caches(page) == [f"luanti-shell:{manifest2['buildId']}"], state

		# 7. A half-deployed v4 (wasm missing) is rejected the same way.
		deploy(site, work, "v4", omit_wasm=True)
		page.evaluate("navigator.serviceWorker.getRegistration().then(r => r.update()).catch(() => {})")
		time.sleep(2)
		state = worker_state(page)
		assert not state["waiting"], f"half-deployed v4 installed: {state}"
		assert shell_caches(page) == [f"luanti-shell:{manifest2['buildId']}"], state
		context.set_offline(True)
		page.goto(url)
		got = page.evaluate("""async () => ({
			page: document.querySelector('meta[name="build"]').content,
			wasm: await (await fetch("luanti.wasm")).text()})""")
		assert got == {"page": "v2", "wasm": "WASM-v2"}, f"mixed or lost build offline: {got}"
		context.set_offline(False)

		# 8. Content-addressed packages are cache-first: after one online fetch
		# the package is served with the network gone.
		deploy(site, work, "v2")
		extra = manifest2["packages"]["extra"]["url"]
		page.goto(url)
		assert page.evaluate("u => fetch(u).then(r => r.ok)", extra)
		context.set_offline(True)
		assert page.evaluate("u => fetch(u).then(r => r.ok)", extra), "hashed package offline"
		context.set_offline(False)

		assert not errors, errors
	finally:
		context.close()
		server.shutdown()
		shutil.rmtree(work, ignore_errors=True)


def main() -> int:
	global WORKER
	parser = argparse.ArgumentParser(description=__doc__,
		formatter_class=argparse.RawDescriptionHelpFormatter)
	parser.add_argument("--browser", default=shutil.which("google-chrome"))
	parser.add_argument("--headed", action="store_true")
	parser.add_argument("--worker", default=str(WORKER),
		help="service worker source to test (to prove the test catches a bad one)")
	args = parser.parse_args()
	WORKER = Path(args.worker).resolve()
	with sync_playwright() as playwright:
		browser = playwright.chromium.launch(
			executable_path=args.browser, headless=not args.headed,
			args=["--no-sandbox"])
		try:
			run(browser)
		finally:
			browser.close()
	print("service worker regression tests passed")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
