#!/usr/bin/env python3
# Luanti
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 The Luanti Contributors
"""Unit tests for the local server and deployment packager."""

from __future__ import annotations

import http.client
import json
from pathlib import Path
import tempfile
import threading
import unittest

from package_demo import REQUIRED_OUTPUTS, package_demo
from serve import create_server


class DemoToolsTest(unittest.TestCase):
	def test_package_is_versioned_and_content_addressed(self) -> None:
		with tempfile.TemporaryDirectory() as temporary:
			root = Path(temporary)
			source = root / "bin"
			source.mkdir()
			for index, name in enumerate(REQUIRED_OUTPUTS):
				(source / name).write_bytes(f"artifact {index}\n".encode())

			destination = root / "site"
			manifest = package_demo(source, destination, "abc123")
			stored = json.loads((destination / "version.json").read_text())
			self.assertEqual(stored, manifest)
			self.assertEqual(stored["entrypoint"], "releases/abc123/luanti.html")
			headers = (destination / "_headers").read_text()
			self.assertIn("immutable", headers)
			self.assertIn("/releases/:version/service-worker.js\n  Cache-Control: no-cache", headers)
			for name in REQUIRED_OUTPUTS:
				self.assertEqual(
					(source / name).read_bytes(),
					(destination / "releases" / "abc123" / name).read_bytes())

	def test_server_sends_isolation_headers_and_wasm_type(self) -> None:
		with tempfile.TemporaryDirectory() as temporary:
			root = Path(temporary)
			(root / "probe.wasm").write_bytes(b"\0asm")
			with create_server(root, "127.0.0.1", 0, quiet=True) as server:
				thread = threading.Thread(target=server.serve_forever, daemon=True)
				thread.start()
				try:
					connection = http.client.HTTPConnection(
						"127.0.0.1", server.server_address[1], timeout=5)
					connection.request("GET", "/probe.wasm")
					response = connection.getresponse()
					self.assertEqual(response.status, 200)
					self.assertEqual(response.getheader("Content-Type"), "application/wasm")
					self.assertEqual(
						response.getheader("Cross-Origin-Opener-Policy"), "same-origin")
					self.assertEqual(
						response.getheader("Cross-Origin-Embedder-Policy"), "require-corp")
					self.assertEqual(
						response.getheader("Cross-Origin-Resource-Policy"), "cross-origin")
					response.read()
					connection.close()
				finally:
					server.shutdown()


if __name__ == "__main__":
	unittest.main()
