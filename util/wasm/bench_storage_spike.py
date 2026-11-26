#!/usr/bin/env python3
# Luanti
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 The Luanti Contributors
"""Storage spike: the same SQLite map workload on IDBFS, WASMFS+OPFS and the
OPFS VFS (src/database/sqlite3_opfs_vfs.cpp).

Builds util/wasm/storage_spike.cpp twice (JS filesystem, WASMFS), then for
each backend in a fresh Chrome profile:

  populate  fill a synthetic map.sqlite to --size-mb
  bench     30 map saves of 200 blocks (commit and durable latency), random
            reads with the browser main thread idle and busy (14 of every
            16 ms, standing in for proxied WebGL), integrity check, heap
  kill      commit 2000-block transactions in a loop, SIGKILL the browser
            mid-transaction, relaunch on the same profile and check the
            database is intact and no reported commit was lost

Prints a Markdown table for wasm_porting.md and the raw JSON.

	python3 util/wasm/bench_storage_spike.py --size-mb 500
"""

from __future__ import annotations

import argparse
import functools
import http.server
import json
import os
import random
import shutil
import signal
import socketserver
import subprocess
import tempfile
import threading
import time
from pathlib import Path

from playwright.sync_api import sync_playwright

REPO = Path(__file__).resolve().parents[2]

IDB_PRE_JS = """
Module["spikeOptions"] = Object.fromEntries(new URLSearchParams(location.search));
if (Module["spikeOptions"]["backend"] === "idbfs") {
	Module["preRun"] = [function() {
		addRunDependency("spike-idbfs");
		FS.mkdir("/idb");
		FS.mount(IDBFS, {}, "/idb");
		FS.syncfs(true, function(error) {
			if (error)
				console.error("spike hydrate", error);
			removeRunDependency("spike-idbfs");
		});
	}];
}
"""

WASMFS_PRE_JS = """
Module["spikeOptions"] = Object.fromEntries(new URLSearchParams(location.search));
"""


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


def build(emcc: str, out: Path, em_cache: str | None) -> None:
	env = os.environ.copy()
	if em_cache:
		env["EM_CACHE"] = em_cache
	(out / "jsfs_pre.js").write_text(IDB_PRE_JS)
	(out / "wasmfs_pre.js").write_text(WASMFS_PRE_JS)
	common = [
		"-O2", "-pthread", "-sPROXY_TO_PTHREAD=1", "-sUSE_SQLITE3=1",
		"-sALLOW_MEMORY_GROWTH=1", "-sINITIAL_MEMORY=64MB",
		"-sMAXIMUM_MEMORY=2GB", "-sEXIT_RUNTIME=0", "-sPTHREAD_POOL_SIZE=4",
		"-sDEFAULT_LIBRARY_FUNCS_TO_INCLUDE=$UTF8ToString,$stringToNewUTF8",
		f"-I{REPO / 'src'}",
	]
	subprocess.run([emcc, str(REPO / "util/wasm/storage_spike.cpp"),
		str(REPO / "src/database/sqlite3_opfs_vfs.cpp"), *common,
		"-sFORCE_FILESYSTEM=1", "-lidbfs.js", "--pre-js", str(out / "jsfs_pre.js"),
		"-o", str(out / "spike-jsfs.html")], check=True, env=env)
	subprocess.run([emcc, str(REPO / "util/wasm/storage_spike.cpp"), *common,
		"-DSPIKE_WASMFS", "-sWASMFS=1", "--pre-js", str(out / "wasmfs_pre.js"),
		"-o", str(out / "spike-wasmfs.html")], check=True, env=env)


def kill_profile(profile: Path) -> None:
	"""SIGKILL every browser process using `profile`, like a crash or a
	force-quit: no pagehide, no unload, no clean shutdown."""
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


def run_page(playwright, browser_path: str, profile: Path, url: str,
		timeout_s: float, *, wait_for: str = "Module.spikeResult !== undefined"):
	context = playwright.chromium.launch_persistent_context(
		str(profile), executable_path=browser_path, headless=True,
		args=["--no-sandbox", "--enable-features=SharedArrayBuffer"])
	page = context.new_page()
	logs: list[str] = []
	page.on("console", lambda message: logs.append(message.text))
	page.goto(url)
	page.wait_for_function(wait_for, timeout=timeout_s * 1000, polling=500)
	return context, page, logs


def bench_backend(playwright, args, base_url: str, backend: str, root: Path) -> dict:
	profile = root / f"profile-{backend}"
	shutil.rmtree(profile, ignore_errors=True)
	page_name = "spike-wasmfs.html" if backend == "wasmfs" else "spike-jsfs.html"
	url = f"{base_url}/{page_name}?backend={backend}"
	result: dict = {"backend": backend}

	def one(action: str, timeout_s: float) -> dict:
		context, page, logs = run_page(playwright, args.browser, profile,
			f"{url}&action={action}&sizeMB={args.size_mb}&seconds={args.read_seconds}",
			timeout_s)
		value = page.evaluate("Module.spikeResult")
		if action == "bench":
			cdp = context.new_cdp_session(page)
			value["mainJsHeapUsedBytes"] = cdp.send("Runtime.getHeapUsage")["usedSize"]
			# Counts typed-array backing stores (where MEMFS keeps file data)
			# and the shared Wasm memory, unlike the V8 heap number above.
			value["pageMemoryBytes"] = page.evaluate("""() => Promise.race([
				performance.measureUserAgentSpecificMemory ?
					performance.measureUserAgentSpecificMemory().then(r => r.bytes) :
					Promise.resolve(null),
				new Promise(resolve => setTimeout(() => resolve(null), 120000))])""")
		context.close()
		if "error" in value:
			raise RuntimeError(f"{backend} {action}: {value['error']}\n" + "\n".join(logs[-20:]))
		return value

	started = time.time()
	result["populate"] = one("populate", 3600)
	print(f"{backend}: populate {result['populate']} ({time.time() - started:.0f} s)", flush=True)
	result["bench"] = one("bench", 3600)
	print(f"{backend}: bench {result['bench']}", flush=True)

	kills = []
	for attempt in range(args.kills):
		context, page, logs = run_page(playwright, args.browser, profile,
			f"{url}&action=kill-writer", 3600,
			wait_for="(Module.spikeCommitted || 0) >= 2")
		# Land somewhere inside a transaction, not right after a commit.
		page.wait_for_timeout(random.randint(50, 900))
		committed = page.evaluate("Module.spikeCommitted")
		kill_profile(profile)
		try:
			context.close()
		except Exception:
			pass
		after = one("verify", 3600)
		kills.append({"reportedCommitted": committed, **after})
		print(f"{backend}: kill {attempt + 1}: {kills[-1]}", flush=True)
	result["kills"] = kills
	return result


def mib(value) -> str:
	return "n/a" if value is None else f"{value / 2**20:.0f}"


def table(results: list[dict]) -> str:
	lines = [
		"| Backend | populate s | save commit p50 / p95 ms | durable p50 / p95 ms | reads/s idle | reads/s busy main | Wasm memory MiB | page memory MiB | kill test |",
		"|---------|-----------|---------------------------|----------------------|--------------|-------------------|-----------------|-----------------|-----------|",
	]
	for r in results:
		p, b = r["populate"], r["bench"]
		kills = r["kills"]
		ok = sum(1 for k in kills if k["integrity"] == "ok" and k["generation"] >= k["reportedCommitted"])
		lines.append(
			f"| {r['backend']} | {(p['insertMs'] + p['syncMs']) / 1000:.0f} | "
			f"{b['commitMs']['p50']:.0f} / {b['commitMs']['p95']:.0f} | "
			f"{b['durableMs']['p50']:.0f} / {b['durableMs']['p95']:.0f} | "
			f"{b['readsPerSecIdle']:.0f} | {b['readsPerSecBusy']:.0f} | "
			f"{b['wasmMemoryBytes'] / 2**20:.0f} | {mib(b.get('pageMemoryBytes'))} | "
			f"{ok} of {len(kills)} intact |")
	return "\n".join(lines)


def main() -> int:
	parser = argparse.ArgumentParser(description=__doc__,
		formatter_class=argparse.RawDescriptionHelpFormatter)
	parser.add_argument("--emcc", default=shutil.which("emcc"))
	parser.add_argument("--browser", default=shutil.which("google-chrome"))
	parser.add_argument("--em-cache", default=os.environ.get("EM_CACHE"))
	parser.add_argument("--size-mb", type=int, default=500)
	parser.add_argument("--read-seconds", type=float, default=3)
	parser.add_argument("--kills", type=int, default=3)
	parser.add_argument("--backends", default="idbfs,wasmfs,vfs")
	parser.add_argument("--json", type=Path, help="write the raw results here")
	args = parser.parse_args()
	if not args.emcc or not args.browser:
		parser.error("emcc and Chrome are required")

	with tempfile.TemporaryDirectory(prefix="luanti-storage-spike-") as directory:
		root = Path(directory)
		build(args.emcc, root, args.em_cache)
		handler = functools.partial(Handler, directory=str(root))
		with Server(("127.0.0.1", 0), handler) as server:
			threading.Thread(target=server.serve_forever, daemon=True).start()
			base_url = f"http://127.0.0.1:{server.server_address[1]}"
			results = []
			with sync_playwright() as playwright:
				for backend in args.backends.split(","):
					results.append(bench_backend(playwright, args, base_url, backend, root))
			server.shutdown()
	print()
	print(f"Synthetic map.sqlite of {args.size_mb} MiB:")
	print(table(results))
	if args.json:
		args.json.write_text(json.dumps(results, indent=2) + "\n")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
