// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 The Luanti Contributors

// World database storage on the Origin Private File System.
//
// This --pre-js runs after persistence.js and before worlds.js. It decides,
// before callMain, whether world databases (worlds/<world>/*.sqlite and their
// journals) live in OPFS, and publishes the decision as
// Module.luantiStorage.backend ("opfs" or "idbfs"). The engine reads it in
// porting::emscripten_init_world_storage() and opens those files through the
// SQLite VFS in src/database/sqlite3_opfs_vfs.cpp, which owns them while the
// engine runs. Everything else stays on IDBFS (persistence.js).
//
// OPFS is used only when a dedicated worker can open a
// FileSystemSyncAccessHandle (what the VFS needs) and this page can write
// with createWritable (what the world library needs for import and
// duplicate). Otherwise worlds stay on IDBFS as before. ?storage=idbfs or
// Module.luantiStorageOptions = {"backend": "idbfs"} forces the old backend.
//
// A world on OPFS has a marker file in its IDBFS directory naming a random
// storage id; its databases are luanti-worlds/<id>/<file> in OPFS. The
// helpers below are what worlds.js uses to list, size, copy, export, import
// and delete them; they only run before callMain, like the library itself.

(function() {
	"use strict";
	if (typeof window === "undefined" && typeof document === "undefined")
		return;

	var OPFS_ROOT = "luanti-worlds";
	var MARKER_FILE = "web_opfs_id.txt";
	// An id no marker points at is deleted only once nothing in it changed
	// for this long, so a world another tab created but has not synced to
	// IndexedDB yet is never touched.
	var ORPHAN_AGE_MS = 24 * 60 * 60 * 1000;
	var dependencyName = "luanti-storage-backend";

	var options = Module["luantiStorageOptions"] || {};
	var sizes = new Map();
	var root = null;
	var api = {
		"backend": "idbfs",
		"reason": "pending",
		"engineState": null,
		"migrations": [],
		"markerFile": MARKER_FILE,
		"opfsRoot": OPFS_ROOT
	};
	Module["luantiStorage"] = api;

	function requestedBackend() {
		var value = options["backend"];
		if (!value && typeof location !== "undefined") {
			try {
				value = new URLSearchParams(location.search).get("storage");
			} catch (_) {}
		}
		return value === "idbfs" || value === "opfs" ? value : "auto";
	}

	// Sync access handles exist only in dedicated workers, so the page asks
	// one. It also proves OPFS is usable in this profile (it is not, for
	// example, in some private windows).
	function probeWorker() {
		var source = [
			"onmessage = async function(event) {",
			"  try {",
			"    if (typeof FileSystemFileHandle === 'undefined' ||",
			"        typeof FileSystemFileHandle.prototype.createSyncAccessHandle !== 'function')",
			"      throw new Error('no FileSystemSyncAccessHandle in workers');",
			"    var root = await navigator.storage.getDirectory();",
			"    var dir = await root.getDirectoryHandle(event.data, {create: true});",
			"    var file = await dir.getFileHandle('.luanti-probe-page', {create: true});",
			"    var access = await file.createSyncAccessHandle();",
			"    access.close();",
			"    await dir.removeEntry('.luanti-probe-page');",
			"    postMessage({ok: true});",
			"  } catch (error) {",
			"    postMessage({ok: false, reason: String(error && error.message || error)});",
			"  }",
			"};"
		].join("\n");
		return new Promise(function(resolve) {
			var url = null;
			var worker = null;
			var timer = setTimeout(function() { finish({"ok": false, "reason": "probe timed out"}); }, 5000);
			function finish(result) {
				clearTimeout(timer);
				if (worker)
					worker.terminate();
				if (url)
					URL.revokeObjectURL(url);
				resolve(result);
			}
			try {
				url = URL.createObjectURL(new Blob([source], {"type": "text/javascript"}));
				worker = new Worker(url);
				worker.onmessage = function(event) {
					finish({"ok": !!event.data.ok, "reason": event.data.reason || null});
				};
				worker.onerror = function(event) {
					finish({"ok": false, "reason": "probe worker failed: " + (event.message || "error")});
				};
				worker.postMessage(OPFS_ROOT);
			} catch (error) {
				finish({"ok": false, "reason": String(error && error.message || error)});
			}
		});
	}

	async function decide() {
		var requested = requestedBackend();
		if (requested === "idbfs")
			return {"ok": false, "reason": "requested"};
		if (typeof navigator === "undefined" || !navigator.storage ||
				typeof navigator.storage.getDirectory !== "function")
			return {"ok": false, "reason": "no OPFS"};
		if (typeof FileSystemFileHandle === "undefined" ||
				typeof FileSystemFileHandle.prototype.createWritable !== "function")
			return {"ok": false, "reason": "no createWritable"};
		if (typeof Worker !== "function" || typeof Blob !== "function")
			return {"ok": false, "reason": "no workers"};
		var probe = await probeWorker();
		if (!probe["ok"])
			return probe;
		root = await (await navigator.storage.getDirectory()).getDirectoryHandle(OPFS_ROOT, {"create": true});
		return {"ok": true, "reason": requested === "opfs" ? "requested" : "supported"};
	}

	function isId(value) {
		return typeof value === "string" && /^[0-9a-f]{32}$/.test(value);
	}

	async function idDirectory(id, create) {
		if (!root || !isId(id))
			throw new Error("Invalid world storage id");
		return root.getDirectoryHandle(id, {"create": !!create});
	}

	// [{name, size, mtime, file}] for one id; [] if it does not exist.
	async function listFiles(id) {
		var out = [];
		var dir;
		try {
			dir = await idDirectory(id, false);
		} catch (error) {
			if (error && error.name === "NotFoundError")
				return out;
			throw error;
		}
		for await (var entry of dir.values()) {
			if (entry.kind !== "file")
				continue;
			var file = await entry.getFile();
			out.push({"name": entry.name, "size": file.size, "mtime": file.lastModified, "file": file});
		}
		out.sort(function(a, b) { return a["name"] < b["name"] ? -1 : a["name"] > b["name"] ? 1 : 0; });
		return out;
	}

	async function refresh(id) {
		var total = 0;
		var count = 0;
		(await listFiles(id)).forEach(function(file) {
			total += file["size"];
			count++;
		});
		if (count)
			sizes.set(id, {"bytes": total, "files": count});
		else
			sizes.delete(id);
		return sizes.get(id) || {"bytes": 0, "files": 0};
	}

	async function removeId(id) {
		sizes.delete(id);
		if (!root || !isId(id))
			return;
		try {
			await root.removeEntry(id, {"recursive": true});
		} catch (error) {
			if (!error || error.name !== "NotFoundError")
				throw error;
		}
	}

	function newId() {
		var bytes = new Uint8Array(16);
		crypto.getRandomValues(bytes);
		return Array.prototype.map.call(bytes, function(byte) {
			return (byte < 16 ? "0" : "") + byte.toString(16);
		}).join("");
	}

	function readMarker(worldPath) {
		try {
			var text = new TextDecoder().decode(FS.readFile(worldPath + "/" + MARKER_FILE)).trim();
			return isId(text) ? text : null;
		} catch (_) {
			return null;
		}
	}

	function writeMarker(worldPath, id) {
		FS.writeFile(worldPath + "/" + MARKER_FILE, id + "\n");
	}

	async function writer(id, name) {
		var dir = await idDirectory(id, true);
		var handle = await dir.getFileHandle(name, {"create": true});
		return handle.createWritable({"keepExistingData": false});
	}

	async function copyId(from, to, onBytes) {
		var files = await listFiles(from);
		for (var i = 0; i < files.length; i++) {
			var output = await writer(to, files[i]["name"]);
			try {
				var reader = files[i]["file"].stream().getReader();
				for (;;) {
					var next = await reader.read();
					if (next.done)
						break;
					await output.write(next.value);
					if (onBytes)
						onBytes(next.value.length);
				}
				await output.close();
			} catch (error) {
				output.abort().catch(function() {});
				throw error;
			}
		}
		await refresh(to);
	}

	// World databases the VFS routes to OPFS: <name>.sqlite and SQLite's
	// companion files, directly in the world directory.
	function isDatabaseFile(rel) {
		return /^[^/]+\.sqlite(-journal|-wal|-shm|-mj[0-9A-Za-z]*)?$/.test(rel) &&
			rel.indexOf(".sqlite") > 0;
	}

	function referencedIds() {
		var ids = new Set();
		var worlds = "/home/web_user/.luanti/worlds";
		try {
			FS.readdir(worlds).forEach(function(name) {
				if (name === "." || name === "..")
					return;
				var id = readMarker(worlds + "/" + name);
				if (id)
					ids.add(id);
			});
		} catch (_) {}
		return ids;
	}

	// Sizes for the library, and removal of storage ids no world points at
	// any more (a world deleted from the engine's own main menu leaves its
	// databases behind). The OPFS listing is taken before the markers are
	// read, so an id created after it is never considered.
	async function scan() {
		var listed = [];
		for await (var entry of root.values()) {
			if (entry.kind === "directory" && isId(entry.name))
				listed.push(entry.name);
		}
		await new Promise(function(resolve) {
			var persistence = Module["luantiPersistence"];
			var state = persistence && persistence["getState"] ? persistence["getState"]() : null;
			if (!state || state["state"] !== "loading")
				return resolve(undefined);
			window.addEventListener("luanti:persistence", function listener(event) {
				var detail = /** @type {CustomEvent} */ (event).detail || {};
				if (detail["state"] !== "loading") {
					window.removeEventListener("luanti:persistence", listener);
					resolve(undefined);
				}
			});
		});
		var persistenceState = Module["luantiPersistence"] && Module["luantiPersistence"]["getState"]();
		var safeToCollect = !persistenceState || !persistenceState["fatal"];
		var referenced = referencedIds();
		var removed = [];
		for (var i = 0; i < listed.length; i++) {
			var id = listed[i];
			var files = await listFiles(id);
			var total = 0;
			var newest = 0;
			files.forEach(function(file) {
				total += file["size"];
				newest = Math.max(newest, file["mtime"]);
			});
			if (!referenced.has(id) && safeToCollect && Date.now() - newest > ORPHAN_AGE_MS) {
				try {
					await removeId(id);
					removed.push(id);
				} catch (error) {
					console.warn("Luanti: could not remove unused world storage " + id, error);
				}
				continue;
			}
			sizes.set(id, {"bytes": total, "files": files.length});
		}
		if (removed.length)
			console.info("Luanti: removed " + removed.length + " unused world storage folder(s)");
		api["orphansRemoved"] = removed;
	}

	var readyResolve;
	var readyPromise = new Promise(function(resolve) { readyResolve = resolve; });

	Object.assign(api, {
		"ready": function() { return readyPromise; },
		"enabled": function() { return api["backend"] === "opfs"; },
		"isDatabaseFile": isDatabaseFile,
		"readMarker": readMarker,
		"writeMarker": writeMarker,
		"newId": newId,
		"sizeOf": function(id) {
			return (id && sizes.get(id)) || {"bytes": 0, "files": 0};
		},
		"files": listFiles,
		"refresh": refresh,
		"remove": removeId,
		"copy": copyId,
		"writer": writer
	});

	var originalPreRun = Module["preRun"];
	if (!Array.isArray(originalPreRun))
		originalPreRun = originalPreRun ? [originalPreRun] : [];
	Module["preRun"] = originalPreRun;
	Module["preRun"].push(function() {
		addRunDependency(dependencyName);
		decide().catch(function(error) {
			return {"ok": false, "reason": String(error && error.message || error)};
		}).then(function(result) {
			api["backend"] = result["ok"] ? "opfs" : "idbfs";
			api["reason"] = result["reason"] || null;
			if (!result["ok"] && result["reason"] !== "requested")
				console.info("Luanti: world databases stay in IndexedDB (" + result["reason"] + ")");
			// The engine may start now; the scan below only feeds the library.
			removeRunDependency(dependencyName);
			return result["ok"] ? scan() : null;
		}).catch(function(error) {
			console.warn("Luanti: world storage scan failed", error);
		}).then(function() {
			readyResolve(undefined);
		});
	});
})();
