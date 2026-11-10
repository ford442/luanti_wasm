// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 The Luanti Contributors

import assert from "node:assert/strict";
import dgram from "node:dgram";
import http from "node:http";
import test from "node:test";
import {WebSocket} from "ws";
import {ConnectionTracker, RateLimiter} from "../limits.mjs";
import {Metrics} from "../metrics.mjs";
import {
	ServerRegistry, TargetPolicy, originAllowed, parseAllowedOrigins, parsePortRanges,
} from "../policy.mjs";
import {encodeFrame} from "../protocol.mjs";
import {createProxyServer} from "../server.mjs";

const quiet = () => {};

function listening(server) {
	if (server.address())
		return Promise.resolve();
	return new Promise((resolve, reject) => {
		server.once("listening", resolve);
		server.once("error", reject);
	});
}

async function start(options = {}) {
	const logs = [];
	const server = createProxyServer({
		host: "127.0.0.1", port: 0, allowPublic: false, allowedTargets: new Set(),
		log: (level, event, fields) => logs.push({level, event, ...fields}),
		...options,
	});
	await listening(server);
	return {server, logs, port: server.address().port, url: `ws://127.0.0.1:${server.address().port}`};
}

function connect(url, options = {}) {
	return new Promise(resolve => {
		const websocket = new WebSocket(url, options);
		const result = {websocket, closed: null, status: null};
		websocket.once("open", () => resolve(result));
		websocket.once("unexpected-response", (request, response) => {
			result.status = response.statusCode;
			response.resume();
			resolve(result);
		});
		websocket.once("error", () => resolve(result));
		websocket.once("close", (code, reason) => {
			result.closed = {code, reason: reason.toString()};
		});
	});
}

const closedWithin = async (result, ms = 1500) => {
	const deadline = Date.now() + ms;
	while (!result.closed && Date.now() < deadline)
		await new Promise(resolve => setTimeout(resolve, 10));
	return result.closed;
};

function nextText(websocket) {
	return new Promise(resolve => websocket.once("message", data => resolve(data.toString())));
}

test("origin allowlist: exact, wildcard subdomain, and the explicit any", () => {
	const allowed = parseAllowedOrigins("https://play.example.org, https://*.pages.dev:8443");
	assert.equal(originAllowed(allowed, "https://play.example.org"), true);
	assert.equal(originAllowed(allowed, "https://PLAY.example.org"), true);
	assert.equal(originAllowed(allowed, "https://evil.example.org"), false);
	assert.equal(originAllowed(allowed, "http://play.example.org"), false);
	assert.equal(originAllowed(allowed, "https://a.b.pages.dev:8443"), true);
	assert.equal(originAllowed(allowed, "https://pages.dev:8443"), false);
	assert.equal(originAllowed(allowed, "https://xpages.dev:8443"), false);
	assert.equal(originAllowed(allowed, undefined), false, "no Origin is not a browser");
	assert.equal(originAllowed(parseAllowedOrigins("*"), undefined), true);
	assert.equal(parseAllowedOrigins(""), null);
	assert.throws(() => parseAllowedOrigins("play.example.org"));
});

test("a public listen address refuses to start without an origin policy", () => {
	assert.throws(() => createProxyServer({host: "0.0.0.0", port: 0, allowedOrigins: null}),
		/ALLOWED_ORIGINS/);
});

test("the WebSocket upgrade is refused for a foreign or missing Origin", async t => {
	const {server, url, logs} = await start({allowedOrigins: parseAllowedOrigins("https://play.example.org")});
	t.after(() => server.close());
	const good = await connect(url, {origin: "https://play.example.org"});
	assert.equal(good.status, null);
	assert.equal(good.websocket.readyState, WebSocket.OPEN);
	const evil = await connect(url, {origin: "https://evil.example"});
	assert.equal(evil.status, 403);
	const none = await connect(url);
	assert.equal(none.status, 403);
	good.websocket.close();
	assert.equal(logs.filter(entry => entry.event === "connection_rejected" && entry.reason === "origin").length, 2);
});

test("per-address and global connection caps", async t => {
	const {server, url} = await start({maxConnectionsPerIp: 2, maxConnections: 10});
	t.after(() => server.close());
	const a = await connect(url);
	const b = await connect(url);
	const c = await connect(url);
	assert.equal(c.status, 429, "third connection from one address is refused");
	a.websocket.close();
	await closedWithin(a);
	const d = await connect(url);
	assert.equal(d.status, null, "a slot is free again after a close");
	assert.equal(server.proxy.tracker.total, 2);
	b.websocket.close();
	d.websocket.close();

	const small = await start({maxConnectionsPerIp: 5, maxConnections: 1});
	t.after(() => small.server.close());
	const first = await connect(small.url);
	const second = await connect(small.url);
	assert.equal(second.status, 503, "the global cap holds across addresses");
	first.websocket.close();
});

test("X-Forwarded-For is only trusted when asked for", async t => {
	const {server, url} = await start({maxConnectionsPerIp: 1});
	t.after(() => server.close());
	const a = await connect(url, {headers: {"X-Forwarded-For": "203.0.113.5"}});
	const b = await connect(url, {headers: {"X-Forwarded-For": "203.0.113.6"}});
	assert.equal(b.status, 429, "spoofed header does not buy a new address");
	a.websocket.close();

	const trusted = await start({maxConnectionsPerIp: 1, trustProxy: true});
	t.after(() => trusted.server.close());
	const c = await connect(trusted.url, {headers: {"X-Forwarded-For": "198.51.100.1"}});
	const d = await connect(trusted.url, {headers: {"X-Forwarded-For": "198.51.100.2"}});
	const e = await connect(trusted.url, {headers: {"X-Forwarded-For": "198.51.100.1"}});
	assert.equal(d.status, null);
	assert.equal(e.status, 429);
	c.websocket.close();
	d.websocket.close();
});

test("the rate limit is shared by every connection from one address", async t => {
	const echo = dgram.createSocket("udp4");
	await new Promise(resolve => echo.bind(0, "127.0.0.1", () => resolve(undefined)));
	const targetPort = echo.address().port;
	const {server, url} = await start({
		allowedTargets: new Set([`127.0.0.1:${targetPort}`]),
		maxPacketsPerSecond: 5, maxBytesPerSecond: 1000000,
	});
	t.after(() => {
		server.close();
		echo.close();
	});
	const a = await connect(url);
	const b = await connect(url);
	for (const connection of [a, b]) {
		const reply = nextText(connection.websocket);
		connection.websocket.send("PROXY IPV4 UDP 1");
		assert.equal(await reply, "PROXY OK 1");
	}
	for (let i = 0; i < 3; i++)
		a.websocket.send(encodeFrame("127.0.0.1", targetPort, Buffer.from("x")));
	for (let i = 0; i < 3; i++)
		b.websocket.send(encodeFrame("127.0.0.1", targetPort, Buffer.from("x")));
	// Five tokens in total: six datagrams cannot all pass, whichever socket they use.
	const closes = await Promise.all([closedWithin(a, 800), closedWithin(b, 800)]);
	assert.ok(closes.some(close => close && close.code === 1008 && /rate limit/.test(close.reason)),
		"one of the two connections is cut off");
	assert.ok(server.proxy.metrics.render().includes('luanti_proxy_rate_limited_total 1'));
});

test("token bucket refills over time and refuses without spending", () => {
	let now = 0;
	const limiter = new RateLimiter({packetsPerSecond: 2, bytesPerSecond: 100, now: () => now});
	assert.equal(limiter.consume("a", 10), true);
	assert.equal(limiter.consume("a", 10), true);
	assert.equal(limiter.consume("a", 10), false);
	assert.equal(limiter.consume("b", 10), true, "other addresses have their own bucket");
	now = 500;
	assert.equal(limiter.consume("a", 10), true, "half a second refills one packet");
	assert.equal(limiter.consume("a", 10), false);
	now = 600;
	assert.equal(limiter.consume("a", 1000), false, "too many bytes is refused");
	const tracker = new ConnectionTracker({maxConnections: 2, maxConnectionsPerIp: 1});
	assert.equal(tracker.acquire("a"), null);
	assert.equal(tracker.acquire("a"), "per_ip_limit");
	assert.equal(tracker.acquire("b"), null);
	assert.equal(tracker.acquire("c"), "global_limit");
	tracker.release("a");
	assert.equal(tracker.acquire("c"), null);
});

test("public targets are limited to the port allowlist", async t => {
	assert.deepEqual(parsePortRanges("30000-30010, 31000"), [[30000, 30010], [31000, 31000]]);
	assert.throws(() => parsePortRanges("0-10"));
	assert.throws(() => parsePortRanges("40000-30000"));
	const policy = new TargetPolicy({allowedTargets: new Set(["127.0.0.1:40000"]),
		allowPublic: true, allowedPorts: parsePortRanges("30000-30010")});
	assert.equal(policy.check("8.8.8.8", 30005), null);
	assert.equal(policy.check("8.8.8.8", 53), "UDP port is not allowed");
	assert.equal(policy.check("8.8.8.8", 30011), "UDP port is not allowed");
	assert.equal(policy.check("127.0.0.1", 40000), null, "exact entries bypass the range");
	assert.equal(policy.check("127.0.0.1", 30005), "UDP target is not allowed");
	assert.equal(policy.check("10.0.0.1", 30005), "UDP target is not allowed");

	const {server, url, logs} = await start({allowPublic: true, allowedPorts: parsePortRanges("30000-30010")});
	t.after(() => server.close());
	const ok = await connect(url);
	const reply = nextText(ok.websocket);
	ok.websocket.send("PROXY IPV4 UDP 8.8.8.8 30005");
	assert.equal(await reply, "PROXY OK");
	ok.websocket.close();
	const denied = await connect(url);
	denied.websocket.send("PROXY IPV4 UDP 8.8.8.8 53");
	const close = await closedWithin(denied);
	assert.equal(close.code, 1008);
	assert.match(close.reason, /port is not allowed/);
	assert.ok(logs.some(entry => entry.event === "session_closed" && entry.reason === "target_denied"));
});

test("the server registry gates public targets and keeps its last good list", async () => {
	let payload = {list: [
		{address: "8.8.4.4", port: 31234},
		{address: "play.example.org", port: 30000},
		{address: "10.0.0.5", port: 30000},
		{address: "bad", port: 70000},
	]};
	let fail = false;
	const registry = new ServerRegistry({
		url: "https://servers.example/list.json", log: quiet,
		fetchImpl: /** @type {any} */ (async () =>
			fail ? {ok: false, status: 500} : {ok: true, json: async () => payload}),
		lookup: /** @type {any} */ (async host => {
			if (host === "play.example.org")
				return {address: "93.184.216.34"};
			throw new Error("nxdomain");
		}),
	});
	const policy = new TargetPolicy({allowedTargets: new Set(), allowPublic: true,
		allowedPorts: parsePortRanges("30000"), registry});
	assert.equal(policy.check("8.8.4.4", 31234), "server list is not loaded yet", "fails closed");
	await registry.refresh();
	assert.equal(policy.check("8.8.4.4", 31234), null, "a listed server may use any port");
	assert.equal(policy.check("8.8.4.4", 30000), "UDP target is not a listed server");
	assert.equal(policy.check("93.184.216.34", 30000), null, "hostnames are resolved");
	assert.equal(registry.has("10.0.0.5", 30000), false, "private entries are dropped");
	fail = true;
	await assert.rejects(registry.refresh());
	assert.equal(policy.check("8.8.4.4", 31234), null, "the last good list stays in force");
	fail = false;
	payload = {list: []};
	await assert.rejects(registry.refresh(), /no usable entries/);
	assert.equal(registry.has("8.8.4.4", 31234), true, "an empty list does not wipe the registry");
});

test("per-session state is bounded", async t => {
	const echo = dgram.createSocket("udp4");
	await new Promise(resolve => echo.bind(0, "127.0.0.1", () => resolve(undefined)));
	const base = echo.address().port;
	const targets = [0, 1, 2, 3, 4, 5].map(i => `127.0.0.1:${base + i}`);
	const {server, url} = await start({
		allowedTargets: new Set(targets), maxTargetsPerSession: 3, maxMappingsPerSession: 2,
	});
	t.after(() => {
		server.close();
		echo.close();
	});
	const client = await connect(url);
	let reply = nextText(client.websocket);
	client.websocket.send("PROXY IPV4 UDP 1");
	await reply;
	for (let i = 0; i < 6; i++)
		client.websocket.send(encodeFrame("127.0.0.1", base + i, Buffer.from("x")));
	await new Promise(resolve => setTimeout(resolve, 200));
	const [session] = server.proxy.sessions;
	assert.equal(session.permittedResponses.size, 3);
	assert.deepEqual([...session.permittedResponses.keys()], targets.slice(3));

	client.websocket.send("RESOLVE 172.29.0.1 localhost");
	client.websocket.send("RESOLVE 172.29.0.2 localhost");
	client.websocket.send("RESOLVE 172.29.0.3 localhost");
	const close = await closedWithin(client);
	assert.match(close.reason, /too many RESOLVE/);
});

test("idle and half-open sessions are reaped", async t => {
	const {server, url} = await start({idleTimeoutMs: 150, handshakeTimeoutMs: 100, sweepIntervalMs: 25});
	t.after(() => server.close());
	const silent = await connect(url); // never sends the handshake
	const closeSilent = await closedWithin(silent);
	assert.equal(closeSilent.code, 1008);
	assert.match(closeSilent.reason, /handshake timeout/);

	const idle = await connect(url);
	const reply = nextText(idle.websocket);
	idle.websocket.send("PROXY IPV4 UDP 1");
	await reply;
	const closeIdle = await closedWithin(idle);
	assert.equal(closeIdle.code, 1001);
	assert.match(closeIdle.reason, /idle timeout/);
	assert.equal(server.proxy.tracker.total, 0, "reaped connections free their slot");
});

function get(port, path, headers = {}) {
	return new Promise((resolve, reject) => {
		http.get({host: "127.0.0.1", port, path, headers}, response => {
			let body = "";
			response.on("data", chunk => (body += chunk));
			response.on("end", () => resolve({status: response.statusCode, body}));
		}).on("error", reject);
	});
}

test("/healthz and Prometheus counters", async t => {
	const {server, port, url} = await start();
	t.after(() => server.close());
	const health = await get(port, "/healthz");
	assert.equal(health.status, 200);
	assert.deepEqual(JSON.parse(health.body), {status: "ok", connections: 0});
	const connection = await connect(url);
	const metrics = await get(port, "/metrics");
	assert.equal(metrics.status, 200, "a direct loopback scrape needs no token");
	assert.match(metrics.body, /# TYPE luanti_proxy_connections_total counter/);
	assert.match(metrics.body, /^luanti_proxy_connections_total 1$/m);
	assert.match(metrics.body, /^luanti_proxy_connections_active 1$/m);
	assert.match(metrics.body, /^luanti_proxy_datagrams_forwarded_total 0$/m);
	assert.equal((await get(port, "/metrics", {"X-Forwarded-For": "203.0.113.9"})).status, 404,
		"not through a reverse proxy without a token");
	assert.equal((await get(port, "/other")).status, 404);
	connection.websocket.close();
	await closedWithin(connection);
	assert.match((await get(port, "/metrics")).body,
		/^luanti_proxy_sessions_closed_total\{reason="client_closed"\} 1$/m);
});

test("/metrics honours a bearer token", async t => {
	const {server, port} = await start({metricsToken: "s3cret"});
	t.after(() => server.close());
	assert.equal((await get(port, "/metrics")).status, 401);
	assert.equal((await get(port, "/metrics", {Authorization: "Bearer wrong"})).status, 401);
	const ok = await get(port, "/metrics", {Authorization: "Bearer s3cret"});
	assert.equal(ok.status, 200);
});

test("metrics render labels and escape them", () => {
	const metrics = new Metrics();
	metrics.inc("luanti_proxy_connections_rejected_total", {reason: 'a"b'});
	assert.match(metrics.render(), /luanti_proxy_connections_rejected_total\{reason="a\\"b"\} 1/);
});

test("logs are structured and never contain datagram payloads", async t => {
	const echo = dgram.createSocket("udp4");
	await new Promise(resolve => echo.bind(0, "127.0.0.1", () => resolve(undefined)));
	const port = echo.address().port;
	const {server, url, logs} = await start({allowedTargets: new Set([`127.0.0.1:${port}`])});
	t.after(() => {
		server.close();
		echo.close();
	});
	const client = await connect(url);
	const reply = nextText(client.websocket);
	client.websocket.send("PROXY IPV4 UDP 1");
	await reply;
	client.websocket.send(encodeFrame("127.0.0.1", port, Buffer.from("SECRET-CHAT")));
	client.websocket.close();
	await closedWithin(client);
	await new Promise(resolve => setTimeout(resolve, 50));
	assert.ok(logs.some(entry => entry.event === "session_opened"));
	assert.ok(logs.some(entry => entry.event === "session_closed" && entry.reason === "client_closed"));
	assert.ok(!JSON.stringify(logs).includes("SECRET-CHAT"));
});
