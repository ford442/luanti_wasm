// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 The Luanti Contributors

// Module.luantiNetwork.probe against the real proxy: what the launcher learns
// before it starts the engine. Like a browser, the page's WebSocket carries an
// Origin and sees a refusal only as a close code and reason.

import assert from "node:assert/strict";
import net from "node:net";
import test from "node:test";
import {parseAllowedOrigins} from "../policy.mjs";
import {createProxyServer} from "../server.mjs";
import {loadPage} from "./page-harness.mjs";

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
		host: "127.0.0.1", port: 0, allowPublic: false, allowedTargets: new Set(), log: quiet,
		...options,
	});
	await listening(server);
	return {server, url: `ws://127.0.0.1:${server.address().port}/`};
}

async function until(condition, timeout = 3000) {
	const deadline = Date.now() + timeout;
	while (!condition()) {
		assert.ok(Date.now() < deadline, "timed out waiting");
		await new Promise(resolve => setTimeout(resolve, 10));
	}
}

test("a proxy that accepts the page passes the probe and sees no datagram", async t => {
	const {server, url} = await startProxy({
		allowedOrigins: parseAllowedOrigins("http://page.test")});
	t.after(() => server.close());
	const page = loadPage({pageOrigin: "http://page.test"});
	const result = await page.api["probe"](url);
	assert.equal(result.ok, true, JSON.stringify(result));
	assert.equal(result.url, url);
	assert.equal(result.message, "");
	assert.equal(result.reason, null);
	assert.equal(typeof result.handshakeMs, "number");
	assert.equal(typeof result.rttMs, "number");
	// The probe closes cleanly and never sends anything toward a game server.
	await until(() => server.proxy.sessions.size === 0);
	assert.equal(server.proxy.metrics.render().includes("luanti_proxy_datagrams_forwarded_total 0"), true);
	assert.match(server.proxy.metrics.render(), /luanti_proxy_sessions_closed_total\{reason="client_closed"\} 1/);
	// ... and it does not touch the page's own link.
	assert.equal(page.api["getState"]().state, "disabled");
	assert.equal(page.api["getState"]().error, null);
	assert.equal(page.statuses.length, 0);
});

test("a refused origin fails the probe with the proxy's reason", async t => {
	const {server, url} = await startProxy({
		allowedOrigins: parseAllowedOrigins("https://play.example.org")});
	t.after(() => server.close());
	const result = await loadPage({pageOrigin: "http://evil.test"}).api["probe"](url);
	assert.equal(result.ok, false);
	assert.equal(result.reason, "origin");
	assert.equal(result.closeCode, 1008);
	assert.match(result.message, /does not allow pages from http:\/\/evil\.test/);
	assert.ok(result.message.includes(new URL(url).host));
});

test("a full proxy fails the probe with its reason", async t => {
	const {server, url} = await startProxy({
		maxConnections: 1, allowedTargets: new Set(["127.0.0.1:30000"])});
	t.after(() => server.close());
	// Hold the only slot with a real, handshaken connection (its target is
	// allowed, so the proxy keeps it open).
	const holder = loadPage({pageOrigin: "http://page.test", proxyUrl: url});
	holder.send([1, 2, 3], {address: "127.0.0.1", port: 30000});
	await until(() => server.proxy.sessions.size === 1);
	const result = await loadPage({pageOrigin: "http://page.test"}).api["probe"](url);
	assert.equal(result.ok, false);
	assert.equal(result.reason, "global_limit");
	assert.match(result.message, /is full right now/);
	holder.api["_destroySocket"](1);
});

test("an unreachable proxy fails the probe as 'could not connect'", async () => {
	const probePort = net.createServer();
	await new Promise(resolve => probePort.listen(0, "127.0.0.1", () => resolve(undefined)));
	const {port} = /** @type {net.AddressInfo} */ (probePort.address());
	await new Promise(resolve => probePort.close(() => resolve(undefined)));
	const result = await loadPage().api["probe"](`ws://127.0.0.1:${port}/`);
	assert.equal(result.ok, false);
	assert.equal(result.reason, null);
	assert.equal(result.closeCode, 1006);
	assert.match(result.message, new RegExp(`^Could not connect to the proxy at 127\\.0\\.0\\.1:${port}\\b`));
});

test("a proxy that never answers fails the probe after the timeout", async t => {
	// Accepts the TCP connection and says nothing: no upgrade, no handshake.
	const sockets = new Set();
	const silent = net.createServer(socket => {
		sockets.add(socket);
		socket.on("error", () => {});
	});
	await new Promise(resolve => silent.listen(0, "127.0.0.1", () => resolve(undefined)));
	t.after(() => {
		sockets.forEach(socket => socket.destroy());
		silent.close();
	});
	const {port} = /** @type {net.AddressInfo} */ (silent.address());
	const started = Date.now();
	const result = await loadPage().api["probe"](`ws://127.0.0.1:${port}/`, 300);
	assert.equal(result.ok, false);
	assert.equal(result.reason, "timeout");
	assert.equal(result.closeCode, null);
	assert.match(result.message, /did not answer within 0 seconds|did not answer within \d+ seconds/);
	assert.ok(Date.now() - started < 3000);
});

test("an HTTPS page cannot probe a plain ws:// proxy, and an empty URL is not a proxy", async () => {
	const secure = await loadPage({protocol: "https:", pageOrigin: "https://play.example.org"})
		.api["probe"]("ws://127.0.0.1:1/");
	assert.equal(secure.ok, false);
	assert.match(secure.message, /HTTPS pages require a wss:\/\/ proxy/);
	const empty = await loadPage().api["probe"]("   ");
	assert.equal(empty.ok, false);
	assert.match(empty.message, /No multiplayer proxy is selected/);
});

test("the probe's handshake time is part of the join timings", async t => {
	const {server, url} = await startProxy();
	t.after(() => server.close());
	const page = loadPage();
	assert.equal(page.api["getTimings"]().probeMs, null);
	await page.api["probe"](url);
	assert.equal(typeof page.api["getTimings"]().probeMs, "number");
});
