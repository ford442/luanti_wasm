// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 The Luanti Contributors

"use strict";

var CACHE_NAME = "luanti-web:" + self.registration.scope;
var PRECACHE = [
	"./luanti.html",
	"./luanti.js",
	"./luanti.wasm",
	"./luanti.data",
	"./launcher.js",
	"./launcher.css",
	"./launcher-config.js",
	"./manifest.webmanifest",
	"./luanti-web.svg"
];

self.addEventListener("install", function(event) {
	event.waitUntil(caches.open(CACHE_NAME).then(function(cache) {
		return cache.addAll(PRECACHE);
	}));
});

self.addEventListener("activate", function(event) {
	// Release URLs are immutable, and an older open tab may still depend on its
	// own scope. Do not delete another release's cache here.
	event.waitUntil(self.clients.claim());
});

self.addEventListener("fetch", function(event) {
	if (event.request.method !== "GET")
		return;
	var requestUrl = new URL(event.request.url);
	if (requestUrl.origin !== self.location.origin ||
			!requestUrl.href.startsWith(self.registration.scope))
		return;
	event.respondWith(caches.match(event.request).then(function(cached) {
		if (cached)
			return cached;
		return fetch(event.request).then(function(response) {
			if (response.ok) {
				var copy = response.clone();
				caches.open(CACHE_NAME).then(function(cache) {
					cache.put(event.request, copy);
				});
			}
			return response;
		});
	}));
});
