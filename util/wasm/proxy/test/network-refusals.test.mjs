// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 The Luanti Contributors

// client/web/network.js against the real proxy: what a page is told when the
// proxy refuses it or cannot be reached. The page's WebSocket is the `ws`
// client with an Origin header, which fails an upgrade the way a browser does:
// close code 1006 and no reason. Whatever message these tests see therefore
// had to come from the proxy's close frame.

import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import net from "node:net";
import test from "node:test";
import vm from "node:vm";
import {WebSocket as NodeWebSocket} from "ws";
import {parseAllowedOrigins} from "../policy.mjs";
import {createProxyServer} from "../server.mjs";

const source = await readFile(new URL("../../../../client/web/network.js", import.meta.url), "utf8");
const quiet = () => {};

function listening(server) {
	if (server.address())
		return Promise.resolve();
	return new Promise((resolve, reject) => {
		server.once("listening", resolve);
		server.once("error", reject);
	});
}

async function startProxy(options = {}) {
	const server = createProxyServer({
		host: "127.0.0.1", port: 0, allowPublic: false, allowedTargets: new Set(),
		log: quiet, ...options,
	});
	await listening(server);
	return {server, url: `ws://127.0.0.1:${server.address().port}/`};
}

async function unusedPort() {
	const probe = net.createServer();
	await new Promise(resolve => probe.listen(0, "127.0.0.1", () => resolve(undefined)));
	const {port} = /** @type {net.AddressInfo} */ (probe.address());
	await new Promise(resolve => probe.close(() => resolve(undefined)));
	return port;
}

// Loads network.js the way the page does and records what it tells the launcher.
function loadPage({proxyUrl, pageOrigin}) {
	const heap = new Uint8Array(4096);
	const statuses = [];
	const constructed = [];
	class PageWebSocket extends NodeWebSocket {
		constructor(url) {
			super(url, {origin: pageOrigin});
			// A browser reports failures as events; `ws` would throw instead.
			/** @type {any} */ (this).on("error", () => {});
			constructed.push(url);
		}
	}
	const context = {
		ArrayBuffer, CustomEvent: class {
			constructor(type, options) {
				this.type = type;
				this.detail = options.detail;
			}
		},
		DataView, HEAPU8: heap, Map, URL, URLSearchParams, Uint8Array, console,
		Module: {
			"luantiProxyUrl": proxyUrl,
			"luantiLauncher": {"reportProxyStatus": detail => statuses.push(detail)},
		},
		WebSocket: PageWebSocket,
		document: {activeElement: null, getElementById: () => null, readyState: "complete"},
		location: {href: pageOrigin + "/", origin: pageOrigin, protocol: "http:", search: ""},
		localStorage: {getItem: () => null, removeItem: () => {}, setItem: () => {}},
		performance: {now: () => 0},
		setInterval: () => 1,
		window: {dispatchEvent: () => {}},
		_malloc: () => 1024,
		_free: () => {},
	};
	vm.runInNewContext(source, context, {filename: "network.js"});
	const api = context.Module["luantiNetwork"];
	return {
		api, statuses, constructed, heap,
		send(handle = 1, address = "127.0.0.1", port = 30000) {
			api["_createSocket"](handle, 20000 + handle);
			heap.set([1, 2, 3], 16);
			return api["_send"](handle, 16, 3, address, port);
		},
		async failure(timeout = 3000) {
			const deadline = Date.now() + timeout;
			while (Date.now() < deadline) {
				const found = statuses.find(status => status.state === "error" || status.state === "closed");
				if (found)
					return found;
				await new Promise(resolve => setTimeout(resolve, 10));
			}
			throw new Error("no failure was reported; saw " + JSON.stringify(statuses.map(s => s.state)));
		},
	};
}

test("a refused origin reaches the launcher as a specific message", async t => {
	const {server, url} = await startProxy({
		allowedOrigins: parseAllowedOrigins("https://play.example.org")});
	t.after(() => server.close());
	const page = loadPage({proxyUrl: url, pageOrigin: "http://evil.test"});
	assert.equal(page.send(), true);
	const status = await page.failure();
	assert.equal(status.state, "error");
	assert.equal(status.reason, "origin");
	assert.equal(status.closeCode, 1008);
	assert.match(status.error, /does not allow pages from http:\/\/evil\.test/);
	assert.ok(status.error.includes(new URL(url).host), "names the proxy");
	assert.ok(!/WebSocket connection failed/.test(status.error));
	assert.equal(page.api["getState"]().reason, "origin");
	assert.equal(server.proxy.sessions.size, 0);
});

test("an allowed origin completes the handshake", async t => {
	const {server, url} = await startProxy({
		allowedOrigins: parseAllowedOrigins("http://play.example.test"),
		allowedTargets: new Set(["127.0.0.1:30000"])});
	t.after(() => server.close());
	const page = loadPage({proxyUrl: url, pageOrigin: "http://play.example.test"});
	page.send();
	const deadline = Date.now() + 3000;
	while (page.api["getState"]().state !== "ready" && Date.now() < deadline)
		await new Promise(resolve => setTimeout(resolve, 10));
	assert.equal(page.api["getState"]().state, "ready");
	assert.equal(page.api["getState"]().reason, null);
	page.api["_destroySocket"](1);
});

test("a denied target reaches the launcher as a specific message", async t => {
	const {server, url} = await startProxy({allowedTargets: new Set(["127.0.0.1:30001"])});
	t.after(() => server.close());
	const page = loadPage({proxyUrl: url, pageOrigin: "http://play.example.test"});
	page.send(1, "127.0.0.1", 30000);
	const status = await page.failure();
	assert.equal(status.state, "error");
	assert.equal(status.reason, "target_denied");
	assert.equal(status.closeCode, 1008);
	assert.match(status.error, /will not forward to that server \(UDP target is not allowed\)/);
});

test("the per-address connection cap (formerly HTTP 429) is readable", async t => {
	const {server, url} = await startProxy({maxConnectionsPerIp: 1});
	t.after(() => server.close());
	const holder = new NodeWebSocket(url);
	await new Promise(resolve => holder.once("open", resolve));
	t.after(() => holder.close());
	const page = loadPage({proxyUrl: url, pageOrigin: "http://play.example.test"});
	page.send();
	const status = await page.failure();
	assert.equal(status.state, "error");
	assert.equal(status.reason, "per_ip_limit");
	assert.equal(status.closeCode, 1013);
	assert.match(status.error, /most connections it allows from your network/);
});

test("a full proxy says so", async t => {
	const {server, url} = await startProxy({maxConnections: 1, maxConnectionsPerIp: 4});
	t.after(() => server.close());
	const holder = new NodeWebSocket(url);
	await new Promise(resolve => holder.once("open", resolve));
	t.after(() => holder.close());
	const page = loadPage({proxyUrl: url, pageOrigin: "http://play.example.test"});
	page.send();
	const status = await page.failure();
	assert.equal(status.reason, "global_limit");
	assert.match(status.error, /is full right now/);
});

test("a dead proxy is reported as unreachable, not as a refusal", async () => {
	const port = await unusedPort();
	const page = loadPage({proxyUrl: `ws://127.0.0.1:${port}/`, pageOrigin: "http://play.example.test"});
	page.send();
	const status = await page.failure();
	assert.equal(status.state, "error");
	assert.equal(status.reason, null, "nothing was said, so there is no tag");
	assert.equal(status.closeCode, 1006);
	assert.match(status.error, new RegExp(`^Could not connect to the proxy at 127\\.0\\.0\\.1:${port}`));
});

test("a refused link is not redialled for every datagram", async t => {
	const {server, url} = await startProxy({
		allowedOrigins: parseAllowedOrigins("https://play.example.org")});
	t.after(() => server.close());
	const page = loadPage({proxyUrl: url, pageOrigin: "http://evil.test"});
	page.send();
	await page.failure();
	assert.equal(page.constructed.length, 1);
	// The engine resends its handshake several times a second.
	for (let i = 0; i < 20; i++)
		assert.equal(page.api["_send"](1, 16, 3, "127.0.0.1", 30000), false);
	assert.equal(page.constructed.length, 1, "no new connection while backing off");
	assert.ok(page.api["getState"]().droppedPackets >= 20);

	// Choosing another proxy clears the backoff.
	const good = await startProxy({allowedOrigins: parseAllowedOrigins("http://evil.test")});
	t.after(() => good.server.close());
	page.api["setProxyUrl"](good.url);
	assert.equal(page.api["_send"](1, 16, 3, "127.0.0.1", 30000), true);
	assert.equal(page.constructed.length, 2);
	page.api["_destroySocket"](1);
});

test("an ordinary idle close may reconnect at once", async t => {
	const {server, url} = await startProxy({
		idleTimeoutMs: 100, handshakeTimeoutMs: 5000, sweepIntervalMs: 20,
		allowedTargets: new Set(["127.0.0.1:30000"])});
	t.after(() => server.close());
	const page = loadPage({proxyUrl: url, pageOrigin: "http://play.example.test"});
	page.send();
	const status = await page.failure();
	assert.equal(status.state, "closed");
	assert.equal(status.reason, "idle");
	assert.match(status.error, /no traffic/);
	assert.equal(page.api["_send"](1, 16, 3, "127.0.0.1", 30000), true,
		"idling out is not a failure, so there is no backoff");
	page.api["_destroySocket"](1);
});
