#!/usr/bin/env python3
# Luanti
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 The Luanti Contributors
"""Serve a Luanti WebAssembly build with its required isolation headers."""

from __future__ import annotations

import argparse
import functools
import http.server
from pathlib import Path
import socketserver


class CrossOriginIsolatedHandler(http.server.SimpleHTTPRequestHandler):
	extensions_map = {
		**http.server.SimpleHTTPRequestHandler.extensions_map,
		".data": "application/octet-stream",
		".wasm": "application/wasm",
	}

	def __init__(
			self, *args: object, directory: str, quiet: bool = False,
			**kwargs: object) -> None:
		self.quiet = quiet
		super().__init__(*args, directory=directory, **kwargs)

	def end_headers(self) -> None:
		self.send_header("Cross-Origin-Opener-Policy", "same-origin")
		self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
		# The demo is intentionally embeddable from an isolated parent origin.
		# Its own COEP still protects every nested resource load.
		self.send_header("Cross-Origin-Resource-Policy", "cross-origin")
		self.send_header("Cache-Control", "no-store")
		self.send_header("X-Content-Type-Options", "nosniff")
		super().end_headers()

	def log_message(self, format: str, *args: object) -> None:
		if not self.quiet:
			super().log_message(format, *args)


class ReusableTCPServer(socketserver.ThreadingTCPServer):
	allow_reuse_address = True
	daemon_threads = True


def create_server(
		directory: Path, bind: str, port: int, *, quiet: bool = False,
		) -> ReusableTCPServer:
	if not directory.is_dir():
		raise FileNotFoundError(f"directory does not exist: {directory}")
	handler = functools.partial(
		CrossOriginIsolatedHandler, directory=str(directory), quiet=quiet)
	return ReusableTCPServer((bind, port), handler)


def main() -> int:
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument("--directory", default="build-wasm/bin")
	parser.add_argument("--bind", default="127.0.0.1")
	parser.add_argument("--port", default=8000, type=int)
	args = parser.parse_args()

	directory = Path(args.directory).resolve()
	with create_server(directory, args.bind, args.port) as server:
		host = "localhost" if args.bind in {"0.0.0.0", "::"} else args.bind
		entrypoint = "/luanti.html" if (directory / "luanti.html").is_file() else "/"
		print(f"Serving {directory} at http://{host}:{server.server_address[1]}{entrypoint}")
		print("COOP/COEP enabled; press Ctrl-C to stop")
		try:
			server.serve_forever()
		except KeyboardInterrupt:
			pass
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
