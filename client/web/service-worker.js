// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 The Luanti Contributors

"use strict";

/** @type {ServiceWorkerGlobalScope} */
var swScope = /** @type {any} */ (self);

// Bump on every packaging change. This worker is a cache-buster only:
// intercepting engine assets previously served stale luanti.wasm after
// a failed network fetch (and then the old ABM/debug logs came back).
// The value is never read: changing it changes the worker bytes, which makes
// the browser install the new worker.
/* exported CACHE_VERSION */
var CACHE_VERSION = "5.17.0-dev-20260819c-lookat";

swScope.addEventListener("install", function(event) {
	event.waitUntil(swScope.skipWaiting());
});

swScope.addEventListener("activate", function(event) {
	event.waitUntil(
		caches.keys().then(function(keys) {
			return Promise.all(keys.map(function(key) {
				return caches.delete(key);
			}));
		}).then(function() {
			return swScope.clients.claim();
		})
	);
});

// Do not handle fetch. Navigations and luanti.{js,wasm,data} go to the
// network so a failed SW fetch cannot revive a cached engine binary.
