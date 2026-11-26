#!/usr/bin/env python3
# Luanti
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 The Luanti Contributors
"""World databases on OPFS in a real browser: migration from IDBFS, the
fallback, and a browser killed in the middle of a save.

Builds util/wasm/storage_probe.cpp with the production persistence.js and
storage.js and the VFS in src/database/sqlite3_opfs_vfs.cpp, then on one
persistent Chrome profile:

1. ?storage=idbfs: write a world (the old backend), and a world whose
   map.sqlite is not a database.
2. OPFS: the old world still opens from IDBFS; migration copies it, passes
   PRAGMA integrity_check, writes the marker and drops the IDBFS copy. The
   broken world fails its check and is left exactly as it was.
3. After a reload the migrated world reads from OPFS with every row.
4. ?storage=idbfs again: the migrated world refuses to open instead of
   starting over empty.
5. A new world on OPFS commits in a loop; the browser is SIGKILLed mid-
   transaction (no pagehide, no unload), relaunched, and the world is intact
   with no reported commit lost. Repeated --kills times.

	python3 util/wasm/test_storage_browser.py --browser "$(command -v google-chrome)"
"""

from __future__ import annotations

import argparse
import functools
import http.server
import os
import random
import shutil
import signal
import socketserver
import subprocess
import tempfile
import threading
from pathlib import Path

from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parents[2]


class Handler(http.server.SimpleHTTPRequestHandler):
	def end_headers(self) -> None:
		self.send_header("Cross-Origin-Opener-Policy", "same-origin")
		self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
		self.send_header("Cache-Control", "no-store")
		super().end_headers()

	def log_message(self, format: str, *args: object) -> None:
		pass


class Server(socketserver.ThreadingTCPServer):
	allow_reuse_address = True
	daemon_threads = True


def kill_profile(profile: Path) -> None:
	"""SIGKILL every browser process of `profile`, like a crash."""
	for entry in Path("/proc").iterdir():
		if not entry.name.isdigit():
			continue
		try:
			cmdline = (entry / "cmdline").read_bytes().decode(errors="replace")
		except OSError:
			continue
		if str(profile) in cmdline:
			try:
				os.kill(int(entry.name), signal.SIGKILL)
			except OSError:
				pass


class Session:
	def __init__(self, playwright, browser: str, profile: Path, base: str) -> None:
		self.playwright = playwright
		self.browser = browser
		self.profile = profile
		self.base = base
		self.context = None
		self.page = None
		self.logs: list[str] = []

	def open(self, query: str = ""):
		self.close()
		self.context = self.playwright.chromium.launch_persistent_context(
			str(self.profile), executable_path=self.browser, headless=True,
			args=["--no-sandbox", "--enable-features=SharedArrayBuffer"])
		self.page = self.context.new_page()
		self.page.on("console", lambda message: self.logs.append(message.text))
		self.page.goto(f"{self.base}/probe.html{query}")
		self.page.wait_for_function(
			"typeof runtimeInitialized !== 'undefined' && runtimeInitialized && "
			"typeof Module.callMain === 'function'")
		return self.page

	def run(self, *argv: str, query: str = "", expect_error: bool = False) -> dict:
		page = self.open(query)
		page.evaluate("argv => Module.callMain(argv)", list(argv))
		page.wait_for_function("Module.luantiStorageProbe !== undefined", timeout=120000)
		result = page.evaluate("Module.luantiStorageProbe")
		if ("error" in result) != expect_error:
			raise AssertionError(f"{argv}: {result}\n" + "\n".join(self.logs[-20:]))
		return result

	def flush_small_files(self) -> None:
		"""Wait until persistence.js has nothing left to write."""
		self.page.evaluate("""() => Module.luantiPersistence.requestSync({
			reason: "external", urgent: true})""")

	def close(self) -> None:
		if self.context:
			try:
				self.context.close()
			except Exception:
				pass
		self.context = None
		self.page = None


def main() -> int:
	parser = argparse.ArgumentParser(description=__doc__,
		formatter_class=argparse.RawDescriptionHelpFormatter)
	parser.add_argument("--emcc", default=shutil.which("emcc"))
	parser.add_argument("--browser", default=shutil.which("google-chrome"))
	parser.add_argument("--em-cache", default=os.environ.get("EM_CACHE"))
	parser.add_argument("--kills", type=int, default=3)
	args = parser.parse_args()
	if not args.emcc or not args.browser:
		parser.error("emcc and Chrome are required")

	with tempfile.TemporaryDirectory(prefix="luanti-storage-") as directory:
		out = Path(directory)
		env = os.environ.copy()
		if args.em_cache:
			env["EM_CACHE"] = args.em_cache
		subprocess.run([
			args.emcc, str(REPO / "util/wasm/storage_probe.cpp"),
			str(REPO / "src/database/sqlite3_opfs_vfs.cpp"), f"-I{REPO / 'src'}",
			"-O1", "-pthread", "-sPROXY_TO_PTHREAD=1", "-sUSE_SQLITE3=1",
			"-sFORCE_FILESYSTEM=1", "-sEXIT_RUNTIME=0", "-sALLOW_MEMORY_GROWTH=1",
			"-sPTHREAD_POOL_SIZE=4", "-sEXPORTED_RUNTIME_METHODS=callMain",
			"-sDEFAULT_LIBRARY_FUNCS_TO_INCLUDE=$UTF8ToString",
			"-lidbfs.js",
			"--pre-js", str(REPO / "client/web/persistence.js"),
			"--pre-js", str(REPO / "client/web/storage.js"),
			"--shell-file", str(REPO / "client/web/shell.html"),
			"-o", str(out / "probe.html"),
		], check=True, env=env)

		profile = out / "profile"
		handler = functools.partial(Handler, directory=str(out))
		with Server(("127.0.0.1", 0), handler) as server:
			threading.Thread(target=server.serve_forever, daemon=True).start()
			base = f"http://127.0.0.1:{server.server_address[1]}"
			with sync_playwright() as playwright:
				s = Session(playwright, args.browser, profile, base)

				# 1. The old backend.
				r = s.run("write", "Legacy", "150", query="?storage=idbfs")
				assert r["state"] == "disabled" and r["rows"] == 150, r
				assert s.page.evaluate("Module.luantiStorage.backend") == "idbfs"
				s.page.evaluate("""() => {
					FS.mkdir("/home/web_user/.luanti/worlds/Broken");
					FS.writeFile("/home/web_user/.luanti/worlds/Broken/map.sqlite",
						"this is not an SQLite database, it only has the name");
				}""")
				s.flush_small_files()

				# 2. OPFS: the old world still opens where it is, then migrates.
				r = s.run("read", "Legacy")
				assert r["state"] == "ready", r
				assert s.page.evaluate("Module.luantiStorage.backend") == "opfs"
				assert r["rows"] == 150 and not r["opfs"] and r["jsCopy"], r
				r = s.run("migrate")
				assert r["worlds"]["Legacy"]["result"] == "migrated", r
				assert r["worlds"]["Broken"]["result"] == "failed", r
				assert s.page.evaluate("""() => FS.readFile(
					"/home/web_user/.luanti/worlds/Broken/map.sqlite", {encoding: "utf8"})""") \
					== "this is not an SQLite database, it only has the name"
				assert not s.page.evaluate("""() => FS.analyzePath(
					"/home/web_user/.luanti/worlds/Broken/web_opfs_id.txt").exists""")
				s.flush_small_files()

				# 3. After a reload the migrated world is read from OPFS.
				r = s.run("read", "Legacy")
				assert r["opfs"] and not r["jsCopy"], r
				assert r["rows"] == 150 and r["integrity"] == "ok", r
				print("migration: ok (150 rows, integrity ok, IDBFS copy removed; "
					"broken world left untouched)")

				# 4. Without OPFS the world is refused, not recreated empty.
				r = s.run("read", "Legacy", query="?storage=idbfs", expect_error=True)
				assert "open" in r["error"], r
				print("fallback: a world on OPFS refuses to open without it")

				# 5. Killed mid-save.
				r = s.run("write", "Fresh", "200")
				assert r["rows"] == 200, r
				s.flush_small_files()
				for attempt in range(args.kills):
					page = s.open()
					page.evaluate("Module.callMain(['kill-writer', 'Fresh'])")
					page.wait_for_function(
						"(Module.luantiStorageProbe?.generation || 0) >= 2", timeout=120000)
					page.wait_for_timeout(random.randint(30, 400))
					reported = page.evaluate("Module.luantiStorageProbe.generation")
					kill_profile(profile)
					s.close()
					r = s.run("read", "Fresh")
					assert r["integrity"] == "ok", r
					assert r["rows"] == 200, r
					assert r["generation"] >= reported, (reported, r)
					print(f"kill {attempt + 1}: committed {reported} before the kill, "
						f"{r['generation']} after, integrity ok")
				s.close()
			server.shutdown()
	print("OPFS world storage browser test passed")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
