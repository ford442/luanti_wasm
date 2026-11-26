#!/usr/bin/env python3
# Luanti
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 The Luanti Contributors
"""The launcher's join flow in Chrome, without the engine.

test_proxy_join.py proves the whole path with the real WebAssembly client, but
it needs the 60-minute build. This test runs the real client/web/shell.html,
launcher scripts and network.js against the real util/wasm/proxy and a UDP echo
server, with a few lines of stand-in for luanti.js (Module.callMain sends a
Luanti-shaped datagram every 100 ms). It is quick enough to run on every change
to client/web, and it pins the page-side contract the engine test relies on.

Scenarios (all by default, --scenario picks one):

  no-proxy    A deployment with no hosted proxy: the server fields and the
              server browser are disabled with the reason beside them; joining
              says so instead of dialling anything; a custom proxy enables them.
  expired     A hosted region past its `expires` date (or with one that does not
              parse) is not offered, and an expired default is not preselected.
  join        A hosted region is shown in the join panel; Join first probes the
              proxy (nothing is sent to the server), then starts the engine; the
              join timeline and the first position packet are recorded.
  origin      The proxy refuses the page's origin: the join fails in the
              launcher with the proxy's reason and the engine never starts.
  proxy-down  Nothing listens at the proxy: the same, with "could not connect".
  target      The proxy allows the page but not the game server: the engine
              starts, the proxy closes with target_denied, the launcher shows its
              reason, and the transport backs off instead of redialling per
              datagram.
  midjoin     The proxy dies mid-session: the launcher reports the lost link, and
              the transport recovers when the proxy is back.

Run: python3 util/wasm/test_join_launcher.py --browser "$(command -v google-chrome)"
(needs `npm ci --prefix util/wasm/proxy` and Playwright for Python).
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
import tempfile
import threading
import time
from typing import Callable, Iterator

from playwright.sync_api import Page, sync_playwright

from serve import create_server
from test_proxy_join import (failed_in_launcher, format_page_error, metric, proxy,
	proxy_events, unused_port)

SCENARIOS = ("no-proxy", "expired", "join", "origin", "proxy-down", "target", "midjoin")
PLAYER = "LauncherTest"
EXAMPLE_PROXY = "wss://proxy.example.org/"

# Stands in for luanti.js: the heap and allocator network.js writes frames
# through, and an engine whose only job is to send what a real one would.
STUB_ENGINE = """
<script>
var HEAPU8 = new Uint8Array(65536);
var heapTop = 1024;
function _malloc(size) { var at = heapTop; heapTop += size; if (heapTop > 60000) heapTop = 1024; return at; }
function _free() {}
</script>
<script src="network.js"></script>
<script>
(function() {
	var engine = window.__engine = {started: false, args: null, received: 0, sent: 0};
	Module.luantiPackages = {
		core: Promise.resolve(), getStates: function() { return {}; },
		loadGame: function() { return Promise.resolve(); },
		loadBackground: function() { return Promise.resolve(); }
	};
	// What test_proxy_join.wait_for_launcher waits for; there is no storage here.
	Module.luantiPersistence = {getState: function() { return {state: "ready"}; }};
	Module._luanti_websocket_proxy_receive = function() { engine.received++; };
	// TOSERVER_INIT (0x02) three times, then TOSERVER_PLAYERPOS (0x23), as an
	// ORIGINAL packet: protocol id, peer id, channel, type 1, command.
	Module.callMain = function(args) {
		engine.started = true;
		engine.args = args;
		var address = args[args.indexOf("--address") + 1];
		var port = Number(args[args.indexOf("--port") + 1]);
		var network = Module.luantiNetwork;
		network._createSocket(1, 20001);
		var tick = 0;
		setInterval(function() {
			var bytes = [0x4f, 0x45, 0x74, 0x03, 0, 2, 0, 1, 0, tick < 3 ? 0x02 : 0x23, 0, 0, 0, 0, 0, 0];
			HEAPU8.set(bytes, 100);
			if (network._send(1, 100, bytes.length, address, port))
				engine.sent++;
			tick++;
		}, 100);
	};
	Module.onRuntimeInitialized();
})();
</script>
"""


class Echo:
	"""A UDP server that answers every datagram with itself."""

	def __init__(self) -> None:
		self.socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
		self.socket.bind(("127.0.0.1", 0))
		self.port = self.socket.getsockname()[1]
		self.received: list[bytes] = []
		threading.Thread(target=self._run, daemon=True).start()

	def _run(self) -> None:
		while True:
			try:
				data, source = self.socket.recvfrom(2048)
			except OSError:
				return
			self.received.append(data)
			self.socket.sendto(data, source)

	def close(self) -> None:
		self.socket.close()


def build_site(directory: Path, repo: Path) -> None:
	"""The shell page with the stand-in engine, and every script it names."""
	web = repo / "client/web"
	html = (web / "shell.html").read_text(encoding="utf-8")
	assert "{{{ SCRIPT }}}" in html, "shell.html lost its engine placeholder"
	(directory / "luanti.html").write_text(html.replace("{{{ SCRIPT }}}", STUB_ENGINE), encoding="utf-8")
	for name in set(re.findall(r'<script src="([^"]+)"', html)) | {"launcher.css", "network.js"}:
		if (web / name).is_file():
			shutil.copy2(web / name, directory / name)
	(directory / "service-worker.js").write_text("// not under test\n", encoding="utf-8")


def write_config(directory: Path, *, default: str = "", proxies: list[dict] | None = None) -> None:
	config = {"serverListUrl": "", "defaultProxy": default, "proxies": proxies or []}
	(directory / "launcher-config.js").write_text(
		"window.LUANTI_WEB_CONFIG = " + json.dumps(config) + ";\n", encoding="utf-8")


def open_launcher(page: Page, base: str, *, remote: bool = True) -> None:
	page.goto(f"{base}/luanti.html?view=60", wait_until="domcontentloaded", timeout=60_000)
	page.wait_for_function("Module.luantiLauncher?.getState().runtimeReady === true", timeout=30_000)
	page.wait_for_function("!document.getElementById('luanti-play-button').disabled", timeout=30_000)
	if remote:
		page.click("#luanti-remote-tab")
		# The proxy picker lives under "Connection & language".
		page.click("details.advanced summary")


def summary(page: Page) -> tuple[str, str]:
	return (page.inner_text("#luanti-proxy-summary"),
		page.get_attribute("#luanti-proxy-summary", "data-state") or "")


def region_options(page: Page) -> list[str]:
	return page.eval_on_selector_all("#luanti-proxy-region option", "o => o.map(x => x.value)")


def server_fields_enabled(page: Page) -> bool:
	states = page.evaluate("""() => ['luanti-address', 'luanti-port', 'luanti-server-list-button']
		.map(id => !document.getElementById(id).disabled)""")
	assert len(set(states)) == 1, f"the server fields disagree about being enabled: {states}"
	return states[0]


def engine(page: Page) -> dict:
	return page.evaluate("({started: __engine.started, args: __engine.args, "
		"sent: __engine.sent, received: __engine.received})")


def join(page: Page, address: str, port: int) -> None:
	page.fill("#luanti-address", address)
	page.fill("#luanti-port", str(port))
	page.fill("#luanti-player-name", PLAYER)
	page.click("#luanti-play-button")


def scenario_no_proxy(page: Page, base: str, site: Path) -> dict:
	write_config(site)
	open_launcher(page, base)
	assert region_options(page) == ["none", "custom"], region_options(page)
	assert not server_fields_enabled(page), "server fields are enabled with no proxy"
	text, state = summary(page)
	assert state == "blocked" and "no multiplayer proxy" in text, (text, state)
	page.fill("#luanti-player-name", PLAYER)
	page.click("#luanti-play-button")
	message = failed_in_launcher(page, "no multiplayer proxy")
	assert page.evaluate("Module.luantiNetwork.getState().state") == "disabled"
	# A custom proxy turns the fields on; a half-typed or wrong one does not.
	page.select_option("#luanti-proxy-region", "custom")
	assert not server_fields_enabled(page)
	assert "Enter your proxy" in summary(page)[0]
	page.fill("#luanti-proxy-url", "https://not-a-proxy.example.org/")
	assert not server_fields_enabled(page)
	assert "starts with wss://" in summary(page)[0]
	page.fill("#luanti-proxy-url", EXAMPLE_PROXY)
	assert server_fields_enabled(page)
	assert summary(page) == ("Proxy: Custom proxy · proxy.example.org", "ready"), summary(page)
	assert not page.evaluate("document.getElementById('luanti-proxy-notice').hidden")
	return {"message": message}


def scenario_expired(page: Page, base: str, site: Path) -> dict:
	eu = "wss://eu.example.org/"
	write_config(site, default=eu, proxies=[
		{"id": "eu", "label": "Europe", "url": eu, "expires": "2020-01-01"},
		{"id": "na", "label": "North America", "url": "wss://na.example.org/", "expires": "2999-01-01"},
		{"id": "ap", "label": "Asia", "url": "wss://ap.example.org/", "expires": "soon"},
		{"id": "sa", "label": "South America", "url": "wss://sa.example.org/"},
	])
	open_launcher(page, base)
	assert region_options(page) == ["none", "na", "sa", "custom"], region_options(page)
	# The default is the expired region: it is neither preselected nor a "custom" URL.
	assert page.input_value("#luanti-proxy-region") == "none"
	assert page.evaluate("Module.luantiProxyUrl") == ""
	assert page.evaluate("document.getElementById('luanti-custom-proxy-row').hidden")
	assert not server_fields_enabled(page)
	assert "Choose a multiplayer proxy region" in summary(page)[0], summary(page)
	page.select_option("#luanti-proxy-region", "na")
	assert server_fields_enabled(page)
	assert summary(page) == ("Proxy: North America · na.example.org", "ready"), summary(page)

	# Every region expired: the page says which one and since when.
	write_config(site, default=eu, proxies=[
		{"id": "eu", "label": "Europe", "url": eu, "expires": "2020-01-01T00:00:00Z"}])
	open_launcher(page, base)
	assert region_options(page) == ["none", "custom"]
	text, state = summary(page)
	assert state == "blocked" and "Europe expired on 2020-01-01" in text, (text, state)
	assert not server_fields_enabled(page)
	return {"options": ["none", "custom"], "message": text}


def hosted(proxy_port: int) -> dict:
	return {"id": "local", "label": "Test region", "url": f"ws://127.0.0.1:{proxy_port}/"}


def scenario_join(page: Page, base: str, site: Path, repo: Path, echo: Echo) -> dict:
	proxy_port = unused_port()
	region = hosted(proxy_port)
	write_config(site, default=region["url"], proxies=[region])
	with proxy(repo, proxy_port, f"127.0.0.1:{echo.port}", base) as relay:
		open_launcher(page, base)
		assert page.input_value("#luanti-proxy-region") == "local"
		assert server_fields_enabled(page)
		assert summary(page) == (f"Proxy: Test region · 127.0.0.1:{proxy_port}", "ready"), summary(page)
		assert page.evaluate("document.getElementById('luanti-proxy-notice').hidden"), \
			"the loopback proxy needs no privacy notice"
		join(page, "127.0.0.1", echo.port)
		page.wait_for_function("__engine.started", timeout=30_000)
		assert not echo.received or echo.received[0][:4] == bytes([0x4f, 0x45, 0x74, 0x03])
		page.wait_for_function("__engine.received >= 5", timeout=30_000)
		page.wait_for_function(
			"Module.luantiNetwork.getTimings().firstPlayerPosMs !== null", timeout=30_000)
		text, state = summary(page)
		assert state == "ready" and re.search(r" · reachable \(\d+ ms\)$", text), (text, state)
		args = engine(page)["args"]
		assert args[args.index("--address") + 1] == "127.0.0.1"
		assert args[args.index("--port") + 1] == str(echo.port)
		assert args[args.index("--name") + 1] == PLAYER

		timings = page.evaluate("Module.luantiNetwork.getTimings()")
		assert timings["joinMarked"] is True, timings
		assert timings["probeMs"] is not None and timings["probeMs"] >= 0, timings
		ordered = [timings[key] for key in (
			"firstSendMs", "proxyOpenMs", "proxyReadyMs", "firstReceiveMs", "firstPlayerPosMs")]
		assert None not in ordered and ordered == sorted(ordered), ordered
		# The probe finished before the engine's first datagram left.
		assert timings["firstSendMs"] >= timings["probeMs"], timings
		assert timings["receivedDatagrams"] >= 5, timings
		assert page.evaluate("document.getElementById('luanti-proxy-alert').hidden")

		events = proxy_events(relay)
		opened = [e for e in events if e.get("event") == "session_opened"]
		# The probe's link and the engine's, both from this page.
		assert len(opened) == 2 and all(e["origin"] == base for e in opened), opened
		closed = [e for e in events if e.get("event") == "session_closed"]
		assert [e["reason"] for e in closed] == ["client_closed"], closed
		assert metric(proxy_port, "luanti_proxy_targets_denied_total") == 0
		assert metric(proxy_port, "luanti_proxy_rate_limited_total") == 0
		return {"timings": timings, "probe": text}


def scenario_origin(page: Page, base: str, site: Path, repo: Path, echo: Echo) -> dict:
	proxy_port = unused_port()
	region = hosted(proxy_port)
	write_config(site, default=region["url"], proxies=[region])
	with proxy(repo, proxy_port, f"127.0.0.1:{echo.port}", "https://play.example.org") as relay:
		open_launcher(page, base)
		join(page, "127.0.0.1", echo.port)
		message = failed_in_launcher(page, f"does not allow pages from {re.escape(base)}")
		assert "WebSocket connection failed" not in message
		page.wait_for_timeout(2500)
		# Exactly one connection: the probe. The engine never dialled the proxy
		# and nothing reached the game server.
		assert metric(proxy_port, "luanti_proxy_connections_rejected_total", '{reason="origin"}') == 1
		assert metric(proxy_port, "luanti_proxy_connections_active") == 0
		assert not echo.received, "a datagram reached the game server"
		assert [e for e in proxy_events(relay) if e.get("event") == "connection_rejected"
			and e.get("reason") == "origin" and e.get("origin") == base]
		# The player can choose another proxy and try again from the same form.
		page.select_option("#luanti-proxy-region", "custom")
		page.fill("#luanti-proxy-url", EXAMPLE_PROXY)
		assert server_fields_enabled(page)
		return {"message": message}


def scenario_proxy_down(page: Page, base: str, site: Path, echo: Echo) -> dict:
	port = unused_port()
	region = hosted(port)
	write_config(site, default=region["url"], proxies=[region])
	open_launcher(page, base)
	join(page, "127.0.0.1", echo.port)
	message = failed_in_launcher(page, rf"^Could not connect to the proxy at 127\.0\.0\.1:{port}\b")
	assert not echo.received
	return {"message": message}


def scenario_target(page: Page, base: str, site: Path, repo: Path, echo: Echo) -> dict:
	proxy_port = unused_port()
	region = hosted(proxy_port)
	write_config(site, default=region["url"], proxies=[region])
	# The page is welcome; the game server is not on the allowlist.
	with proxy(repo, proxy_port, "127.0.0.1:1", base) as relay:
		open_launcher(page, base)
		join(page, "127.0.0.1", echo.port)
		page.wait_for_function("__engine.started", timeout=30_000)
		page.wait_for_function(
			"!document.getElementById('luanti-proxy-alert').hidden", timeout=30_000)
		proxy_state = page.evaluate("Module.luantiLauncher.getState().proxy")
		assert proxy_state["reason"] == "target_denied", proxy_state
		assert proxy_state["closeCode"] == 1008, proxy_state
		assert re.search(rf"^The proxy at 127\.0\.0\.1:{proxy_port} will not forward to that server "
			r"\(UDP target is not allowed\)\.$", proxy_state["message"]), proxy_state
		assert page.inner_text("#luanti-proxy-alert-text") == proxy_state["message"]
		# The engine keeps resending; the transport must back off, not redial for each datagram.
		page.wait_for_timeout(8000)
		denied = [e for e in proxy_events(relay) if e.get("event") == "session_closed"
			and e.get("reason") == "target_denied"]
		assert 1 <= len(denied) <= 6, f"{len(denied)} refused sessions in ~8 s: no backoff?"
		assert metric(proxy_port, "luanti_proxy_targets_denied_total") >= 1
		assert metric(proxy_port, "luanti_proxy_sessions_closed_total", '{reason="target_denied"}') == len(denied)
		assert not echo.received, "the denied server received a datagram"
		return {"message": proxy_state["message"], "refused_sessions": len(denied)}


def scenario_midjoin(page: Page, base: str, site: Path, repo: Path, echo: Echo) -> dict:
	proxy_port = unused_port()
	region = hosted(proxy_port)
	write_config(site, default=region["url"], proxies=[region])
	targets = f"127.0.0.1:{echo.port}"
	with contextlib.ExitStack() as stack:
		relay = stack.enter_context(proxy(repo, proxy_port, targets, base))
		open_launcher(page, base)
		join(page, "127.0.0.1", echo.port)
		page.wait_for_function("__engine.received >= 3", timeout=30_000)
		assert page.evaluate("Module.luantiNetwork.getState().state") == "ready"
		# Die without a close frame: a crash or a dropped connection, not a shutdown.
		os.killpg(relay.process.pid, signal.SIGKILL)
		relay.process.wait(timeout=10)
		page.wait_for_function(
			"Module.luantiNetwork.getState().state === 'error'", timeout=30_000)
		network = page.evaluate("Module.luantiNetwork.getState()")
		assert network["reason"] is None and network["closeCode"] == 1006, network
		assert re.match(rf"^Lost the connection to the proxy at 127\.0\.0\.1:{proxy_port}\b",
			network["error"]), network
		page.wait_for_function(
			"!document.getElementById('luanti-proxy-alert').hidden", timeout=10_000)
		assert page.inner_text("#luanti-proxy-alert-text") == network["error"]
		received_before = engine(page)["received"]
		# The proxy comes back on the same address. The engine is still sending,
		# so the transport redials by itself (it cannot resume the old UDP port:
		# a new WebSocket is a new source port, and the game session with it).
		stack.enter_context(proxy(repo, proxy_port, targets, base))
		page.wait_for_function(
			"Module.luantiNetwork.getState().state === 'ready'", timeout=60_000)
		page.wait_for_function(f"__engine.received > {received_before}", timeout=30_000)
		page.wait_for_function(
			"document.getElementById('luanti-proxy-alert').hidden", timeout=10_000)
		recovered = page.evaluate("Module.luantiNetwork.getState()")
		assert recovered["reason"] is None and recovered["error"] is None, recovered
		return {"lost": network["error"], "state_after_restart": recovered["state"]}


def main() -> int:
	parser = argparse.ArgumentParser(description=__doc__,
		formatter_class=argparse.RawDescriptionHelpFormatter)
	parser.add_argument("--browser", default=shutil.which("google-chrome"),
		help="Chrome executable Playwright should drive")
	parser.add_argument("--scenario", choices=("all", *SCENARIOS), default="all")
	parser.add_argument("--headed", action="store_true")
	args = parser.parse_args()
	if not args.browser:
		parser.error("no browser executable was found; pass --browser")

	repo = Path(__file__).resolve().parents[2]
	chosen = SCENARIOS if args.scenario == "all" else (args.scenario,)
	results: dict[str, dict] = {}
	echo = Echo()
	with tempfile.TemporaryDirectory(prefix="luanti-join-launcher-") as directory:
		site = Path(directory)
		build_site(site, repo)
		with create_server(site, "127.0.0.1", 0, quiet=True) as web:
			threading.Thread(target=web.serve_forever, daemon=True).start()
			base = f"http://127.0.0.1:{web.server_address[1]}"
			try:
				with sync_playwright() as playwright:
					browser = playwright.chromium.launch(
						headless=not args.headed, executable_path=args.browser,
						args=["--no-sandbox"])
					try:
						for name in chosen:
							echo.received.clear()
							# A fresh context per scenario: no storage, no earlier proxy choice.
							context = browser.new_context(viewport={"width": 1280, "height": 720})
							page = context.new_page()
							page_errors: list[str] = []
							console: list[str] = []
							page.on("pageerror", lambda error, sink=page_errors: sink.append(
								format_page_error(error)))
							page.on("console", lambda message, sink=console: sink.append(
								f"{message.type}: {message.text}"))
							runners: dict[str, Callable[[], dict]] = {
								"no-proxy": lambda: scenario_no_proxy(page, base, site),
								"expired": lambda: scenario_expired(page, base, site),
								"join": lambda: scenario_join(page, base, site, repo, echo),
								"origin": lambda: scenario_origin(page, base, site, repo, echo),
								"proxy-down": lambda: scenario_proxy_down(page, base, site, echo),
								"target": lambda: scenario_target(page, base, site, repo, echo),
								"midjoin": lambda: scenario_midjoin(page, base, site, repo, echo),
							}
							try:
								results[name] = runners[name]()
							except BaseException:
								print(f"console tail at failure ({name}):\n" + "\n".join(
									line[:200] for line in console[-25:]))
								raise
							finally:
								context.close()
							assert not page_errors, {"scenario": name, "pageErrors": page_errors}
							print(f"launcher {name}: passed {json.dumps(results[name], default=str)}")
					finally:
						browser.close()
			finally:
				web.shutdown()
				echo.close()
	print("launcher join flow passed:", ", ".join(results))
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
