// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 The Luanti Contributors

// check.mjs, the outside-in deployment check, against proxies configured well
// and badly. It must pass a proper allowlist deployment and say which setting
// is wrong for an open one.

import assert from "node:assert/strict";
import net from "node:net";
import test from "node:test";
import {parseAllowedOrigins} from "../policy.mjs";
import {createProxyServer} from "../server.mjs";
import {runChecks} from "../check.mjs";

const quiet = () => {};
const ORIGIN = "https://play.example.org";

async function startProxy(options = {}) {
	const server = createProxyServer({
		host: "127.0.0.1", port: 0, allowPublic: false, allowedTargets: new Set(["127.0.0.1:30000"]),
		allowedOrigins: parseAllowedOrigins(ORIGIN), metricsToken: "secret", log: quiet, ...options,
	});
	if (!server.address())
		await new Promise(resolve => server.once("listening", resolve));
	return {server, url: `ws://127.0.0.1:${server.address().port}/`};
}

const byName = checks => Object.fromEntries(checks.map(check => [check.name, check]));

test("a proxy configured as an allowlist passes every check", async t => {
	const {server, url} = await startProxy();
	t.after(() => server.close());
	const checks = byName(await runChecks({url, origin: ORIGIN, timeoutMs: 3000}));
	for (const name of ["tls", "handshake", "rtt", "origin", "target", "metrics"])
		assert.equal(checks[name]?.ok, true, `${name}: ${JSON.stringify(checks[name])}`);
	assert.match(checks.rtt.detail, /5\/5 answered/);
	assert.match(checks.origin.detail, /^https:\/\/luanti-acceptance\.invalid refused: origin:/);
	assert.match(checks.target.detail, /^192\.0\.2\.1:30000 refused: target_denied:/);
	// Nothing the checker did reached a UDP target: the refusal came first.
	assert.match(server.proxy.metrics.render(), /luanti_proxy_datagrams_forwarded_total 0/);
});

test("an origin the proxy does not allow fails at the handshake, naming the setting", async t => {
	const {server, url} = await startProxy();
	t.after(() => server.close());
	const checks = byName(await runChecks({url, origin: "https://other.example.org", timeoutMs: 3000}));
	assert.equal(checks.tls.ok, true);
	assert.equal(checks.handshake.ok, false);
	assert.match(checks.handshake.detail, /1008 "origin: .*allowed origins/);
});

test("a proxy that allows every origin fails the origin check", async t => {
	const {server, url} = await startProxy({allowedOrigins: parseAllowedOrigins("*")});
	t.after(() => server.close());
	const checks = byName(await runChecks({url, origin: ORIGIN, timeoutMs: 3000}));
	assert.equal(checks.origin.ok, false);
	assert.match(checks.origin.detail, /ACCEPTED: LUANTI_PROXY_ALLOWED_ORIGINS may be too wide/);
});

test("a proxy that forwards to the 'denied' target fails the target check", async t => {
	const {server, url} = await startProxy();
	t.after(() => server.close());
	// 127.0.0.1:30000 is on this proxy's allowlist, so calling it forbidden must fail.
	const checks = byName(await runChecks({
		url, origin: ORIGIN, deniedTarget: "127.0.0.1:30000", timeoutMs: 3000}));
	assert.equal(checks.target.ok, false);
	assert.match(checks.target.detail, /NOT refused/);
});

test("a /metrics that anyone can read fails the metrics check", async t => {
	// No token: a direct request from loopback is served, as it would be
	// from anywhere if a reverse proxy forwarded /metrics.
	const {server, url} = await startProxy({metricsToken: ""});
	t.after(() => server.close());
	const checks = byName(await runChecks({url, origin: ORIGIN, timeoutMs: 3000}));
	assert.equal(checks.metrics.ok, false);
	assert.match(checks.metrics.detail, /\/metrics is public/);
});

test("an unreachable proxy fails the tls check and stops", async () => {
	const probe = net.createServer();
	await new Promise(resolve => probe.listen(0, "127.0.0.1", () => resolve(undefined)));
	const {port} = /** @type {net.AddressInfo} */ (probe.address());
	await new Promise(resolve => probe.close(() => resolve(undefined)));
	const checks = byName(await runChecks({
		url: `ws://127.0.0.1:${port}/`, origin: ORIGIN, timeoutMs: 1500}));
	assert.equal(checks.tls.ok, false);
	assert.equal(checks.handshake, undefined);
	assert.equal(checks.target, undefined);
});

test("only ws:// and wss:// URLs are accepted", async () => {
	await assert.rejects(runChecks({url: "https://proxy.example.org/", origin: ORIGIN}),
		/must be wss:\/\//);
});
