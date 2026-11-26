// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 The Luanti Contributors

// Streamed asset packages.
// This file is included with --pre-js. The engine no longer preloads a single
// luanti.data: util/wasm/build_packages.py writes content-addressed
// assets/<name>.<hash>.data files plus asset-manifest.json, and this service
// downloads them on demand (with byte progress), checks them against the
// manifest hash and writes them into the Emscripten filesystem.
// Package layout is documented in build_packages.py ("LWP1").
// Property names on Module are quoted so they survive Closure.

(function() {
	"use strict";
	// In PROXY_TO_PTHREAD builds this program is also evaluated in workers;
	// the filesystem is owned by the browser main thread.
	if (typeof window === "undefined" && typeof document === "undefined")
		return;

	var MAGIC = "LWP1";
	var manifestUrl = Module["luantiAssetManifestUrl"] || "asset-manifest.json";
	var manifestPromise = null;
	var states = {};

	function emit(name, state, loaded, total, error) {
		var detail = {"name": name, "state": state, "loaded": loaded, "total": total, "error": error || null};
		try {
			window.dispatchEvent(new CustomEvent("luanti:package", {"detail": detail}));
		} catch (_) {}
	}

	function loadManifest() {
		if (!manifestPromise) {
			manifestPromise = fetch(manifestUrl, {"cache": "no-cache"}).then(function(response) {
				if (!response.ok)
					throw new Error("asset-manifest.json: HTTP " + response.status);
				return response.json();
			}).then(function(manifest) {
				if (!manifest || !manifest["packages"] || !manifest["games"])
					throw new Error("asset-manifest.json is malformed");
				return manifest;
			});
			manifestPromise.catch(function() { manifestPromise = null; });
		}
		return manifestPromise;
	}

	function resolve(relative) {
		// Package URLs are relative to the manifest, not to the page.
		return new URL(relative, new URL(manifestUrl, document.baseURI)).href;
	}

	function toHex(buffer) {
		return Array.prototype.map.call(new Uint8Array(buffer), function(byte) {
			return (byte < 16 ? "0" : "") + byte.toString(16);
		}).join("");
	}

	async function download(entry, onBytes) {
		var response = await fetch(resolve(entry["url"]));
		if (!response.ok)
			throw new Error(entry["url"] + ": HTTP " + response.status);
		var expected = entry["bytes"];
		var bytes = new Uint8Array(expected);
		var received = 0;
		if (response.body && response.body.getReader) {
			var reader = response.body.getReader();
			for (;;) {
				var step = await reader.read();
				if (step.done)
					break;
				if (received + step.value.length > expected)
					throw new Error(entry["url"] + ": larger than the manifest says");
				bytes.set(step.value, received);
				received += step.value.length;
				onBytes(received);
			}
		} else {
			var whole = new Uint8Array(await response.arrayBuffer());
			if (whole.length > expected)
				throw new Error(entry["url"] + ": larger than the manifest says");
			bytes.set(whole);
			received = whole.length;
			onBytes(received);
		}
		if (received !== expected)
			throw new Error(entry["url"] + ": truncated (" + received + " of " + expected + " bytes)");
		// Content-addressed: a cache or proxy handing back the wrong bytes
		// must never reach the filesystem.
		if (window.crypto && window.crypto.subtle) {
			var digest = toHex(await window.crypto.subtle.digest("SHA-256", bytes));
			if (digest !== entry["sha256"])
				throw new Error(entry["url"] + ": hash mismatch");
		}
		return bytes;
	}

	function fsReady() {
		return typeof FS !== "undefined" && FS.root && FS.createDataFile;
	}

	function whenFsReady() {
		return new Promise(function(resolveReady) {
			(function check() {
				if (fsReady())
					resolveReady(undefined);
				else
					setTimeout(check, 20);
			})();
		});
	}

	function parseIndex(bytes) {
		var tail = new DataView(bytes.buffer, bytes.byteOffset + bytes.length - 8, 8);
		var magic = String.fromCharCode(bytes[bytes.length - 4], bytes[bytes.length - 3],
			bytes[bytes.length - 2], bytes[bytes.length - 1]);
		if (magic !== MAGIC)
			throw new Error("not a Luanti asset package");
		var length = tail.getUint32(0, true);
		var start = bytes.length - 8 - length;
		if (start < 0)
			throw new Error("corrupt asset package index");
		var text = new TextDecoder().decode(bytes.subarray(start, start + length));
		return {"files": JSON.parse(text)["files"], "payloadEnd": start};
	}

	function mount(bytes) {
		var index = parseIndex(bytes);
		var made = {};
		index["files"].forEach(function(file) {
			if (file["e"] > index["payloadEnd"] || file["s"] > file["e"])
				throw new Error("corrupt asset package entry " + file["p"]);
			var slash = file["p"].lastIndexOf("/");
			var directory = file["p"].slice(0, slash) || "/";
			if (!made[directory]) {
				FS.createPath("/", directory, true, true);
				made[directory] = true;
			}
			FS.createDataFile(directory, file["p"].slice(slash + 1),
				bytes.subarray(file["s"], file["e"]), true, true, true);
		});
		return index["files"].length;
	}

	function loadPackage(name, onProgress) {
		var state = states[name];
		if (state && state.promise) {
			if (onProgress)
				state.listeners.push(onProgress);
			return state.promise;
		}
		state = states[name] = {"name": name, "state": "loading", "loaded": 0, "total": 0,
			"promise": null, "listeners": onProgress ? [onProgress] : []};
		state.promise = loadManifest().then(function(manifest) {
			var entry = manifest["packages"][name];
			if (!entry)
				throw new Error("unknown asset package: " + name);
			state["total"] = entry["bytes"];
			emit(name, "loading", 0, entry["bytes"]);
			return download(entry, function(received) {
				state["loaded"] = received;
				state.listeners.forEach(function(listener) { listener(received, entry["bytes"]); });
				emit(name, "loading", received, entry["bytes"]);
			}).then(function(bytes) {
				return whenFsReady().then(function() {
					mount(bytes);
				});
			});
		}).then(function() {
			state["state"] = "loaded";
			emit(name, "loaded", state["total"], state["total"]);
		}, function(error) {
			// Allow a retry (the user may have been offline).
			state["state"] = "error";
			state.promise = null;
			emit(name, "error", state["loaded"], state["total"], String(error && error.message || error));
			throw error;
		});
		return state.promise;
	}

	function loadAll(names, onProgress) {
		var totals = {};
		var loaded = {};
		function report() {
			var done = 0, sum = 0;
			names.forEach(function(name) {
				done += loaded[name] || 0;
				sum += totals[name] || 0;
			});
			if (onProgress)
				onProgress(done, sum);
		}
		return loadManifest().then(function(manifest) {
			names.forEach(function(name) {
				if (!manifest["packages"][name])
					throw new Error("unknown asset package: " + name);
				totals[name] = manifest["packages"][name]["bytes"];
				loaded[name] = 0;
			});
			report();
			return Promise.all(names.map(function(name) {
				return loadPackage(name, function(received) {
					loaded[name] = received;
					report();
				}).then(function() {
					loaded[name] = totals[name];
					report();
				});
			}));
		});
	}

	function gameEntry(manifest, game) {
		var entry = manifest["games"][game];
		if (!entry)
			throw new Error("This build does not include the game \"" + game + "\".");
		return entry;
	}

	Module["luantiPackages"] = {
		"manifest": loadManifest,
		"load": loadAll,
		"loadCore": function(onProgress) {
			return loadManifest().then(function(manifest) {
				var names = Object.keys(manifest["packages"]).filter(function(name) {
					return manifest["packages"][name]["eager"];
				});
				return loadAll(names, onProgress);
			});
		},
		"loadGame": function(game, onProgress) {
			return loadManifest().then(function(manifest) {
				return loadAll(gameEntry(manifest, game)["packages"], onProgress);
			});
		},
		// Optional content for a game (songs): started after the world is up,
		// one package at a time so it never competes with itself.
		"loadBackground": function(game) {
			return loadManifest().then(function(manifest) {
				var names = gameEntry(manifest, game)["background"] || [];
				return names.reduce(function(chain, name) {
					return chain.then(function() { return loadPackage(name); });
				}, Promise.resolve());
			});
		},
		// Started right away so the engine data downloads while the wasm
		// module compiles; the launcher waits on it before enabling Play.
		"core": null,
		"getStates": function() {
			var result = {};
			Object.keys(states).forEach(function(name) {
				result[name] = {"state": states[name]["state"], "loaded": states[name]["loaded"],
					"total": states[name]["total"]};
			});
			return result;
		}
	};

	var service = Module["luantiPackages"];
	service["core"] = service["loadCore"]();
	// The launcher reports the failure; this only keeps it from also being
	// logged as an unhandled rejection.
	service["core"].catch(function() {});
})();
