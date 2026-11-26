// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 The Luanti Contributors

import assert from "node:assert/strict";
import dgram from "node:dgram";
import test from "node:test";
import {WebSocket} from "ws";
import {decodeFrame, encodeFrame} from "../protocol.mjs";
import {createProxyServer} from "../server.mjs";

function onceListening(server) {
	if (server.address())
		return Promise.resolve();
	return new Promise((resolve, reject) => {
		server.once("listening", resolve);
		server.once("error", reject);
	});
}

function onceOpen(websocket) {
	return new Promise((resolve, reject) => {
		websocket.once("open", resolve);
		websocket.once("error", reject);
	});
}

function nextMessage(websocket) {
	return new Promise((resolve, reject) => {
		const onMessage = (data, isBinary) => {
			cleanup();
			resolve({data, isBinary});
		};
		const onClose = (code, reason) => {
			cleanup();
			reject(new Error(`socket closed before reply (${code}: ${reason})`));
		};
		const cleanup = () => {
			websocket.off("message", onMessage);
			websocket.off("close", onClose);
		};
		websocket.once("message", onMessage);
		websocket.once("close", onClose);
	});
}

test("versioned proxy forwards an encapsulated datagram to UDP and back", async t => {
	const echo = dgram.createSocket("udp4");
	echo.on("message", (message, remote) => echo.send(message, remote.port, remote.address));
	await new Promise((resolve, reject) => {
		echo.once("listening", resolve);
		echo.once("error", reject);
		echo.bind(0, "127.0.0.1");
	});
	const targetPort = echo.address().port;

	const server = createProxyServer({
		host: "127.0.0.1",
		port: 0,
		allowPublic: false,
		allowedTargets: new Set([`127.0.0.1:${targetPort}`]),
		maxPacketsPerSecond: 10,
		maxBytesPerSecond: 4096,
	});
	await onceListening(server);
	const websocket = new WebSocket(`ws://127.0.0.1:${server.address().port}`);
	await onceOpen(websocket);
	t.after(() => {
		websocket.close();
		server.close();
		echo.close();
	});

	let reply = nextMessage(websocket);
	websocket.send("PROXY IPV4 UDP 1");
	let message = await reply;
	assert.equal(message.isBinary, false);
	assert.equal(message.data.toString(), "PROXY OK 1");

	const payload = Buffer.from("luanti-proxy-smoke");
	reply = nextMessage(websocket);
	// Send the mapping and datagram without waiting in between. The server must
	// preserve WebSocket message order across asynchronous DNS resolution.
	websocket.send("RESOLVE 172.29.1.2 localhost");
	websocket.send(encodeFrame("172.29.1.2", targetPort, payload));
	message = await reply;
	assert.equal(message.isBinary, true);
	const frame = decodeFrame(message.data);
	assert.equal(frame.address, "127.0.0.1");
	assert.equal(frame.port, targetPort);
	assert.deepEqual(frame.payload, payload);

	reply = nextMessage(websocket);
	websocket.send("PING 7 12.5");
	message = await reply;
	assert.equal(message.data.toString(), "PONG 7 12.5");
});
