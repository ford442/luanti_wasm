// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 The Luanti Contributors

import assert from "node:assert/strict";
import test from "node:test";
import {decodeFrame, encodeFrame, isHostname, parseHandshake, parseResolve} from "../protocol.mjs";
import {isPublicIPv4, parseAllowedTargets} from "../server.mjs";

test("encapsulation round trips in network byte order", () => {
	const frame = encodeFrame("203.0.113.9", 30000, Buffer.from([1, 2, 3, 4]));
	assert.deepEqual([...frame.subarray(0, 12)],
		[0x77, 0x8b, 0x4c, 0xf3, 203, 0, 113, 9, 0x75, 0x30, 0, 4]);
	const decoded = decodeFrame(frame);
	assert.equal(decoded.address, "203.0.113.9");
	assert.equal(decoded.port, 30000);
	assert.deepEqual([...decoded.payload], [1, 2, 3, 4]);
});

test("handshake retains legacy direct mode and adds versioned multiplexing", () => {
	assert.deepEqual(parseHandshake("PROXY IPV4 UDP 1"),
		{mode: "encapsulated", version: 1});
	assert.deepEqual(parseHandshake("PROXY IPV4 UDP 203.0.113.2 30000"),
		{mode: "legacy", address: "203.0.113.2", port: 30000});
	assert.throws(() => parseHandshake("PROXY IPV6 UDP 1"));
});

test("resolver control messages reject injection", () => {
	assert.deepEqual(parseResolve("RESOLVE 198.18.0.1 play.example.org"),
		{virtualAddress: "198.18.0.1", hostname: "play.example.org"});
	assert.equal(isHostname("play.example.org"), true);
	assert.throws(() => parseResolve("RESOLVE 198.18.0.1 bad host"));
});

test("public target policy rejects local and reserved networks", () => {
	assert.equal(isPublicIPv4("8.8.8.8"), true);
	for (const address of ["127.0.0.1", "10.0.0.1", "172.16.0.1",
			"192.168.1.1", "169.254.1.1", "192.0.2.1", "198.51.100.1",
			"203.0.113.1", "224.0.0.1"])
		assert.equal(isPublicIPv4(address), false, address);
});

test("exact target allowlists validate IPv4 addresses and ports", () => {
	assert.deepEqual([...parseAllowedTargets("127.0.0.1:30000, 8.8.8.8:53")],
		["127.0.0.1:30000", "8.8.8.8:53"]);
	for (const value of ["999.1.1.1:30000", "127.0.0.1:0", "host:30000"])
		assert.throws(() => parseAllowedTargets(value), undefined, value);
});
