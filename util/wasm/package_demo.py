#!/usr/bin/env python3
# Luanti
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 The Luanti Contributors
"""Package one coherent, cache-safe Luanti WASM deployment."""

from __future__ import annotations

import argparse
import hashlib
import html
import json
from pathlib import Path
import re
import shutil


REQUIRED_OUTPUTS = (
	"luanti.html", "luanti.js", "luanti.wasm", "luanti.data",
	"launcher.js", "launcher.css", "launcher-config.js",
	"manifest.webmanifest", "service-worker.js", "luanti-web.svg",
)
VERSION_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")


def digest(path: Path) -> str:
	hash_value = hashlib.sha256()
	with path.open("rb") as source:
		for chunk in iter(lambda: source.read(1024 * 1024), b""):
			hash_value.update(chunk)
	return hash_value.hexdigest()


def package_demo(source: Path, destination: Path, version: str) -> dict[str, object]:
	if not VERSION_PATTERN.fullmatch(version):
		raise ValueError("version must contain only letters, numbers, dots, dashes, or underscores")
	if destination.exists():
		raise FileExistsError(f"destination already exists: {destination}")

	missing = [name for name in REQUIRED_OUTPUTS if not (source / name).is_file()]
	if missing:
		raise FileNotFoundError(f"missing generated WASM outputs: {', '.join(missing)}")

	release = destination / "releases" / version
	release.mkdir(parents=True)
	files: dict[str, dict[str, object]] = {}
	for name in REQUIRED_OUTPUTS:
		target = release / name
		shutil.copy2(source / name, target)
		files[name] = {"bytes": target.stat().st_size, "sha256": digest(target)}

	manifest: dict[str, object] = {
		"version": version,
		"entrypoint": f"releases/{version}/luanti.html",
		"files": files,
	}
	(destination / "version.json").write_text(
		json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")

	entrypoint = manifest["entrypoint"]
	quoted_entrypoint = html.escape(str(entrypoint), quote=True)
	(destination / "index.html").write_text(f"""<!doctype html>
<html lang="en">
<head>
	<meta charset="utf-8">
	<meta name="viewport" content="width=device-width, initial-scale=1">
	<meta http-equiv="refresh" content="0; url={quoted_entrypoint}">
	<title>Luanti WebAssembly</title>
</head>
<body>
	<p>Opening <a href="{quoted_entrypoint}">Luanti WebAssembly {html.escape(version)}</a>…</p>
</body>
</html>
""", encoding="utf-8")

	(destination / "404.html").write_text("""<!doctype html>
<html lang="en"><meta charset="utf-8"><title>Not found</title>
<p>This Luanti WebAssembly build was not found. Return to <a href="/">the current build</a>.</p>
""", encoding="utf-8")

	(destination / "_headers").write_text("""/*
  Cross-Origin-Opener-Policy: same-origin
  Cross-Origin-Embedder-Policy: require-corp
  Cross-Origin-Resource-Policy: cross-origin
  X-Content-Type-Options: nosniff
  Referrer-Policy: no-referrer

/index.html
  Cache-Control: no-store

/version.json
  Cache-Control: no-store

/releases/:version/luanti.html
  Cache-Control: public, max-age=31536000, immutable

/releases/:version/luanti.js
  Cache-Control: public, max-age=31536000, immutable

/releases/:version/luanti.wasm
  Cache-Control: public, max-age=31536000, immutable

/releases/:version/luanti.data
  Cache-Control: public, max-age=31536000, immutable

/releases/:version/launcher.js
  Cache-Control: public, max-age=31536000, immutable

/releases/:version/launcher.css
  Cache-Control: public, max-age=31536000, immutable

/releases/:version/launcher-config.js
  Cache-Control: public, max-age=31536000, immutable

/releases/:version/manifest.webmanifest
  Cache-Control: public, max-age=31536000, immutable

/releases/:version/luanti-web.svg
  Cache-Control: public, max-age=31536000, immutable

/releases/:version/service-worker.js
  Cache-Control: no-cache
""", encoding="utf-8")
	return manifest


def main() -> int:
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument("--build", default="build-wasm/bin", help="directory containing luanti.html")
	parser.add_argument("--output", default="wasm-demo", help="new deployment directory")
	parser.add_argument(
		"--version", required=True,
		help="immutable build identifier, normally a Git SHA")
	args = parser.parse_args()

	manifest = package_demo(
		Path(args.build).resolve(), Path(args.output).resolve(), args.version)
	print(json.dumps(manifest, indent=2, sort_keys=True))
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
