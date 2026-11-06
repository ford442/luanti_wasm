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

from build_packages import (
	PackageError, build_all, build_package, load_config, read_index, stamp_service_worker)
from package_demo import REQUIRED_OUTPUTS, package_demo
from serve import create_server

REPO = Path(__file__).resolve().parents[2]


def make_build(root: Path) -> Path:
	"""A fake generated build: shell files, two asset packages, a manifest."""
	tree = root / "tree"
	(tree / "core").mkdir(parents=True)
	(tree / "game").mkdir()
	(tree / "core/a.txt").write_text("core a")
	(tree / "game/b.txt").write_text("game b")
	(tree / "worker.js").write_text('var BUILD_ID = "__LUANTI_BUILD_ID__";\n')
	source = root / "bin"
	source.mkdir()
	for index, name in enumerate(REQUIRED_OUTPUTS):
		(source / name).write_bytes(f"artifact {index}\n".encode())
	config = {
		"schema": 1,
		"packages": {
			"core": {"eager": True, "mounts": [{"src": "core", "dest": "/core"}]},
			"game": {"mounts": [{"src": "game", "dest": "/game"}]},
		},
		"games": {"demo": {"packages": ["game"]}},
		"shell": ["luanti.html", "luanti.js", "luanti.wasm"],
		"verified": ["luanti.wasm"],
		"serviceWorker": "worker.js",
	}
	build_all(tree, config, source, shell_dir=source)
	# The stamped worker replaces the placeholder copy in the fake build.
	return source


class DemoToolsTest(unittest.TestCase):
	def test_package_is_versioned_and_content_addressed(self) -> None:
		with tempfile.TemporaryDirectory() as temporary:
			root = Path(temporary)
			source = make_build(root)
			destination = root / "site"
			manifest = package_demo(source, destination, "abc123")
			stored = json.loads((destination / "version.json").read_text())
			self.assertEqual(stored, manifest)
			self.assertEqual(stored["entrypoint"], "releases/abc123/luanti.html")
			headers = (destination / "_headers").read_text()
			self.assertIn("immutable", headers)
			self.assertIn("/releases/:version/service-worker.js\n  Cache-Control: no-cache", headers)
			self.assertIn("/assets/*\n  Cache-Control: public, max-age=31536000, immutable", headers)
			self.assertIn(
				"/releases/:version/asset-manifest.json\n  Cache-Control: no-cache", headers)
			self.assertNotIn("luanti.data", headers)
			for name in REQUIRED_OUTPUTS:
				self.assertEqual(
					(source / name).read_bytes(),
					(destination / "releases" / "abc123" / name).read_bytes())

			# Packages are shared between releases, so their urls point at /assets/.
			release = json.loads(
				(destination / "releases/abc123/asset-manifest.json").read_text())
			for package in release["packages"].values():
				self.assertTrue(package["url"].startswith("../../assets/"), package["url"])
				stored_file = destination / "assets" / Path(package["url"]).name
				self.assertEqual(stored_file.stat().st_size, package["bytes"])

	def test_package_refuses_a_tampered_asset(self) -> None:
		with tempfile.TemporaryDirectory() as temporary:
			root = Path(temporary)
			source = make_build(root)
			victim = next((source / "assets").glob("core.*.data"))
			victim.write_bytes(victim.read_bytes()[:-1] + b"X")
			with self.assertRaises(ValueError):
				package_demo(source, root / "site", "abc123")

	def test_packages_are_deterministic_and_round_trip(self) -> None:
		config = load_config(REPO / "util/wasm/packages.json")
		first, count = build_package(REPO, config["packages"]["flower_island"])
		second, _ = build_package(REPO, config["packages"]["flower_island"])
		self.assertEqual(first, second)
		index = read_index(first)
		self.assertEqual(len(index), count)
		for entry in index:
			source = REPO / "games/flower_island" / entry["p"].removeprefix("/games/flower_island/")
			self.assertEqual(first[entry["s"]:entry["e"]], source.read_bytes())

	def test_package_config_covers_every_game_and_shell_file(self) -> None:
		config = load_config(REPO / "util/wasm/packages.json")
		# Every game offered by the launcher has a package.
		shell = (REPO / "client/web/shell.html").read_text()
		import re
		offered = set(re.findall(r'<option value="([a-z_]+)"[^>]*>', shell.split('id="luanti-game"')[1]
			.split("</select>")[0]))
		self.assertEqual(offered, set(config["games"]), "launcher games vs packages.json")
		# Songs stay out of the game package and in their own, background ones.
		luanti_web, _ = build_package(REPO, config["packages"]["luanti_web"])
		self.assertFalse(any("/lw_amps/songs/" in e["p"] and e["p"].endswith(".ogg")
			for e in read_index(luanti_web)))
		songs = set()
		for name in config["games"]["luanti_web"]["background"]:
			data, _ = build_package(REPO, config["packages"][name])
			songs |= {e["p"].rsplit("/", 1)[1] for e in read_index(data)}
		on_disk = {p.name for p in (REPO / "games/luanti_web/mods/lw_amps/songs").glob("*.ogg")}
		self.assertEqual(songs, on_disk, "every song is in a background package")
		# core is what every visitor downloads before the first frame.
		core, _ = build_package(REPO, config["packages"]["core"])
		self.assertLessEqual(len(core), 12 * 1024 * 1024, "first-visit budget (wasm_porting.md)")

	def test_service_worker_stamping(self) -> None:
		source = (REPO / "client/web/service-worker.js").read_text()
		stamped = stamp_service_worker(source, "abc")
		self.assertIn('var BUILD_ID = "abc";', stamped)
		self.assertNotIn("__LUANTI_BUILD_ID__", stamped)
		with self.assertRaises(PackageError):
			stamp_service_worker("no placeholder", "abc")

	def test_missing_asset_manifest_is_reported(self) -> None:
		with tempfile.TemporaryDirectory() as temporary:
			root = Path(temporary)
			source = make_build(root)
			(source / "asset-manifest.json").unlink()
			with self.assertRaises(FileNotFoundError):
				package_demo(source, root / "site", "abc123")

	def test_server_sends_isolation_headers_and_wasm_type(self) -> None:
		with tempfile.TemporaryDirectory() as temporary:
			root = Path(temporary)
			(root / "probe.wasm").write_bytes(b"\0asm")
			(root / "assets").mkdir()
			(root / "assets/core.0123456789ab.data").write_bytes(b"x")
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
					connection.request("GET", "/assets/core.0123456789ab.data")
					response = connection.getresponse()
					self.assertEqual(
						response.getheader("Cache-Control"),
						"public, max-age=31536000, immutable")
					response.read()
					connection.request("GET", "/probe.wasm")
					response = connection.getresponse()
					self.assertEqual(response.getheader("Cache-Control"), "no-store")
					response.read()
					connection.close()
				finally:
					server.shutdown()


if __name__ == "__main__":
	unittest.main()
