#!/usr/bin/env python3
# Luanti
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 The Luanti Contributors
"""Join a Luanti server from the generated WASM client through the proxy.

Two halves. The local scenarios run everything on 127.0.0.1:

  native luantiserver  <--UDP-->  util/wasm/proxy (npm start)  <--WebSocket-->
  Chrome running build-wasm/bin/luanti.html, driven through the launcher's
  "Join server" form (custom proxy URL, address, port, name).

  join        The launcher probes the proxy, the engine completes the handshake
              (PROXY OK), logs TOCLIENT_HELLO and enters the world, the server
              logs the player joining, and a chat line typed in the browser
              arrives in the server log. The join timeline is recorded.
  origin      A proxy that does not allow the page's origin: the join fails in
              the launcher with the proxy's reason and the engine never starts.
  proxy-down  Nothing listens on the proxy address: the same, with "could not
              connect to the proxy".
  target      The proxy allows the page but not the game server: the launcher
              shows the proxy's reason (target_denied), the proxy log and
              metrics show the refusal, the player never reaches the server, and
              the transport backs off instead of redialling per datagram.
  midjoin     The proxy goes away mid-join: the launcher reports the lost link,
              the page stays alive, and the transport recovers when the proxy is
              back (the game session itself cannot resume on a new WebSocket).

The public scenarios run the *deployed* demo page against the *deployed* wss://
proxy and a consenting public server. They are never part of `all`: they need
a deployment and, to see the player on the server, a way to read its log
(docs: util/wasm/proxy/README.md, "Public acceptance"). Configuration is by
flag or environment variable, so a CI job can keep the secret out of the repo:

  public-join    A fresh page on the demo joins the allowlisted server over wss://
                 and the player appears in the server's log. Records the join
                 timeline, RTT and stall counters (the TCP hop measurement).
  public-denied  A target that is not on the allowlist (default 192.0.2.1:30000,
                 a documentation address no allowlist should contain) fails in the
                 launcher with the proxy's reason; the proxy log shows the refusal
                 when it can be read. Nothing is sent to a real third party.
  public-origin  A page from a different origin is refused by the deployed proxy
                 (close code 1008, reason "origin: ..."): the allowlist is not an
                 open relay.

  LUANTI_PUBLIC_PAGE_URL            https URL of the deployed luanti.html
  LUANTI_PUBLIC_SERVER              host:port of the consenting server
  LUANTI_PUBLIC_REGION              launcher proxy region id (default: the page's default)
  LUANTI_PUBLIC_SERVER_LOG_COMMAND  prints the server's recent log (a secret: it may hold a token)
  LUANTI_PUBLIC_PROXY_LOG_COMMAND   prints the proxy's recent JSON log (optional)
  LUANTI_PUBLIC_DENIED_TARGET       host:port that must be refused (default 192.0.2.1:30000)
  LUANTI_PUBLIC_HOLD_SECONDS        how long to stay joined before measuring (default 90)
  LUANTI_PUBLIC_OTHER_ORIGIN        the origin public-origin claims (default https://luanti-acceptance.invalid)

What this does not show: that a proxy is safe to publish (see the "Still needed
on a public host" list in util/wasm/proxy/README.md).
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
from urllib.parse import urlsplit
import uuid

from playwright.sync_api import Page, sync_playwright

from serve import create_server

PLAYER = "ProxyJoin"
LOCAL_SCENARIOS = ("join", "origin", "proxy-down", "target", "midjoin")
PUBLIC_SCENARIOS = ("public-join", "public-denied", "public-origin")
SCENARIOS = (*LOCAL_SCENARIOS, *PUBLIC_SCENARIOS)
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
	"""The launcher's direct-connect flow, as a player would use it.

	The proxy comes first: until one is chosen the server fields are disabled
	(client/web/launcher-connect.js), because a join cannot work without it."""
	page.click("#luanti-remote-tab")
	page.click("details.advanced summary")
	page.select_option("#luanti-proxy-region", "custom")
	page.fill("#luanti-proxy-url", proxy_url)
	page.fill("#luanti-address", address)
	page.fill("#luanti-port", str(port))
	page.fill("#luanti-player-name", PLAYER)


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


def send_chat(page: Page, server: Managed | RemoteLog, text: str, player: str = PLAYER) -> None:
	"""Type a chat line, retrying: early key presses are dropped while the
	engine catches up on its first server steps (see test_first_playable.py)."""
	expected = rf"CHAT: <{player}> {re.escape(text)}"
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


def failed_in_launcher(page: Page, expected: str) -> str:
	"""The join ended on the launcher form, with `expected` in its error line.

	The launcher dials the proxy once before it starts the engine
	(client/web/launcher-connect.js, preflight): a proxy that is down or refuses
	the page fails here, with the proxy's own reason, and the engine never runs."""
	page.wait_for_function(
		"!document.getElementById('luanti-launch-error').hidden", timeout=60_000)
	message = page.inner_text("#luanti-launch-error")
	assert re.search(expected, message), message
	launcher = page.evaluate("Module.luantiLauncher.getState()")
	assert not launcher["started"], f"the engine was started anyway: {launcher}"
	assert page.evaluate("!document.getElementById('luanti-launcher').hidden"), "the launcher is gone"
	assert page.evaluate("document.getElementById('luanti-game-shell').hidden")
	assert page.evaluate("!document.getElementById('luanti-play-button').disabled")
	assert page.inner_text("#luanti-play-label") == "Join server"
	return message


def refused_in_game_shell(page: Page, proxy_state_expected: dict) -> dict:
	"""The proxy closed the link after the engine started: the launcher's alert
	carries the proxy's reason and `getState().proxy` has it for embedders."""
	page.wait_for_function(
		"!document.getElementById('luanti-proxy-alert').hidden", timeout=120_000)
	state = page.evaluate("Module.luantiLauncher.getState().proxy")
	for key, value in proxy_state_expected.items():
		assert state[key] == value, (key, state)
	assert page.inner_text("#luanti-proxy-alert-text") == state["message"], state
	return state


class RemoteLog:
	"""A log this machine cannot read directly. `command` prints its recent
	lines (ssh tail, an authenticated curl, a docker logs call...). The command
	may contain a token, so it is never printed; and because a public server's
	log names other players and addresses, only lines mentioning `needle` are
	ever shown, with addresses blanked."""

	def __init__(self, name: str, command: str | None, needle: str) -> None:
		self.name = name
		self.command = command
		self.needle = needle
		self.matched: list[str] = []

	@property
	def available(self) -> bool:
		return bool(self.command)

	def fetch(self) -> list[str]:
		assert self.command
		result = subprocess.run(self.command, shell=True, capture_output=True, text=True,
			errors="replace", timeout=90)
		if result.returncode != 0:
			raise RuntimeError(f"the {self.name} log command failed ({result.returncode})")
		return result.stdout.splitlines()

	def has(self, pattern: str) -> bool:
		expression = re.compile(pattern)
		for line in self.fetch():
			if expression.search(line):
				self.matched.append(self.redact(line))
				return True
		return False

	def wait_for(self, pattern: str, timeout: float, interval: float = 5.0) -> str:
		expression = re.compile(pattern)
		deadline = time.monotonic() + timeout
		while True:
			for line in self.fetch():
				if expression.search(line):
					return self.redact(line)
			if time.monotonic() >= deadline:
				break
			time.sleep(interval)
		raise AssertionError(f"the {self.name} log never showed /{self.redact(pattern)}/ "
			f"({len(self.matching())} lines mention this run)")

	def matching(self) -> list[str]:
		return [self.redact(line) for line in self.fetch() if self.needle in line]

	def tail(self, count: int = 25) -> str:
		try:
			lines = self.matching()[-count:]
		except Exception as error:  # a diagnostic must not hide the real failure
			return f"  [{self.name}] unreadable: {type(error).__name__}"
		return "\n".join(f"  [{self.name}] {line[:220]}" for line in lines) or \
			f"  [{self.name}] no line mentions this run"

	@staticmethod
	def redact(line: str) -> str:
		"""Blank what a public log says about anyone else: addresses, and the
		player list the server appends to every join."""
		line = re.sub(r"\[[0-9a-fA-F.:]+\]", "[addr]", line)
		return re.sub(r"(List of players:).*$", r"\1 [others redacted]", line)


def join_timings(page: Page) -> dict:
	"""The TCP-hop measurement: see util/wasm/proxy/README.md, "Measuring the TCP hop"."""
	return page.evaluate("""() => ({
		timings: Module.luantiNetwork.getTimings(),
		network: (({url, rttMs, sentPackets, receivedPackets, droppedPackets}) =>
			({url, rttMs, sentPackets, receivedPackets, droppedPackets}))(Module.luantiNetwork.getState())
	})""")


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
				page.wait_for_function(
					"Module.luantiNetwork.getTimings().firstPlayerPosMs !== null", timeout=60_000)
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
			measured = join_timings(page)
			timings = measured["timings"]
			assert timings["joinMarked"] is True, timings
			assert timings["probeMs"] is not None, timings
			assert timings["firstPlayerPosMs"] > timings["proxyReadyMs"] > 0, timings

			events = proxy_events(relay)
			opened = [e for e in events if e.get("event") == "session_opened"]
			# The launcher's probe, then the engine's link.
			assert len(opened) == 2 and all(e["origin"] == origin for e in opened), events
			assert not [e for e in events if e.get("event") == "connection_rejected"], events
			assert not [e for e in events if e.get("event") == "session_closed"
				and e.get("reason") not in ("client_closed",)], events
			forwarded = metric(proxy_port, "luanti_proxy_datagrams_forwarded_total")
			received = metric(proxy_port, "luanti_proxy_datagrams_received_total")
			assert forwarded > 0 and received > 0, (forwarded, received)
			assert metric(proxy_port, "luanti_proxy_rate_limited_total") == 0
			return {"proxy": proxy_url, "web_port": web_port, "server_port": udp_port,
				"datagrams_forwarded": forwarded, "datagrams_received": received,
				"chat": message, **measured}


def scenario_origin(page: Page, base: str, repo: Path) -> dict:
	proxy_port = unused_port()
	allowed = "https://play.example.org"
	with proxy(repo, proxy_port, "127.0.0.1:30000", allowed) as relay:
		page.goto(f"{base}/luanti.html?view=60", wait_until="domcontentloaded", timeout=120_000)
		wait_for_launcher(page)
		fill_join_form(page, "127.0.0.1", 30000, f"ws://127.0.0.1:{proxy_port}/")
		page.click("#luanti-play-button")
		message = failed_in_launcher(page, rf"does not allow pages from {re.escape(base)}")
		assert "WebSocket connection failed" not in message, message
		page.wait_for_timeout(3000)
		# One connection, the launcher's probe: the engine never dialled the proxy.
		rejected = metric(proxy_port, "luanti_proxy_connections_rejected_total", '{reason="origin"}')
		assert rejected == 1, f"{rejected} refused connections: the engine dialled anyway?"
		assert metric(proxy_port, "luanti_proxy_connections_active") == 0
		assert [e for e in proxy_events(relay) if e.get("event") == "connection_rejected"
			and e.get("reason") == "origin" and e.get("origin") == base]
		return {"message": message, "refused_connections": rejected}


def scenario_proxy_down(page: Page, base: str) -> dict:
	port = unused_port()  # nothing listens here once the probe socket closes
	page.goto(f"{base}/luanti.html?view=60", wait_until="domcontentloaded", timeout=120_000)
	wait_for_launcher(page)
	fill_join_form(page, "127.0.0.1", 30000, f"ws://127.0.0.1:{port}/")
	page.click("#luanti-play-button")
	message = failed_in_launcher(page, rf"^Could not connect to the proxy at 127\.0\.0\.1:{port}\b")
	return {"message": message}


def scenario_target(page: Page, base: str, repo: Path, binary: Path, game: str) -> dict:
	proxy_port = unused_port()
	with native_server(binary, repo, game) as (server, udp_port):
		# The page is welcome; the game server is not on the allowlist.
		with proxy(repo, proxy_port, "127.0.0.1:1", base) as relay:
			page.goto(f"{base}/luanti.html?view=60", wait_until="domcontentloaded", timeout=120_000)
			wait_for_launcher(page)
			fill_join_form(page, "127.0.0.1", udp_port, f"ws://127.0.0.1:{proxy_port}/")
			page.click("#luanti-play-button")
			proxy_state = refused_in_game_shell(page, {"reason": "target_denied", "closeCode": 1008})
			assert re.search(rf"^The proxy at 127\.0\.0\.1:{proxy_port} will not forward to that server "
				r"\(UDP target is not allowed\)\.$", proxy_state["message"]), proxy_state
			# The engine resends its handshake; the transport must back off.
			page.wait_for_timeout(8000)
			denied = [e for e in proxy_events(relay) if e.get("event") == "session_closed"
				and e.get("reason") == "target_denied"]
			assert 1 <= len(denied) <= 6, f"{len(denied)} refused sessions in ~8 s: no backoff?"
			assert metric(proxy_port, "luanti_proxy_targets_denied_total") >= 1
			assert metric(proxy_port, "luanti_proxy_sessions_closed_total",
				'{reason="target_denied"}') == len(denied)
			assert not server.has(rf"{PLAYER} \[[0-9.]+\] joins game"), \
				"the player reached a server the proxy was not allowed to forward to"
			return {"message": proxy_state["message"], "refused_sessions": len(denied)}


def scenario_midjoin(page: Page, base: str, console: list[str], repo: Path,
		binary: Path, game: str) -> dict:
	proxy_port = unused_port()
	with native_server(binary, repo, game) as (server, udp_port):
		with contextlib.ExitStack() as stack:
			targets = f"127.0.0.1:{udp_port}"
			relay = stack.enter_context(proxy(repo, proxy_port, targets, base))
			page.goto(f"{base}/luanti.html?view=60", wait_until="domcontentloaded", timeout=120_000)
			wait_for_launcher(page)
			fill_join_form(page, "127.0.0.1", udp_port, f"ws://127.0.0.1:{proxy_port}/")
			page.click("#luanti-play-button")
			page.wait_for_function("Module.luantiNetwork.getState().state === 'ready'", timeout=120_000)
			wait_for_console(page, console, HELLO, 120)
			world_ready = any(WORLD_READY in line for line in console)
			# Die without a close frame: a crash or a dropped connection, not a shutdown.
			os.killpg(relay.process.pid, signal.SIGKILL)
			relay.process.wait(timeout=10)
			lost = refused_in_game_shell(page, {"reason": None, "closeCode": 1006})
			assert re.match(rf"^Lost the connection to the proxy at 127\.0\.0\.1:{proxy_port}\b",
				lost["message"]), lost
			# The page survives it: the main thread still answers and the launcher
			# still reports (no unhandled error is raised, which main() checks).
			assert page.evaluate("1 + 1") == 2
			stack.enter_context(proxy(repo, proxy_port, targets, base))
			# The engine keeps resending, so the transport redials by itself. The
			# Luanti session does not resume (a new WebSocket is a new UDP source
			# port, so the server sees a stranger); that is the engine's timeout to
			# report, not something to hide here.
			page.wait_for_function(
				"Module.luantiNetwork.getState().state === 'ready'", timeout=90_000)
			recovered = page.evaluate("Module.luantiNetwork.getState()")
			assert recovered["reason"] is None and recovered["error"] is None, recovered
			return {"lost": lost["message"], "world_ready_before_kill": world_ready,
				"transport_after_restart": recovered["state"]}


# --- the deployed proxy ---------------------------------------------------

def public_setting(args: argparse.Namespace, name: str, env: str, default: str = "") -> str:
	value = getattr(args, name, None)
	return value if value else os.environ.get(env, default)


def open_public_launcher(page: Page, page_url: str, region: str) -> str:
	"""Load the deployed page, open the join panel and return the chosen region."""
	assert page_url.startswith("https://"), \
		"the deployed demo must be an https page: ws:// is refused there, which is the point"
	separator = "&" if "?" in page_url else "?"
	page.goto(f"{page_url}{separator}view=60", wait_until="domcontentloaded", timeout=120_000)
	# A deployment's index.html redirects to the current release's luanti.html.
	if "luanti.html" not in page.url:
		page.wait_for_url(re.compile(r"luanti\.html"), timeout=60_000)
	wait_for_launcher(page)
	page.click("#luanti-remote-tab")
	page.click("details.advanced summary")
	if region:
		page.select_option("#luanti-proxy-region", region)
	chosen = page.input_value("#luanti-proxy-region")
	assert chosen not in ("none", "custom"), (
		f"the deployed launcher offers no hosted proxy (region {chosen!r}): its "
		"launcher-config.js has no usable entry, or it has expired")
	summary = page.inner_text("#luanti-proxy-summary")
	assert page.get_attribute("#luanti-proxy-summary", "data-state") == "ready", summary
	# The privacy notice is for a proxy that is not on the player's machine,
	# which is every real deployment.
	host = (urlsplit(hosted_proxy_url(page)).hostname or "").lower()
	loopback = host == "localhost" or host.endswith(".localhost") or host == "::1" or host.startswith("127.")
	assert notice_hidden(page) == loopback, (host, "privacy notice does not match the proxy")
	return summary


def hosted_proxy_url(page: Page) -> str:
	"""The wss:// URL of the region the launcher has selected."""
	return page.evaluate("""() => {
		const select = document.getElementById('luanti-proxy-region');
		const entry = (window.LUANTI_WEB_CONFIG.proxies || []).find(p => String(p.id) === select.value);
		return entry.url;
	}""")


def split_target(value: str) -> tuple[str, int]:
	host, _, port = value.rpartition(":")
	assert host and port.isdigit(), f"expected host:port, got {value!r}"
	return host, int(port)


def join_form_public(page: Page, host: str, port: int, name: str) -> None:
	page.fill("#luanti-address", host)
	page.fill("#luanti-port", str(port))
	page.fill("#luanti-player-name", name)
	page.click("#luanti-play-button")


def wait_joined_or_failed(page: Page, expression: str, timeout: float) -> None:
	"""Wait for `expression`; a refusal surfaced by the launcher fails at once with its text."""
	deadline = time.monotonic() + timeout
	while time.monotonic() < deadline:
		status = page.evaluate("""expression => ({
			ok: !!eval(expression),
			form: document.getElementById('luanti-launch-error').hidden ? null :
				document.getElementById('luanti-launch-error').textContent,
			alert: document.getElementById('luanti-proxy-alert').hidden ? null :
				document.getElementById('luanti-proxy-alert-text').textContent
		})""", expression)
		if status["form"] or status["alert"]:
			raise AssertionError("the join failed in the launcher: "
				+ (status["form"] or status["alert"]))
		if status["ok"]:
			return
		page.wait_for_timeout(500)
	raise AssertionError(f"timed out waiting for {expression}")


def scenario_public_join(browser, console: list[str], cfg: argparse.Namespace,
		screenshots: Path | None) -> dict:
	page_url = public_setting(cfg, "public_page", "LUANTI_PUBLIC_PAGE_URL")
	server_address = public_setting(cfg, "public_server", "LUANTI_PUBLIC_SERVER")
	region = public_setting(cfg, "public_region", "LUANTI_PUBLIC_REGION")
	hold = int(public_setting(cfg, "public_hold_seconds", "LUANTI_PUBLIC_HOLD_SECONDS", "90"))
	assert page_url and server_address, "set LUANTI_PUBLIC_PAGE_URL and LUANTI_PUBLIC_SERVER"
	host, port = split_target(server_address)
	player = "ci-" + uuid.uuid4().hex[:8]
	server_log = RemoteLog("server", public_setting(
		cfg, "public_server_log_command", "LUANTI_PUBLIC_SERVER_LOG_COMMAND") or None, player)
	if not server_log.available and not cfg.no_server_log:
		raise AssertionError(
			"no way to read the public server's log: set LUANTI_PUBLIC_SERVER_LOG_COMMAND, or pass "
			"--no-server-log to run without proving the player is visible on the server")

	context = browser.new_context(viewport={"width": 1280, "height": 720})
	page = context.new_page()
	page.on("console", lambda message: console.append(message.text))
	try:
		summary = open_public_launcher(page, page_url, region)
		join_form_public(page, host, port, player)
		wait_joined_or_failed(page, "Module.luantiNetwork.getState().state === 'ready'", 180)
		state = page.evaluate("Module.luantiNetwork.getState()")
		assert state["url"].startswith("wss://"), state
		assert page.evaluate("location.protocol") == "https:"
		wait_for_console(page, console, HELLO, 180)
		wait_for_console(page, console, WORLD_READY, 240)
		page.wait_for_function(
			"Module.luantiNetwork.getTimings().firstPlayerPosMs !== null", timeout=120_000)
		joined_line = None
		if server_log.available:
			joined_line = server_log.wait_for(rf"{re.escape(player)} \[[0-9a-fA-F.:]+\] joins game", 120)
		if screenshots:
			page.screenshot(path=str(screenshots / "public-join-world.png"))
		page.click("#canvas", position={"x": 640, "y": 360})
		page.wait_for_timeout(1500)
		chat = "publicjoin-" + uuid.uuid4().hex[:8]
		if server_log.available:
			send_chat(page, server_log, chat, player)
		# Stay joined so the RTT samples (one per five seconds) and the stall
		# counters mean something.
		deadline = time.monotonic() + hold
		while time.monotonic() < deadline:
			page.wait_for_timeout(5000)
			link = page.evaluate("Module.luantiNetwork.getState()")
			assert link["state"] == "ready" and not link["error"], link
			assert page.evaluate("document.getElementById('luanti-proxy-alert').hidden")
		measured = join_timings(page)
		if screenshots:
			page.screenshot(path=str(screenshots / "public-join-after.png"))
		return {"region": summary, "player_in_server_log": joined_line is not None,
			"server_log_line": joined_line, "chat_in_server_log": server_log.available,
			"held_seconds": hold, **measured}
	except BaseException:
		print("--- server (lines naming this run) ---\n" + server_log.tail(20)
			if server_log.available else "--- server log not readable ---")
		raise
	finally:
		context.close()


def scenario_public_denied(browser, console: list[str], cfg: argparse.Namespace) -> dict:
	page_url = public_setting(cfg, "public_page", "LUANTI_PUBLIC_PAGE_URL")
	region = public_setting(cfg, "public_region", "LUANTI_PUBLIC_REGION")
	denied = public_setting(cfg, "public_denied_target", "LUANTI_PUBLIC_DENIED_TARGET", "192.0.2.1:30000")
	assert page_url, "set LUANTI_PUBLIC_PAGE_URL"
	host, port = split_target(denied)
	player = "ci-" + uuid.uuid4().hex[:8]
	proxy_log = RemoteLog("proxy", public_setting(
		cfg, "public_proxy_log_command", "LUANTI_PUBLIC_PROXY_LOG_COMMAND") or None, "")
	context = browser.new_context(viewport={"width": 1280, "height": 720})
	page = context.new_page()
	page.on("console", lambda message: console.append(message.text))
	try:
		open_public_launcher(page, page_url, region)
		join_form_public(page, host, port, player)
		state = refused_in_game_shell(page, {"reason": "target_denied", "closeCode": 1008})
		assert re.search(r"will not forward to that server", state["message"]), state
		page_ok = page.evaluate("Module.luantiNetwork.getState().state") in ("error", "closed", "connecting")
		assert page_ok
		logged = None
		if proxy_log.available:
			logged = proxy_log.wait_for(r'"event":"session_closed".*"reason":"target_denied"', 90)
		return {"message": state["message"], "proxy_log_checked": proxy_log.available,
			"proxy_log_line": logged and re.sub(r'"ip":"[^"]*"', '"ip":"addr"', logged)}
	finally:
		context.close()


def scenario_public_origin(browser, cfg: argparse.Namespace) -> dict:
	page_url = public_setting(cfg, "public_page", "LUANTI_PUBLIC_PAGE_URL")
	region = public_setting(cfg, "public_region", "LUANTI_PUBLIC_REGION")
	assert page_url, "set LUANTI_PUBLIC_PAGE_URL"
	proxy_log = RemoteLog("proxy", public_setting(
		cfg, "public_proxy_log_command", "LUANTI_PUBLIC_PROXY_LOG_COMMAND") or None, "")
	context = browser.new_context(viewport={"width": 1280, "height": 720})
	page = context.new_page()
	try:
		open_public_launcher(page, page_url, region)
		proxy_url = hosted_proxy_url(page)
		assert proxy_url.startswith("wss://"), proxy_url
		# A page from an origin the proxy has never heard of. The request is
		# answered locally (nothing is fetched from, or claimed to be, a real
		# site); only the Origin header it puts on the WebSocket matters.
		other = public_setting(cfg, "public_other_origin", "LUANTI_PUBLIC_OTHER_ORIGIN",
			"https://luanti-acceptance.invalid")
		other_page = context.new_page()
		other_page.route(f"{other}/**", lambda route: route.fulfill(
			status=200, content_type="text/html", body="<!doctype html><title>other origin</title>"))
		other_page.goto(f"{other}/", wait_until="domcontentloaded")
		result = other_page.evaluate("""url => new Promise(resolve => {
			const socket = new WebSocket(url);
			let opened = false;
			socket.onopen = () => { opened = true; };
			socket.onclose = event => resolve({opened, code: event.code, reason: event.reason});
			setTimeout(() => resolve({opened, timeout: true}), 20000);
		})""", proxy_url)
		assert not result.get("timeout"), result
		# The TLS handshake and the upgrade worked (this is the deployed wss://),
		# and the proxy then refused the origin the way README.md documents.
		assert result["opened"] is True, result
		assert result["code"] == 1008 and result["reason"].startswith("origin:"), result
		logged = None
		if proxy_log.available:
			logged = proxy_log.wait_for(
				r'"event":"connection_rejected".*"reason":"origin".*"origin":"' + re.escape(other) + '"', 90)
		return {"close_code": result["code"], "reason": result["reason"],
			"proxy_log_checked": proxy_log.available,
			"proxy_log_line": logged and re.sub(r'"ip":"[^"]*"', '"ip":"addr"', logged)}
	finally:
		context.close()


def main() -> int:
	parser = argparse.ArgumentParser(description=__doc__,
		formatter_class=argparse.RawDescriptionHelpFormatter)
	parser.add_argument("--browser", default=shutil.which("google-chrome"),
		help="Chrome executable Playwright should drive")
	parser.add_argument("--build", default="build-wasm")
	parser.add_argument("--server", default="bin/luantiserver",
		help="native luantiserver, relative to the repository (default: %(default)s)")
	parser.add_argument("--game", default="devtest")
	parser.add_argument("--scenario", choices=("all", "public", *SCENARIOS), default="all",
		help="`all` is the local scenarios; `public` is the three against a deployment")
	parser.add_argument("--screenshot-dir")
	parser.add_argument("--report", help="write the results (timings included) here as JSON")
	parser.add_argument("--headed", action="store_true")
	public = parser.add_argument_group("public scenarios (each also reads its LUANTI_PUBLIC_* variable)")
	public.add_argument("--public-page")
	public.add_argument("--public-server")
	public.add_argument("--public-region")
	public.add_argument("--public-server-log-command",
		help="shell command that prints the server's recent log; may hold a secret, never echoed")
	public.add_argument("--public-proxy-log-command")
	public.add_argument("--public-denied-target")
	public.add_argument("--public-hold-seconds")
	public.add_argument("--public-other-origin",
		help="the origin public-origin claims (default https://luanti-acceptance.invalid)")
	public.add_argument("--no-server-log", action="store_true",
		help="run public-join without reading the server log. The engine still reaches "
			"the world, but the run does not prove the player is visible on the server")
	args = parser.parse_args()
	if not args.browser:
		parser.error("no browser executable was found; pass --browser")

	repo = Path(__file__).resolve().parents[2]
	if args.scenario == "all":
		chosen: tuple[str, ...] = LOCAL_SCENARIOS
	elif args.scenario == "public":
		chosen = PUBLIC_SCENARIOS
	else:
		chosen = (args.scenario,)
	local = [name for name in chosen if name in LOCAL_SCENARIOS]
	output = (repo / args.build / "bin").resolve()
	if local and not (output / "luanti.html").exists():
		parser.error(f"generated client not found under {output}")
	binary = (repo / args.server).resolve()
	if any(name in ("join", "target", "midjoin") for name in chosen) and not binary.exists():
		parser.error(f"native server not found at {binary}; build it with BUILD_SERVER=TRUE "
			"(see .github/workflows/wasm.yml) or pass --server")
	screenshots = None
	if args.screenshot_dir:
		screenshots = Path(args.screenshot_dir)
		screenshots.mkdir(parents=True, exist_ok=True)

	results: dict[str, dict] = {}

	def run_scenarios(browser, base: str | None) -> None:
		for name in chosen:
			# A fresh context per scenario: no storage, no engine state.
			if name.startswith("public-"):
				console: list[str] = []
				try:
					if name == "public-join":
						results[name] = scenario_public_join(browser, console, args, screenshots)
					elif name == "public-denied":
						results[name] = scenario_public_denied(browser, console, args)
					else:
						results[name] = scenario_public_origin(browser, args)
				except BaseException:
					print(f"console tail at failure ({name}):\n" + "\n".join(
						line[:200] for line in console[-30:]))
					raise
				print(f"proxy {name}: passed {json.dumps(results[name], default=str)}")
				continue
			assert base
			context = browser.new_context(viewport={"width": 1280, "height": 720})
			page = context.new_page()
			console = []
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
				elif name == "proxy-down":
					results[name] = scenario_proxy_down(page, base)
				elif name == "target":
					results[name] = scenario_target(page, base, repo, binary, args.game)
				else:
					results[name] = scenario_midjoin(page, base, console, repo, binary, args.game)
			except BaseException:
				print(f"console tail at failure ({name}):\n" + "\n".join(
					line[:200] for line in console[-40:]))
				raise
			finally:
				context.close()
			assert not page_errors, {"scenario": name, "pageErrors": page_errors,
				"console": console[-30:]}
			print(f"proxy {name}: passed {json.dumps(results[name], default=str)}")

	with sync_playwright() as playwright:
		browser = playwright.chromium.launch(
			headless=not args.headed, executable_path=args.browser,
			args=["--no-sandbox", "--use-gl=angle", "--use-angle=swiftshader"])
		try:
			if local:
				with create_server(output, "127.0.0.1", 0, quiet=True) as web:
					threading.Thread(target=web.serve_forever, daemon=True).start()
					try:
						run_scenarios(browser, f"http://127.0.0.1:{web.server_address[1]}")
					finally:
						web.shutdown()
			else:
				run_scenarios(browser, None)
		finally:
			browser.close()
	if args.report:
		Path(args.report).parent.mkdir(parents=True, exist_ok=True)
		Path(args.report).write_text(json.dumps(results, indent=2, default=str) + "\n", encoding="utf-8")
	print("proxy browser acceptance passed:", ", ".join(results))
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
