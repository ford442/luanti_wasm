// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 The Luanti Contributors

import dgram from "node:dgram";
import dns from "node:dns/promises";
import net from "node:net";
import {pathToFileURL} from "node:url";
import {WebSocket, WebSocketServer} from "ws";
import {decodeFrame, encodeFrame, parseHandshake, parseResolve} from "./protocol.mjs";

const config = {
	host: process.env.LUANTI_PROXY_HOST || "127.0.0.1",
	port: numberEnv("LUANTI_PROXY_PORT", 8080, 0, 65535),
	allowPublic: process.env.LUANTI_PROXY_ALLOW_PUBLIC === "1",
	allowedTargets: parseAllowedTargets(process.env.LUANTI_PROXY_ALLOWED_TARGETS ||
		"127.0.0.1:30000"),
	maxPacketsPerSecond: numberEnv("LUANTI_PROXY_MAX_PACKETS_PER_SECOND", 256, 1, 10000),
	maxBytesPerSecond: numberEnv("LUANTI_PROXY_MAX_BYTES_PER_SECOND", 1048576, 1024, 100000000),
};

export class UDPProxySession {
	constructor(websocket, options = config) {
		this.websocket = websocket;
		this.options = options;
		this.mode = null;
		this.legacyTarget = null;
		this.mappings = new Map();
		this.permittedResponses = new Set();
		this.closed = false;
		this.windowStarted = Date.now();
		this.windowPackets = 0;
		this.windowBytes = 0;
		this.pendingMessages = Promise.resolve();
		this.udp = dgram.createSocket("udp4");
		this.udp.on("message", (message, remote) => this.onUDPMessage(message, remote));
		this.udp.on("error", error => this.close(1011, "UDP socket error: " + error.message));
		this.udp.bind();
	}

	receive(data, isBinary) {
		// WebSocket events are ordered, but DNS resolution is asynchronous. Keep
		// RESOLVE and the following binary datagram in that same order.
		this.pendingMessages = this.pendingMessages.then(() =>
			this.onMessage(data, isBinary));
		return this.pendingMessages;
	}

	async onMessage(data, isBinary) {
		try {
			if (!this.mode) {
				if (isBinary)
					throw new Error("binary data before handshake");
				const handshake = parseHandshake(data.toString());
				this.mode = handshake.mode;
				if (handshake.mode === "legacy")
					this.legacyTarget = await this.authorize(handshake.address, handshake.port);
				this.sendText(handshake.mode === "encapsulated" ? "PROXY OK 1" : "PROXY OK");
				return;
			}

			if (!isBinary) {
				const text = data.toString();
				if (text.startsWith("RESOLVE ")) {
					if (this.mode !== "encapsulated")
						throw new Error("RESOLVE is unavailable in legacy mode");
					const request = parseResolve(text);
					const answer = await dns.lookup(request.hostname, {family: 4});
					this.mappings.set(request.virtualAddress, answer.address);
					return;
				}
				const ping = /^PING (\d+) (\d+(?:\.\d+)?)$/.exec(text);
				if (ping) {
					this.sendText("PONG " + ping[1] + " " + ping[2]);
					return;
				}
				throw new Error("unsupported control message");
			}

			if (this.mode === "legacy") {
				await this.forward(this.legacyTarget.address, this.legacyTarget.port, data);
				return;
			}
			const frame = decodeFrame(data);
			const mapped = this.mappings.get(frame.address) || frame.address;
			const target = await this.authorize(mapped, frame.port);
			await this.forward(target.address, target.port, frame.payload);
		} catch (error) {
			this.close(1008, error.message);
		}
	}

	async authorize(address, port) {
		if (!net.isIPv4(address))
			throw new Error("IPv4 target required");
		const endpoint = address + ":" + port;
		if (this.options.allowedTargets.has(endpoint))
			return {address, port};
		if (!this.options.allowPublic || !isPublicIPv4(address))
			throw new Error("UDP target is not allowed");
		return {address, port};
	}

	async forward(address, port, payload) {
		const bytes = Buffer.from(payload);
		this.consumeRate(bytes.length);
		this.permittedResponses.add(address + ":" + port);
		await new Promise((resolve, reject) => {
			this.udp.send(bytes, port, address, error => error ? reject(error) : resolve());
		});
	}

	onUDPMessage(message, remote) {
		if (!this.permittedResponses.has(remote.address + ":" + remote.port))
			return;
		if (!this.websocket || this.websocket.readyState !== WebSocket.OPEN)
			return;
		if (this.mode === "legacy")
			this.websocket.send(message, {binary: true});
		else
			this.websocket.send(encodeFrame(remote.address, remote.port, message), {binary: true});
	}

	consumeRate(bytes) {
		const now = Date.now();
		if (now - this.windowStarted >= 1000) {
			this.windowStarted = now;
			this.windowPackets = 0;
			this.windowBytes = 0;
		}
		this.windowPackets++;
		this.windowBytes += bytes;
		if (this.windowPackets > this.options.maxPacketsPerSecond ||
				this.windowBytes > this.options.maxBytesPerSecond)
			throw new Error("UDP rate limit exceeded");
	}

	sendText(text) {
		if (this.websocket && this.websocket.readyState === WebSocket.OPEN)
			this.websocket.send(text, {binary: false});
	}

	close(code = 1000, reason = "") {
		if (this.closed)
			return;
		this.closed = true;
		if (this.udp) {
			try {
				this.udp.close();
			} catch (_) {
			}
			this.udp = null;
		}
		if (this.websocket && this.websocket.readyState < WebSocket.CLOSING)
			this.websocket.close(code, String(reason).slice(0, 123));
		this.websocket = null;
	}
}

export function createProxyServer(options = config) {
	const server = new WebSocketServer({host: options.host, port: options.port,
		maxPayload: 65519, perMessageDeflate: false});
	server.on("connection", websocket => {
		const session = new UDPProxySession(websocket, options);
		websocket.on("message", (data, isBinary) => session.receive(data, isBinary));
		websocket.on("error", () => session.close());
		websocket.on("close", () => session.close());
	});
	return server;
}

function numberEnv(name, fallback, minimum, maximum) {
	const value = Number(process.env[name] || fallback);
	if (!Number.isInteger(value) || value < minimum || value > maximum)
		throw new Error(name + " is invalid");
	return value;
}

export function parseAllowedTargets(value) {
	const targets = new Set();
	for (const entry of value.split(",").map(item => item.trim()).filter(Boolean)) {
		const separator = entry.lastIndexOf(":");
		const address = entry.slice(0, separator);
		const port = Number(entry.slice(separator + 1));
		if (separator < 0 || !net.isIPv4(address) || !Number.isInteger(port) ||
				port < 1 || port > 65535)
			throw new Error("LUANTI_PROXY_ALLOWED_TARGETS contains an invalid endpoint");
		targets.add(address + ":" + port);
	}
	return targets;
}

export function isPublicIPv4(address) {
	if (!net.isIPv4(address))
		return false;
	const [a, b, c] = address.split(".").map(Number);
	return !(a === 0 || a === 10 || a === 127 || a >= 224 ||
		(a === 100 && b >= 64 && b <= 127) ||
		(a === 169 && b === 254) ||
		(a === 172 && b >= 16 && b <= 31) ||
		(a === 192 && b === 0) ||
		(a === 192 && b === 168) ||
		(a === 198 && (b === 18 || b === 19 || (b === 51 && c === 100))) ||
		(a === 203 && b === 0 && c === 113));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
	const server = createProxyServer();
	server.on("listening", () => {
		const address = server.address();
		console.log(`Luanti WebSocket UDP proxy listening on ${address.address}:${address.port}`);
		console.log(config.allowPublic ? "Public IPv4 targets enabled" :
			"Public targets disabled; using explicit allowlist only");
	});
}
