// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 The Luanti Contributors

"use strict";

// Bump when packaging a new engine/shell so activate() drops stale caches.
// Development rebuilds also rely on network-first for mutable binaries below.
var CACHE_VERSION = "5.17.0-dev-20260816c";
var CACHE_NAME = "luanti-web:" + CACHE_VERSION + ":" + self.registration.scope;

var PRECACHE = [
	"./luanti.html",
	"./launcher.css",
	"./launcher-config.js",
	"./manifest.webmanifest",
	"./luanti-web.svg"
];

// These change every rebuild; never prefer a stale cache entry over the network.
var NETWORK_FIRST = [
	"/luanti.js",
	"/luanti.wasm",
	"/luanti.data",
	"/launcher.js",
	"/service-worker.js"
];

function isNetworkFirst(pathname) {
	return NETWORK_FIRST.some(function(suffix) {
		return pathname.endsWith(suffix) || pathname.endsWith(suffix.slice(1));
	});
}

self.addEventListener("install", function(event) {
	event.waitUntil(
		caches.open(CACHE_NAME).then(function(cache) {
			return cache.addAll(PRECACHE);
		}).then(function() {
			return self.skipWaiting();
		})
	);
});

self.addEventListener("activate", function(event) {
	event.waitUntil(
		caches.keys().then(function(keys) {
			return Promise.all(keys.filter(function(key) {
				return key.indexOf("luanti-web:") === 0 && key !== CACHE_NAME;
			}).map(function(key) {
				return caches.delete(key);
			}));
		}).then(function() {
			return self.clients.claim();
		})
	);
});

function withIsolationHeaders(response) {
	// Cached/network responses must keep COOP+COEP so pthreads keep working.
	if (!response || !response.status)
		return response;
	var headers = new Headers(response.headers);
	headers.set("Cross-Origin-Opener-Policy", "same-origin");
	headers.set("Cross-Origin-Embedder-Policy", "require-corp");
	headers.set("Cross-Origin-Resource-Policy", "cross-origin");
	return new Response(response.body, {
		status: response.status,
		statusText: response.statusText,
		headers: headers
	});
}

function putInCache(request, response) {
	if (!response || !response.ok)
		return;
	var copy = response.clone();
	caches.open(CACHE_NAME).then(function(cache) {
		cache.put(request, copy);
	});
}

self.addEventListener("fetch", function(event) {
	if (event.request.method !== "GET")
		return;
	var requestUrl = new URL(event.request.url);
	if (requestUrl.origin !== self.location.origin ||
			!requestUrl.href.startsWith(self.registration.scope))
		return;

	if (isNetworkFirst(requestUrl.pathname)) {
		event.respondWith(
			fetch(event.request).then(function(response) {
				putInCache(event.request, response);
				return withIsolationHeaders(response);
			}).catch(function() {
				return caches.match(event.request).then(function(cached) {
					return withIsolationHeaders(cached);
				});
			})
		);
		return;
	}

	event.respondWith(caches.match(event.request).then(function(cached) {
		if (cached)
			return withIsolationHeaders(cached);
		return fetch(event.request).then(function(response) {
			putInCache(event.request, response);
			return withIsolationHeaders(response);
		});
	}));
});
