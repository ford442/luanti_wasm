// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 The Luanti Contributors

// What client/web/network.js records about the TCP hop (getTimings): the
// join timeline, the first position packet, receive gaps, suspected
// head-of-line stalls and PING round trips. The clock is the test's, so the
// numbers are exact.

import assert from "node:assert/strict";
import test from "node:test";
import {ScriptedWebSocket, TOSERVER_INIT, TOSERVER_PLAYERPOS, loadPage, luantiDatagram}
	from "./page-harness.mjs";

function connected() {
	const page = loadPage({proxyUrl: "ws://proxy.example.test/", scripted: true});
	page.clock.now = 100;
	page.api["markJoin"]();
	page.clock.now = 130;
	assert.equal(page.send(luantiDatagram(TOSERVER_INIT)), true);
	return {page, socket: ScriptedWebSocket.instances[0]};
}

test("the join timeline is relative to the launcher's mark", () => {
	const {page, socket} = connected();
	page.clock.now = 150;
	socket.onopen();
	page.clock.now = 190;
	socket.onmessage({data: "PROXY OK 1"});
	page.clock.now = 230;
	page.deliver(socket);
	// An unreliable PLAYERPOS is the first position packet; a reliable packet
	// that merely contains the same bytes later is not.
	page.clock.now = 500;
	page.send(luantiDatagram(TOSERVER_PLAYERPOS));
	page.clock.now = 900;
	page.send(luantiDatagram(TOSERVER_PLAYERPOS));

	const timings = page.api["getTimings"]();
	assert.equal(timings.joinMarked, true);
	assert.equal(timings.firstSendMs, 30);
	assert.equal(timings.proxyOpenMs, 50);
	assert.equal(timings.proxyReadyMs, 90);
	assert.equal(timings.firstReceiveMs, 130);
	assert.equal(timings.firstPlayerPosMs, 400);
	assert.equal(timings.receivedDatagrams, 1);
});

test("without a mark the first datagram is the join", () => {
	const page = loadPage({proxyUrl: "ws://proxy.example.test/", scripted: true});
	page.clock.now = 5000;
	page.send(luantiDatagram(TOSERVER_INIT));
	page.clock.now = 5040;
	page.ready(ScriptedWebSocket.instances[0]);
	const timings = page.api["getTimings"]();
	assert.equal(timings.joinMarked, false);
	assert.equal(timings.firstSendMs, 0);
	assert.equal(timings.proxyReadyMs, 40);
});

test("only an unreliable PLAYERPOS counts as a position packet", () => {
	const {page} = connected();
	page.clock.now = 200;
	page.send(luantiDatagram(TOSERVER_PLAYERPOS, {type: 3}));          // reliable wrapper
	page.send(luantiDatagram(TOSERVER_INIT));                          // another command
	page.send([0x4f, 0x45, 0x74, 0x04, 0, 2, 0, 1, 0, 0x23, 0, 0]);   // not Luanti's protocol id
	page.send([0x4f, 0x45, 0x74, 0x03, 0, 2, 0, 1, 0]);                // truncated
	assert.equal(page.api["getTimings"]().firstPlayerPosMs, null);
	page.clock.now = 260;
	page.send(luantiDatagram(TOSERVER_PLAYERPOS));
	assert.equal(page.api["getTimings"]().firstPlayerPosMs, 160);
});

test("a pause that ends in a pile-up is a stall; a quiet server is not", () => {
	const {page, socket} = connected();
	page.ready(socket);
	const frameAt = at => {
		page.clock.now = at;
		page.deliver(socket);
	};
	// A steady 100 ms stream, then a 400 ms hole filled by a burst: stall.
	[1000, 1100, 1200, 1300].forEach(frameAt);
	[1700, 1703, 1706].forEach(frameAt);
	let timings = page.api["getTimings"]();
	assert.equal(timings.stalls, 1);
	assert.equal(timings.longestStallMs, 400);
	assert.equal(timings.gapsOver250Ms, 1);
	assert.equal(timings.longestGapMs, 400);

	// An idle server: 600 ms of nothing, then one datagram, then the normal
	// rhythm. The pause is counted as a gap, not as a stall.
	[2306, 2406, 2506].forEach(frameAt);
	timings = page.api["getTimings"]();
	assert.equal(timings.stalls, 1, "a lone datagram after silence is not a pile-up");
	assert.equal(timings.gapsOver250Ms, 2);
	assert.equal(timings.longestGapMs, 600);
	assert.equal(timings.gapsOver1000Ms, 0);

	// Two datagrams after a pause is still below the pile-up threshold, and a
	// burst that starts late (after the window) does not count either.
	[2900, 2905].forEach(frameAt);
	[3300, 3400, 3401, 3402].forEach(frameAt);
	timings = page.api["getTimings"]();
	assert.equal(timings.stalls, 1);
	assert.ok(timings.gapsOver100Ms >= 6);

	// A second real stall, and a gap of a second or more.
	frameAt(5000);
	[5001, 5002].forEach(frameAt);
	timings = page.api["getTimings"]();
	assert.equal(timings.stalls, 2);
	assert.equal(timings.gapsOver1000Ms, 1);
	assert.equal(timings.longestStallMs, 1598);
});

test("PING round trips are summarised", () => {
	const {page, socket} = connected();
	page.ready(socket);
	// Round trips of 40, 80 and 60 ms.
	for (const [now, sentAt] of [[1000, 960], [2000, 1920], [3000, 2940]]) {
		page.clock.now = now;
		socket.onmessage({data: `PONG 1 ${sentAt}`});
	}
	const rtt = page.api["getTimings"]().rtt;
	assert.deepEqual({...rtt}, {samples: 3, minMs: 40, maxMs: 80, meanMs: 60});
});

test("choosing a proxy again starts a fresh measurement", () => {
	const {page, socket} = connected();
	page.ready(socket);
	page.deliver(socket);
	assert.equal(page.api["getTimings"]().receivedDatagrams, 1);
	page.api["setProxyUrl"]("ws://other.example.test/");
	const timings = page.api["getTimings"]();
	assert.equal(timings.receivedDatagrams, 0);
	assert.equal(timings.firstSendMs, null);
	assert.equal(timings.rtt.samples, 0);
});

test("a proxy that refuses the target is redialled with a growing delay", () => {
	const page = loadPage({proxyUrl: "ws://proxy.example.test/", scripted: true});
	const datagram = luantiDatagram(TOSERVER_INIT);
	const refuse = socket => socket.onclose({
		code: 1008, reason: "target_denied: UDP target is not allowed"});

	// Every connection completes the handshake and is closed on its first
	// datagram. The delay between attempts must still double (1 s, 2 s, 4 s):
	// a successful handshake says nothing about the target.
	let attempts = 0;
	const attempt = at => {
		page.clock.now = at;
		const before = ScriptedWebSocket.instances.length;
		const queued = page.send(datagram);
		if (ScriptedWebSocket.instances.length === before)
			return false;
		assert.equal(queued, true);
		attempts++;
		const socket = ScriptedWebSocket.instances.at(-1);
		page.ready(socket);
		page.clock.now = at + 10;
		refuse(socket);
		return true;
	};
	assert.equal(attempt(0), true);
	assert.equal(attempt(500), false, "inside the first 1 s delay");
	assert.equal(attempt(1010), true);
	assert.equal(attempt(2500), false, "inside the doubled 2 s delay");
	assert.equal(attempt(3020), true);
	assert.equal(attempt(6000), false, "inside the 4 s delay");
	assert.equal(attempt(7030), true);
	assert.equal(attempts, 4);
	assert.equal(page.api["getState"]().reason, "target_denied");
});

test("the retry delay starts over after a link that stayed up", () => {
	const page = loadPage({proxyUrl: "ws://proxy.example.test/", scripted: true});
	const datagram = luantiDatagram(TOSERVER_INIT);
	// Two quick failures push the delay to 2 s.
	for (const at of [0, 1010]) {
		page.clock.now = at;
		page.send(datagram);
		const socket = ScriptedWebSocket.instances.at(-1);
		page.ready(socket);
		socket.onclose({code: 1008, reason: "target_denied: x"});
	}
	// A connection that survives past the stable threshold, then drops.
	page.clock.now = 3010;
	page.send(datagram);
	const stable = ScriptedWebSocket.instances.at(-1);
	page.ready(stable);
	page.clock.now = 14000;
	stable.onclose({code: 1006, reason: ""});
	// Back to the first 1 s delay: allowed again at 15000, not before.
	const count = ScriptedWebSocket.instances.length;
	page.clock.now = 14500;
	page.send(datagram);
	assert.equal(ScriptedWebSocket.instances.length, count, "still inside the 1 s delay");
	page.clock.now = 15001;
	page.send(datagram);
	assert.equal(ScriptedWebSocket.instances.length, count + 1);
});
