// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 The Luanti Contributors

"use strict";

// A narrow, versioned cache. History: an earlier worker intercepted every
// engine asset and, when a fetch failed, replayed an old luanti.wasm next to
// a new luanti.js. The rules below exist so that cannot happen again; the
// stale-binary regression test is util/wasm/test_service_worker_browser.py.
//
//  1. Identity. build_packages.py replaces BUILD_ID with a hash of every
//     shell file listed in asset-manifest.json, so the worker's own bytes
//     change exactly when the engine or launcher does (that is also what makes
//     the browser install the update). Content-only changes ship as new
//     hashed packages and need no new worker. An unstamped worker stays inert.
//  2. Atomic shell. On install the worker downloads the whole shell listed in
//     asset-manifest.json (page, engine, launcher), refuses any file whose
//     size or, for luanti.js / luanti.wasm, SHA-256 differs from the manifest
//     and keeps nothing unless every file is good. A half-deployed build
//     therefore never installs, and the previous worker keeps its own
//     complete set.
//  3. Network first for the shell. The fetch handler never writes the shell
//     cache. It answers from it only when fetch() itself rejects (offline),
//     never for an HTTP error status, so a 404/500 is reported as such and
//     cannot be papered over with an old binary.
//  4. Asset packages (assets/<name>.<hash>.data) are content-addressed, so
//     the worker serves them cache-first forever and only evicts superseded
//     versions of a package the current manifest knows.
//  5. Updates wait. A new worker does not take over until the page asks (the
//     launcher's "new version available" button posts SKIP_WAITING).

/** @type {ServiceWorkerGlobalScope} */
var swScope = /** @type {any} */ (self);

var BUILD_ID = "__LUANTI_BUILD_ID__";
var ACTIVE = BUILD_ID.indexOf("__") !== 0;
var SHELL_PREFIX = "luanti-shell:";
var ASSET_CACHE = "luanti-assets";
var SHELL_CACHE = SHELL_PREFIX + BUILD_ID;
var SCOPE = swScope.registration.scope;
var MANIFEST_URL = new URL("asset-manifest.json", SCOPE).href;
var ASSET_PATTERN = /\/assets\/([A-Za-z0-9_-]+)\.([0-9a-f]{12})\.data$/;

/** @param {ArrayBuffer} buffer */
function hex(buffer) {
	return Array.prototype.map.call(new Uint8Array(buffer), function(byte) {
		return (byte < 16 ? "0" : "") + byte.toString(16);
	}).join("");
}

/**
 * @param {string} url
 * @returns {Promise<Response>}
 */
async function fetchFresh(url) {
	var response = await fetch(new Request(url, {cache: "reload"}));
	if (!response.ok)
		throw new Error(url + ": HTTP " + response.status);
	return response;
}

async function precache() {
	var manifestResponse = await fetchFresh(MANIFEST_URL);
	var manifest = await manifestResponse.clone().json();
	if (!manifest || manifest.buildId !== BUILD_ID) {
		// The server is already on another build than this worker was stamped
		// for; installing would mix them. Let the newer worker take over.
		throw new Error("asset-manifest.json is for build " + (manifest && manifest.buildId) +
			", not " + BUILD_ID);
	}
	await caches.delete(SHELL_CACHE);
	var cache = await caches.open(SHELL_CACHE);
	try {
		var names = Object.keys(manifest.shell || {});
		for (var i = 0; i < names.length; i++) {
			var meta = manifest.shell[names[i]];
			var url = new URL(names[i], SCOPE).href;
			var response = await fetchFresh(url);
			var body = await response.clone().arrayBuffer();
			if (body.byteLength !== meta.bytes)
				throw new Error(names[i] + ": size " + body.byteLength + " != manifest " + meta.bytes);
			if (meta.verify) {
				var digest = hex(await crypto.subtle.digest("SHA-256", body));
				if (digest !== meta.sha256)
					throw new Error(names[i] + ": SHA-256 does not match the manifest");
			}
			await cache.put(url, response);
		}
		await cache.put(MANIFEST_URL, manifestResponse);
	} catch (error) {
		await caches.delete(SHELL_CACHE);
		throw error;
	}
	// Engine data for offline use. Best effort: a failure here must not keep
	// the verified shell from installing.
	try {
		var assets = await caches.open(ASSET_CACHE);
		var packages = Object.keys(manifest.packages || {});
		for (var j = 0; j < packages.length; j++) {
			var entry = manifest.packages[packages[j]];
			if (!entry.eager)
				continue;
			var assetUrl = new URL(entry.url, MANIFEST_URL).href;
			if (!(await assets.match(assetUrl))) {
				var asset = await fetchFresh(assetUrl);
				await assets.put(assetUrl, asset);
			}
		}
	} catch (_) {
		// Fetched (and cached) by the page on first use instead.
	}
}

async function cleanup() {
	var keys = await caches.keys();
	// One shell cache at a time, whatever scope installed it: older release
	// directories are never visited again and would otherwise pile up.
	await Promise.all(keys.filter(function(key) {
		return key.indexOf(SHELL_PREFIX) === 0 && key !== SHELL_CACHE;
	}).map(function(key) { return caches.delete(key); }));

	var shell = await caches.open(SHELL_CACHE);
	var stored = await shell.match(MANIFEST_URL);
	if (!stored)
		return;
	var manifest = await stored.json();
	var current = {};
	Object.keys(manifest.packages || {}).forEach(function(name) {
		current[name] = new URL(manifest.packages[name].url, MANIFEST_URL).href;
	});
	var assets = await caches.open(ASSET_CACHE);
	var cached = await assets.keys();
	await Promise.all(cached.map(function(request) {
		var match = ASSET_PATTERN.exec(new URL(request.url).pathname);
		// Only a superseded version of a package we know is evicted.
		if (match && current[match[1]] && current[match[1]] !== request.url)
			return assets.delete(request);
		return undefined;
	}));
}

swScope.addEventListener("install", function(event) {
	if (!ACTIVE)
		return;
	// No skipWaiting(): an update waits for the user (see SKIP_WAITING below).
	event.waitUntil(precache());
});

swScope.addEventListener("activate", function(event) {
	if (!ACTIVE)
		return;
	event.waitUntil(cleanup().then(function() {
		return swScope.clients.claim();
	}));
});

swScope.addEventListener("message", function(event) {
	if (event.data && event.data.type === "SKIP_WAITING")
		swScope.skipWaiting();
});

/**
 * @param {Request} request
 * @returns {Promise<Response | undefined>}
 */
async function matchShell(request) {
	var cache = await caches.open(SHELL_CACHE);
	var url = new URL(request.url);
	if (request.mode === "navigate")
		return (await cache.match(new URL("luanti.html", SCOPE).href)) || undefined;
	return cache.match(url.origin + url.pathname);
}

/** @param {Request} request */
async function networkFirst(request) {
	try {
		return await fetch(request);
	} catch (error) {
		// Only a rejected fetch (no response at all) falls back to the cache.
		var cached = await matchShell(request);
		if (cached)
			return cached;
		throw error;
	}
}

/**
 * @param {FetchEvent} event
 * @param {Request} request
 */
async function assetFirst(event, request) {
	var cache = await caches.open(ASSET_CACHE);
	var hit = await cache.match(request.url);
	if (hit)
		return hit;
	var response = await fetch(request);
	if (response.status === 200 && response.type === "basic")
		event.waitUntil(cache.put(request.url, response.clone()).catch(function() {}));
	return response;
}

swScope.addEventListener("fetch", function(event) {
	var request = event.request;
	if (!ACTIVE || request.method !== "GET")
		return;
	// Media (theater clips) streams with Range requests; the Cache API cannot
	// answer those, so leave them entirely to the network.
	if (request.headers.has("range"))
		return;
	var url = new URL(request.url);
	if (url.origin !== new URL(SCOPE).origin)
		return;
	if (ASSET_PATTERN.test(url.pathname)) {
		event.respondWith(assetFirst(event, request));
		return;
	}
	// Anything else inside the scope is shell: the page, the engine, the
	// launcher and the manifest. Files outside the shell have no cache entry,
	// so for them this is a plain pass-through that only differs in how a
	// rejected fetch is reported.
	var scopePath = new URL(SCOPE).pathname;
	if (url.pathname.indexOf(scopePath) === 0)
		event.respondWith(networkFirst(request));
});
