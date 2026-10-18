// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 The Luanti Contributors

import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";

const source = await readFile(new URL("../../../../client/web/network.js", import.meta.url), "utf8");

class MockWebSocket {
	static instances = [];

	constructor(url) {
		this.url = url;
		this.sent = [];
		MockWebSocket.instances.push(this);
	}

	send(value) {
		this.sent.push(value);
	}

	close() {
		this.closed = true;
	}
}

test("browser bridge negotiates, queues, frames, receives, and reports state", () => {
	MockWebSocket.instances = [];
	const heap = new Uint8Array(4096);
	const events = [];
	const received = [];
	const storage = new Map();
	const context = {
		ArrayBuffer,
		CustomEvent: class CustomEvent {
			constructor(type, options) {
				this.type = type;
				this.detail = options.detail;
			}
		},
		DataView,
		HEAPU8: heap,
		Map,
		Module: {"luantiProxyUrl": "ws://proxy.example.test/"},
		URL,
		URLSearchParams,
		Uint8Array,
		WebSocket: MockWebSocket,
		console,
		document: {
			activeElement: null,
			getElementById: () => null,
			readyState: "complete",
		},
		location: {
			href: "http://client.example.test/",
			protocol: "http:",
			search: "",
		},
		localStorage: {
			getItem: key => storage.get(key) || null,
			removeItem: key => storage.delete(key),
			setItem: (key, value) => storage.set(key, value),
		},
		performance: {now: () => 50},
		setInterval: () => 1,
		window: {dispatchEvent: event => events.push(event)},
		_malloc: () => 1024,
		_free: () => {},
	};
	context.Module["_luanti_websocket_proxy_receive"] =
		(handle, pointer, length, address, port) => received.push({
			handle,
			payload: [...heap.subarray(pointer, pointer + length)],
			address: address >>> 0,
			port,
		});
	vm.runInNewContext(source, context, {filename: "network.js"});

	const api = context.Module["luantiNetwork"];
	api["_createSocket"](3, 20003);
	api["_registerHostname"]("172.29.1.2", "play.example.test");
	heap.set([9, 8, 7], 20);
	assert.equal(api["_send"](3, 20, 3, "172.29.1.2", 30000), true);
	const websocket = MockWebSocket.instances[0];
	assert.equal(websocket.url, "ws://proxy.example.test/");
	assert.equal(websocket.sent.length, 0);

	websocket.onopen();
	assert.deepEqual(websocket.sent, ["PROXY IPV4 UDP 1"]);
	websocket.onmessage({data: "PROXY OK 1"});
	assert.equal(websocket.sent[1], "RESOLVE 172.29.1.2 play.example.test");
	assert.ok(websocket.sent[2] instanceof ArrayBuffer);
	const outgoing = api["_test"]["decodeFrame"](websocket.sent[2]);
	assert.equal(outgoing.address, "172.29.1.2");
	assert.equal(outgoing.port, 30000);
	assert.deepEqual([...outgoing.payload], [9, 8, 7]);

	const incoming = api["_test"]["encapsulate"]("203.0.113.9", 30000,
		new Uint8Array([4, 5, 6]));
	websocket.onmessage({data: incoming});
	assert.deepEqual(received, [{
		handle: 3,
		payload: [4, 5, 6],
		address: 0xcb007109,
		port: 30000,
	}]);
	assert.equal(api["getState"]().state, "ready");
	assert.equal(api["getState"]().sentPackets, 1);
	assert.equal(api["getState"]().receivedPackets, 1);
	assert.equal(events.at(-1).type, "luanti:network");
});

test("HTTPS pages reject an insecure proxy URL", () => {
	const context = {
		ArrayBuffer, CustomEvent: class {}, DataView, Map, URL, URLSearchParams,
		Uint8Array, WebSocket: MockWebSocket, console,
		Module: {}, localStorage: {getItem: () => null},
		location: {href: "https://client.example.test/", protocol: "https:", search: ""},
		document: {activeElement: null, getElementById: () => null, readyState: "complete"},
		window: {dispatchEvent: () => {}}, setInterval: () => 1,
	};
	vm.runInNewContext(source, context, {filename: "network.js"});
	assert.throws(() => context.Module["luantiNetwork"]["setProxyUrl"]("ws://localhost:8080"),
		/HTTPS pages require/);
});
