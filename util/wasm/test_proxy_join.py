#!/usr/bin/env python3
# Luanti
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 The Luanti Contributors
"""Join a native luantiserver from the generated WASM client through the proxy.

This is the browser leg of "public-server acceptance" (wasm_porting.md, Phase 4)
without a public host. Everything runs on 127.0.0.1:

  native luantiserver  <--UDP-->  util/wasm/proxy (npm start)  <--WebSocket-->
  Chrome running build-wasm/bin/luanti.html, driven through the launcher's
  "Join server" form (custom proxy URL, address, port, name).

Scenarios (all by default, --scenario picks one):

  join        The client completes the proxy handshake (PROXY OK), the engine
              logs TOCLIENT_HELLO and enters the world, the server logs the
              player joining, and a chat line typed in the browser arrives in
              the server log.
  origin      A proxy that does not allow the page's origin: the launcher says
              so (Module.luantiLauncher.getState().proxy and the on-page alert)
              instead of a generic WebSocket error, and the client does not
              redial the proxy for every datagram.
  proxy-down  Nothing listens on the proxy address: the launcher says the proxy
              could not be reached.

What this does not show: that a proxy is safe to publish (see the "Still needed
on a public host" list in util/wasm/proxy/README.md), TLS, or a remote server.
"""

from __future__ import annotations

import argparse
import contextlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import socket
import subprocess
import tempfile
import threading
import time
from typing import Iterator
import urllib.request
import uuid

from playwright.sync_api import Page, sync_playwright

from serve import create_server

PLAYER = "ProxyJoin"
SCENARIOS = ("join", "origin", "proxy-down")
# What the engine prints (actionstream, so it reaches the browser console).
HELLO = "Client: handling TOCLIENT_HELLO"
WORLD_READY = "World ready; entering game loop"


def format_page_error(error: object) -> str:
	return str(getattr(error, "stack", None) or error)


def unused_port(kind: int = socket.SOCK_STREAM) -> int:
	with socket.socket(socket.AF_INET, kind) as probe:
		probe.bind(("127.0.0.1", 0))
		return probe.getsockname()[1]


class Managed:
	"""A child process whose combined output is collected line by line."""

	def __init__(self, name: str, command: list[str], cwd: Path,
			env: dict[str, str] | None = None) -> None:
		self.name = name
		self.lines: list[str] = []
		self.process = subprocess.Popen(
			command, cwd=cwd, env=env, stdout=subprocess.PIPE,
			stderr=subprocess.STDOUT, text=True, errors="replace", bufsize=1,
			start_new_session=True)
		threading.Thread(target=self._pump, daemon=True).start()

	def _pump(self) -> None:
		assert self.process.stdout is not None
		for line in self.process.stdout:
			self.lines.append(line.rstrip("\n"))

	def wait_for(self, pattern: str, timeout: float) -> str:
		expression = re.compile(pattern)
		deadline = time.monotonic() + timeout
		seen = 0
		while time.monotonic() < deadline:
			for line in self.lines[seen:]:
				if expression.search(line):
					return line
			seen = len(self.lines)
			if self.process.poll() is not None and seen == len(self.lines):
				raise RuntimeError(f"{self.name} exited ({self.process.returncode}) before "
					f"logging /{pattern}/\n{self.tail()}")
			time.sleep(0.1)
		raise RuntimeError(f"{self.name} never logged /{pattern}/\n{self.tail()}")

	def has(self, pattern: str) -> bool:
		expression = re.compile(pattern)
		return any(expression.search(line) for line in list(self.lines))

	def tail(self, count: int = 25) -> str:
		return "\n".join(f"  [{self.name}] {line[:220]}" for line in self.lines[-count:])

	def stop(self) -> None:
		# npm start leaves node as a child: signal the whole group.
		if self.process.poll() is None:
			with contextlib.suppress(ProcessLookupError):
				os.killpg(self.process.pid, signal.SIGTERM)
			try:
				self.process.wait(timeout=8)
			except subprocess.TimeoutExpired:
				with contextlib.suppress(ProcessLookupError):
					os.killpg(self.process.pid, signal.SIGKILL)
				self.process.wait(timeout=5)


@contextlib.contextmanager
def native_server(binary: Path, repo: Path, game: str) -> Iterator[tuple[Managed, int]]:
	"""A dedicated server on 127.0.0.1 with a fresh flat world."""
	port = unused_port(socket.SOCK_DGRAM)
	with tempfile.TemporaryDirectory(prefix="luanti-proxy-join-") as directory:
		root = Path(directory)
		config = root / "minetest.conf"
		config.write_text(
			"# written by util/wasm/test_proxy_join.py\n"
			"bind_address = 127.0.0.1\n"
			"server_announce = false\n"
			"mg_name = flat\n"
			"fixed_map_seed = proxyjoin\n"
			"max_users = 4\n"
			"time_speed = 0\n"
			"default_privs = interact, shout\n"
			"enable_damage = false\n")
		server = Managed("server", [
			str(binary), "--config", str(config), "--world", str(root / "world"),
			"--gameid", game, "--port", str(port), "--logfile", str(root / "debug.txt"),
		], repo)
		try:
			server.wait_for(r'Server for gameid="%s" listening on 127\.0\.0\.1:%d' % (game, port), 120)
			yield server, port
		finally:
			server.stop()


@contextlib.contextmanager
def proxy(repo: Path, port: int, targets: str, origins: str) -> Iterator[Managed]:
	directory = repo / "util/wasm/proxy"
	if not (directory / "node_modules/ws").exists():
		raise RuntimeError("run `npm ci --prefix util/wasm/proxy` first")
	# Hermetic: a LUANTI_PROXY_* variable in the caller's shell must not change
	# what is tested. The proxy runs on its shipped defaults apart from the
	# listen address, the one allowed target and the one allowed origin.
	environment = {name: value for name, value in os.environ.items()
		if not name.startswith("LUANTI_PROXY_")}
	environment.update({
		"LUANTI_PROXY_HOST": "127.0.0.1",
		"LUANTI_PROXY_PORT": str(port),
		"LUANTI_PROXY_ALLOWED_TARGETS": targets,
		"LUANTI_PROXY_ALLOWED_ORIGINS": origins,
	})
	process = Managed("proxy", ["npm", "start", "--silent"], directory, environment)
	try:
		process.wait_for(r'"event":"listening"', 30)
		yield process
	finally:
		process.stop()


def proxy_events(process: Managed) -> list[dict]:
	events = []
	for line in list(process.lines):
		with contextlib.suppress(ValueError):
			events.append(json.loads(line))
	return events


def metric(port: int, name: str, label: str = "") -> float:
	"""One Prometheus value from the proxy (loopback needs no token)."""
	with urllib.request.urlopen(f"http://127.0.0.1:{port}/metrics", timeout=5) as response:
		text = response.read().decode()
	total = 0.0
	for line in text.splitlines():
		if line.startswith(name + label) and not line.startswith("#"):
			total += float(line.rsplit(" ", 1)[1])
	return total


def wait_for_launcher(page: Page) -> None:
	page.wait_for_function(
		"Module.luantiPersistence?.getState().state === 'ready'", timeout=120_000)
	page.wait_for_function(
		"Module.luantiLauncher?.getState().runtimeReady === true", timeout=120_000)
	page.wait_for_function(
		"!document.getElementById('luanti-play-button').disabled", timeout=120_000)


def fill_join_form(page: Page, address: str, port: int, proxy_url: str) -> None:
	"""The launcher's direct-connect flow, as a player would use it."""
	page.click("#luanti-remote-tab")
	page.fill("#luanti-address", address)
	page.fill("#luanti-port", str(port))
	page.fill("#luanti-player-name", PLAYER)
	page.click("details.advanced summary")
	page.select_option("#luanti-proxy-region", "custom")
	page.fill("#luanti-proxy-url", proxy_url)


def notice_hidden(page: Page) -> bool:
	return page.evaluate("document.getElementById('luanti-proxy-notice').hidden")


def check_proxy_notice(page: Page) -> None:
	"""A proxy that is not on this machine can read the game: the form says so."""
	remote = "wss://proxy.example.org/"
	page.fill("#luanti-proxy-url", remote)
	assert not notice_hidden(page), "no notice for a remote proxy"
	text = page.inner_text("#luanti-proxy-notice")
	assert "operator can see your gameplay and chat" in text, text
	for loopback in ("ws://127.0.0.1:8080/", "ws://localhost:8080/", "ws://[::1]:8080/"):
		page.fill("#luanti-proxy-url", loopback)
		assert notice_hidden(page), f"notice shown for the loopback proxy {loopback}"
	page.fill("#luanti-proxy-url", "wss://")
	assert notice_hidden(page), "a half-typed URL is not a proxy"


def send_chat(page: Page, server: Managed, text: str) -> None:
	"""Type a chat line, retrying: early key presses are dropped while the
	engine catches up on its first server steps (see test_first_playable.py)."""
	expected = rf"CHAT: <{PLAYER}> {re.escape(text)}"
	for _ in range(8):
		page.keyboard.press("t")
		page.wait_for_timeout(1500)
		page.keyboard.type(text, delay=60)
		page.wait_for_timeout(500)
		page.keyboard.press("Enter")
		deadline = time.monotonic() + 5
		while time.monotonic() < deadline:
			if server.has(expected):
				return
			page.wait_for_timeout(250)
	raise AssertionError(f"the chat line never reached the server\n{server.tail()}")


def wait_for_console(page: Page, console: list[str], needle: str, timeout: float) -> None:
	deadline = time.monotonic() + timeout
	while time.monotonic() < deadline:
		if any(needle in line for line in console):
			return
		page.wait_for_timeout(500)
	raise AssertionError(f"the engine never logged {needle!r}")


def scenario_join(page: Page, base: str, console: list[str], repo: Path,
		binary: Path, game: str, screenshots: Path | None) -> dict:
	origin = base
	web_port = int(base.rsplit(":", 1)[1])
	proxy_port = unused_port()
	with native_server(binary, repo, game) as (server, udp_port):
		with proxy(repo, proxy_port, f"127.0.0.1:{udp_port}", origin) as relay:
			page.goto(f"{base}/luanti.html?view=60", wait_until="domcontentloaded", timeout=120_000)
			wait_for_launcher(page)
			fill_join_form(page, "127.0.0.1", udp_port, "wss://proxy.example.org/")
			check_proxy_notice(page)
			proxy_url = f"ws://127.0.0.1:{proxy_port}/"
			page.fill("#luanti-proxy-url", proxy_url)
			assert notice_hidden(page), "the loopback proxy needs no warning"
			page.click("#luanti-play-button")
			try:
				page.wait_for_function(
					"Module.luantiNetwork.getState().state === 'ready'", timeout=120_000)
				state = page.evaluate("Module.luantiNetwork.getState()")
				assert state["url"] == proxy_url, state
				assert state["reason"] is None and state["error"] is None, state
				wait_for_console(page, console, HELLO, 120)
				wait_for_console(page, console, WORLD_READY, 240)
				server.wait_for(rf"{PLAYER} \[[0-9.]+\] joins game", 60)
				if screenshots:
					page.screenshot(path=str(screenshots / "join-world.png"))
				page.click("#canvas", position={"x": 640, "y": 360})
				page.wait_for_timeout(1500)
				message = "proxyjoin-" + uuid.uuid4().hex[:8]
				send_chat(page, server, message)
				if screenshots:
					page.wait_for_timeout(3000)
					page.screenshot(path=str(screenshots / "join-after-chat.png"))
			except BaseException:
				print("--- server ---\n" + server.tail(40))
				print("--- proxy ---\n" + relay.tail(40))
				raise
			launcher = page.evaluate("Module.luantiLauncher.getState()")
			assert launcher["proxy"]["message"] == "", launcher["proxy"]
			assert launcher["proxy"]["state"] == "ready", launcher["proxy"]
			assert page.evaluate("document.getElementById('luanti-proxy-alert').hidden")

			events = proxy_events(relay)
			opened = [e for e in events if e.get("event") == "session_opened"]
			assert opened and opened[0]["origin"] == origin, events
			assert not [e for e in events if e.get("event") == "connection_rejected"], events
			assert not [e for e in events if e.get("event") == "session_closed"
				and e.get("reason") not in ("client_closed",)], events
			forwarded = metric(proxy_port, "luanti_proxy_datagrams_forwarded_total")
			received = metric(proxy_port, "luanti_proxy_datagrams_received_total")
			assert forwarded > 0 and received > 0, (forwarded, received)
			assert metric(proxy_port, "luanti_proxy_rate_limited_total") == 0
			return {"proxy": proxy_url, "web_port": web_port, "server_port": udp_port,
				"datagrams_forwarded": forwarded, "datagrams_received": received,
				"chat": message}


def scenario_origin(page: Page, base: str, repo: Path) -> dict:
	proxy_port = unused_port()
	allowed = "https://play.example.org"
	with proxy(repo, proxy_port, "127.0.0.1:30000", allowed) as relay:
		page.goto(f"{base}/luanti.html?view=60", wait_until="domcontentloaded", timeout=120_000)
		wait_for_launcher(page)
		fill_join_form(page, "127.0.0.1", 30000, f"ws://127.0.0.1:{proxy_port}/")
		page.click("#luanti-play-button")
		page.wait_for_function(
			"Module.luantiLauncher.getState().proxy.message !== ''", timeout=120_000)
		proxy_state = page.evaluate("Module.luantiLauncher.getState().proxy")
		assert proxy_state["reason"] == "origin", proxy_state
		assert proxy_state["closeCode"] == 1008, proxy_state
		assert f"does not allow pages from {base}" in proxy_state["message"], proxy_state
		assert "WebSocket connection failed" not in proxy_state["message"], proxy_state
		page.wait_for_function(
			"!document.getElementById('luanti-proxy-alert').hidden", timeout=10_000)
		assert page.inner_text("#luanti-proxy-alert-text") == proxy_state["message"]
		# The engine resends its handshake several times a second; the link must
		# back off instead of dialling the proxy for each datagram.
		page.wait_for_timeout(8000)
		rejected = metric(proxy_port, "luanti_proxy_connections_rejected_total", '{reason="origin"}')
		assert 1 <= rejected <= 8, f"{rejected} refused connections in 8 s: no backoff?"
		assert metric(proxy_port, "luanti_proxy_connections_active") == 0
		assert [e for e in proxy_events(relay) if e.get("event") == "connection_rejected"
			and e.get("reason") == "origin" and e.get("origin") == base]
		return {"message": proxy_state["message"], "refused_connections": rejected}


def scenario_proxy_down(page: Page, base: str) -> dict:
	port = unused_port()  # nothing listens here once the probe socket closes
	page.goto(f"{base}/luanti.html?view=60", wait_until="domcontentloaded", timeout=120_000)
	wait_for_launcher(page)
	fill_join_form(page, "127.0.0.1", 30000, f"ws://127.0.0.1:{port}/")
	page.click("#luanti-play-button")
	page.wait_for_function(
		"Module.luantiLauncher.getState().proxy.message !== ''", timeout=120_000)
	proxy_state = page.evaluate("Module.luantiLauncher.getState().proxy")
	assert re.match(rf"^Could not connect to the proxy at 127\.0\.0\.1:{port}\b",
		proxy_state["message"]), proxy_state
	assert proxy_state["reason"] is None and proxy_state["closeCode"] == 1006, proxy_state
	page.wait_for_function(
		"!document.getElementById('luanti-proxy-alert').hidden", timeout=10_000)
	assert page.inner_text("#luanti-proxy-alert-text") == proxy_state["message"]
	return {"message": proxy_state["message"]}


def main() -> int:
	parser = argparse.ArgumentParser(description=__doc__,
		formatter_class=argparse.RawDescriptionHelpFormatter)
	parser.add_argument("--browser", default=shutil.which("google-chrome"),
		help="Chrome executable Playwright should drive")
	parser.add_argument("--build", default="build-wasm")
	parser.add_argument("--server", default="bin/luantiserver",
		help="native luantiserver, relative to the repository (default: %(default)s)")
	parser.add_argument("--game", default="devtest")
	parser.add_argument("--scenario", choices=("all", *SCENARIOS), default="all")
	parser.add_argument("--screenshot-dir")
	parser.add_argument("--headed", action="store_true")
	args = parser.parse_args()
	if not args.browser:
		parser.error("no browser executable was found; pass --browser")

	repo = Path(__file__).resolve().parents[2]
	output = (repo / args.build / "bin").resolve()
	if not (output / "luanti.html").exists():
		parser.error(f"generated client not found under {output}")
	binary = (repo / args.server).resolve()
	chosen = SCENARIOS if args.scenario == "all" else (args.scenario,)
	if "join" in chosen and not binary.exists():
		parser.error(f"native server not found at {binary}; build it with BUILD_SERVER=TRUE "
			"(see .github/workflows/wasm.yml) or pass --server")
	screenshots = None
	if args.screenshot_dir:
		screenshots = Path(args.screenshot_dir)
		screenshots.mkdir(parents=True, exist_ok=True)

	results: dict[str, dict] = {}
	with create_server(output, "127.0.0.1", 0, quiet=True) as web:
		threading.Thread(target=web.serve_forever, daemon=True).start()
		base = f"http://127.0.0.1:{web.server_address[1]}"
		try:
			with sync_playwright() as playwright:
				browser = playwright.chromium.launch(
					headless=not args.headed, executable_path=args.browser,
					args=["--no-sandbox", "--use-gl=angle", "--use-angle=swiftshader"])
				try:
					for name in chosen:
						# A fresh context per scenario: no storage, no engine state.
						context = browser.new_context(viewport={"width": 1280, "height": 720})
						page = context.new_page()
						console: list[str] = []
						page_errors: list[str] = []
						page.on("console", lambda message, sink=console: sink.append(message.text))
						page.on("pageerror", lambda error, sink=page_errors: sink.append(
							format_page_error(error)))
						try:
							if name == "join":
								results[name] = scenario_join(
									page, base, console, repo, binary, args.game, screenshots)
							elif name == "origin":
								results[name] = scenario_origin(page, base, repo)
							else:
								results[name] = scenario_proxy_down(page, base)
						except BaseException:
							print(f"console tail at failure ({name}):\n" + "\n".join(
								line[:200] for line in console[-40:]))
							raise
						finally:
							context.close()
						assert not page_errors, {"scenario": name, "pageErrors": page_errors,
							"console": console[-30:]}
						print(f"proxy {name}: passed {results[name]}")
				finally:
					browser.close()
		finally:
			web.shutdown()
	print("proxy browser acceptance passed:", ", ".join(results))
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
