#!/usr/bin/env python3
# Luanti
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 The Luanti Contributors
"""Exercise the production WebSocket bridge through a real browser and UDP socket."""

from __future__ import annotations

import argparse
import functools
import http.server
import os
from pathlib import Path
import shutil
import socket
import socketserver
import subprocess
import threading
import time
from urllib.parse import quote

from playwright.sync_api import sync_playwright


class QuietHandler(http.server.SimpleHTTPRequestHandler):
	def log_message(self, format: str, *args: object) -> None:
		pass


class ReusableTCPServer(socketserver.TCPServer):
	allow_reuse_address = True


class ReusableUDPServer(socketserver.ThreadingUDPServer):
	allow_reuse_address = True


class UDPEchoHandler(socketserver.BaseRequestHandler):
	def handle(self) -> None:
		message, udp_socket = self.request
		udp_socket.sendto(message, self.client_address)


def unused_tcp_port() -> int:
	with socket.socket() as probe:
		probe.bind(("127.0.0.1", 0))
		return probe.getsockname()[1]


def wait_for_listener(port: int, process: subprocess.Popen[str]) -> None:
	deadline = time.monotonic() + 10
	while time.monotonic() < deadline:
		if process.poll() is not None:
			stdout, stderr = process.communicate()
			raise RuntimeError(f"proxy exited early: {stdout}\n{stderr}")
		try:
			with socket.create_connection(("127.0.0.1", port), timeout=0.2):
				return
		except OSError:
			time.sleep(0.05)
	raise RuntimeError("proxy did not begin listening")


def main() -> int:
	parser = argparse.ArgumentParser()
	parser.add_argument("--browser", default=shutil.which("google-chrome"))
	args = parser.parse_args()
	if not args.browser:
		parser.error("Google Chrome was not found")

	repo = Path(__file__).resolve().parents[2]
	proxy_directory = repo / "util/wasm/proxy"
	if not (proxy_directory / "node_modules/ws").exists():
		parser.error("run npm install in util/wasm/proxy first")

	with ReusableUDPServer(("127.0.0.1", 0), UDPEchoHandler) as echo:
		echo_thread = threading.Thread(target=echo.serve_forever, daemon=True)
		echo_thread.start()
		target_port = echo.server_address[1]
		proxy_port = unused_tcp_port()
		environment = os.environ.copy()
		environment.update({
			"LUANTI_PROXY_HOST": "127.0.0.1",
			"LUANTI_PROXY_PORT": str(proxy_port),
			"LUANTI_PROXY_ALLOWED_TARGETS": f"127.0.0.1:{target_port}",
		})
		proxy = subprocess.Popen(
			["node", "server.mjs"], cwd=proxy_directory, env=environment,
			stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
		try:
			wait_for_listener(proxy_port, proxy)
			handler = functools.partial(QuietHandler, directory=repo)
			with ReusableTCPServer(("127.0.0.1", 0), handler) as web:
				web_thread = threading.Thread(target=web.serve_forever, daemon=True)
				web_thread.start()
				with sync_playwright() as playwright:
					browser = playwright.chromium.launch(
						headless=True, executable_path=args.browser,
						args=["--no-sandbox"])
					page = browser.new_page()
					messages: list[str] = []
					page.on("console", lambda message: messages.append(
						f"console {message.type}: {message.text}"))
					page.on("pageerror", lambda error: messages.append(
						f"pageerror: {error}"))
					proxy_url = quote(f"ws://127.0.0.1:{proxy_port}", safe="")
					url = (f"http://127.0.0.1:{web.server_address[1]}/"
						f"util/wasm/network_browser_probe.html?proxy={proxy_url}")
					page.goto(url)
					page.evaluate("""targetPort => {
						Module.luantiNetwork._createSocket(11, 20011);
						HEAPU8.set([11, 22, 33, 44], 64);
						if (!Module.luantiNetwork._send(
								11, 64, 4, "127.0.0.1", targetPort))
							throw new Error("browser bridge rejected the datagram");
					}""", target_port)
					try:
						page.wait_for_function(
							"Module.luantiNetworkProbe.received.length === 1",
							timeout=10_000)
					except Exception as error:
						state = page.evaluate("Module.luantiNetwork.getState()")
						raise RuntimeError(
							f"browser proxy probe timed out; state={state}; "
							f"messages={messages}") from error
					result = page.evaluate("""({
						state: Module.luantiNetwork.getState(),
						received: Module.luantiNetworkProbe.received,
						status: document.getElementById("luanti-network-status").textContent
					})""")
					browser.close()
				web.shutdown()

			assert result["received"] == [{
				"handle": 11,
				"payload": [11, 22, 33, 44],
				"address": 0x7F000001,
				"port": target_port,
			}], result
			assert result["state"]["state"] == "ready", result
			assert result["state"]["sentPackets"] == 1, result
			assert result["state"]["receivedPackets"] == 1, result
			assert result["status"].startswith("Multiplayer proxy connected"), result
			print("browser WebSocket-to-UDP smoke passed:", result)
		finally:
			proxy.terminate()
			try:
				proxy.wait(timeout=5)
			except subprocess.TimeoutExpired:
				proxy.kill()
			echo.shutdown()

	return 0


if __name__ == "__main__":
	raise SystemExit(main())
