// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 The Luanti Contributors

// Loads client/web/network.js the way the page does, with a clock the test
// moves and a WebSocket that is either the real `ws` client (with an Origin
// header, so a refused upgrade looks like it does in a browser) or a scripted
// stand-in. Shared by the probe and telemetry tests.

import {readFile} from "node:fs/promises";
import vm from "node:vm";
import {WebSocket as NodeWebSocket} from "ws";

const source = await readFile(new URL("../../../../client/web/network.js", import.meta.url), "utf8");

// A WebSocket the test drives by hand: nothing is dialled.
export class ScriptedWebSocket {
	static instances = [];

	constructor(url) {
		this.url = url;
		this.sent = [];
		ScriptedWebSocket.instances.push(this);
	}

	send(value) {
		this.sent.push(value);
	}

	close() {
		this.closed = true;
	}
}

/**
 * @param {object} options
 * @param {string} [options.proxyUrl] the configured proxy (Module.luantiProxyUrl)
 * @param {string} [options.pageOrigin] sent as the Origin of every real WebSocket
 * @param {string} [options.protocol] the page's scheme, "http:" or "https:"
 * @param {boolean} [options.scripted] use ScriptedWebSocket instead of dialling
 */
export function loadPage({proxyUrl = "", pageOrigin = "http://page.test", protocol = "http:",
		scripted = false} = {}) {
	ScriptedWebSocket.instances = [];
	const heap = new Uint8Array(4096);
	const clock = {now: 0};
	const statuses = [];
	const received = [];
	const created = new Set();
	class PageWebSocket extends NodeWebSocket {
		constructor(url) {
			super(url, {origin: pageOrigin});
			// A browser reports failures as events; `ws` would throw instead.
			/** @type {any} */ (this).on("error", () => {});
		}
	}
	const context = {
		ArrayBuffer, DataView, Map, URL, URLSearchParams, Uint8Array, console,
		CustomEvent: class {
			constructor(type, options) {
				this.type = type;
				this.detail = options.detail;
			}
		},
		HEAPU8: heap,
		Module: {
			"luantiProxyUrl": proxyUrl,
			"luantiLauncher": {"reportProxyStatus": detail => statuses.push(detail)},
			"_luanti_websocket_proxy_receive": (handle, pointer, length, address, port) =>
				received.push({handle, payload: [...heap.subarray(pointer, pointer + length)],
					address: address >>> 0, port}),
		},
		WebSocket: scripted ? ScriptedWebSocket : PageWebSocket,
		document: {activeElement: null, getElementById: () => null, readyState: "complete"},
		location: {href: pageOrigin + "/", origin: pageOrigin, protocol, search: ""},
		localStorage: {getItem: () => null, removeItem: () => {}, setItem: () => {}},
		performance: {now: () => clock.now},
		// The retry delays are measured with Date.now(); the test moves them too.
		Date: {now: () => clock.now},
		setInterval: () => 1,
		setTimeout, clearTimeout,
		window: {dispatchEvent: () => {}},
		_malloc: () => 1024,
		_free: () => {},
	};
	vm.runInNewContext(source, context, {filename: "network.js"});
	const api = context.Module["luantiNetwork"];
	return {
		api, heap, clock, statuses, received,
		/** Queue one datagram from the engine, as socket.cpp does. */
		send(bytes, {handle = 1, address = "127.0.0.1", port = 30000} = {}) {
			if (!created.has(handle)) {
				created.add(handle);
				api["_createSocket"](handle, 20000 + handle);
			}
			heap.set(bytes, 16);
			return api["_send"](handle, 16, bytes.length, address, port);
		},
		/** The link as a server would find it: handshake done. */
		ready(socket) {
			socket.onopen();
			socket.onmessage({data: "PROXY OK 1"});
		},
		/** One datagram from the proxy. */
		deliver(socket, payload = [1, 2, 3], address = "127.0.0.1", port = 30000) {
			socket.onmessage({data: api["_test"]["encapsulate"](address, port, new Uint8Array(payload))});
		},
	};
}

// A Luanti datagram the way the engine writes it: protocol id, peer id,
// channel, packet type, then (for an ORIGINAL packet) the big-endian command.
export function luantiDatagram(command, {type = 1, padding = 24} = {}) {
	return [0x4f, 0x45, 0x74, 0x03, 0, 2, 0, type, command >> 8, command & 255,
		...new Array(padding).fill(0)];
}

export const TOSERVER_PLAYERPOS = 0x23;
export const TOSERVER_INIT = 0x02;
