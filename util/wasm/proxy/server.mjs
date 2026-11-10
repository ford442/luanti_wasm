// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 The Luanti Contributors

import crypto from "node:crypto";
import dgram from "node:dgram";
import dns from "node:dns/promises";
import http from "node:http";
import net from "node:net";
import {pathToFileURL} from "node:url";
import {WebSocket, WebSocketServer} from "ws";
import {ConnectionTracker, RateLimiter} from "./limits.mjs";
import {Metrics} from "./metrics.mjs";
import {
	ServerRegistry, TargetPolicy, isPublicIPv4, originAllowed, parseAllowedOrigins,
	parseAllowedTargets, parsePortRanges,
} from "./policy.mjs";
import {decodeFrame, encodeFrame, parseHandshake, parseResolve} from "./protocol.mjs";

export {isPublicIPv4, parseAllowedTargets};

class ProxyError extends Error {
	constructor(message, tag) {
		super(message);
		this.tag = tag;
	}
}

export function defaultConfig(env = process.env) {
	const number = (name, fallback, minimum, maximum) => {
		const value = Number(env[name] || fallback);
		if (!Number.isInteger(value) || value < minimum || value > maximum)
			throw new Error(name + " is invalid");
		return value;
	};
	return {
		host: env.LUANTI_PROXY_HOST || "127.0.0.1",
		port: number("LUANTI_PROXY_PORT", 8080, 0, 65535),
		allowPublic: env.LUANTI_PROXY_ALLOW_PUBLIC === "1",
		allowedTargets: parseAllowedTargets(env.LUANTI_PROXY_ALLOWED_TARGETS || "127.0.0.1:30000"),
		allowedPorts: parsePortRanges(env.LUANTI_PROXY_ALLOWED_PORTS || "30000-30010"),
		allowedOrigins: parseAllowedOrigins(env.LUANTI_PROXY_ALLOWED_ORIGINS || ""),
		serverListUrl: env.LUANTI_PROXY_SERVER_LIST_URL || "",
		serverListRefreshMs: number("LUANTI_PROXY_SERVER_LIST_REFRESH_SECONDS", 600, 10, 86400) * 1000,
		maxPacketsPerSecond: number("LUANTI_PROXY_MAX_PACKETS_PER_SECOND", 256, 1, 10000),
		maxBytesPerSecond: number("LUANTI_PROXY_MAX_BYTES_PER_SECOND", 1048576, 1024, 100000000),
		maxConnections: number("LUANTI_PROXY_MAX_CONNECTIONS", 256, 1, 100000),
		maxConnectionsPerIp: number("LUANTI_PROXY_MAX_CONNECTIONS_PER_IP", 8, 1, 10000),
		maxTargetsPerSession: number("LUANTI_PROXY_MAX_TARGETS_PER_SESSION", 64, 1, 4096),
		maxMappingsPerSession: number("LUANTI_PROXY_MAX_MAPPINGS_PER_SESSION", 256, 1, 65536),
		idleTimeoutMs: number("LUANTI_PROXY_IDLE_TIMEOUT_SECONDS", 120, 1, 86400) * 1000,
		handshakeTimeoutMs: number("LUANTI_PROXY_HANDSHAKE_TIMEOUT_SECONDS", 10, 1, 600) * 1000,
		sweepIntervalMs: 5000,
		trustProxy: env.LUANTI_PROXY_TRUST_PROXY === "1",
		metricsToken: env.LUANTI_PROXY_METRICS_TOKEN || "",
	};
}

function isLoopbackHost(host) {
	return host === "localhost" || host === "::1" || /^127\./.test(host);
}

function defaultLog(level, event, fields) {
	console.log(JSON.stringify({ts: new Date().toISOString(), level, event, ...fields}));
}

// The peer address, or with LUANTI_PROXY_TRUST_PROXY=1 (a reverse proxy that
// overwrites X-Forwarded-For, such as the bundled Caddy) its last entry.
export function clientAddress(request, trustProxy) {
	let address = request.socket.remoteAddress || "unknown";
	if (trustProxy) {
		const forwarded = String(request.headers["x-forwarded-for"] || "")
			.split(",").map(part => part.trim()).filter(Boolean);
		if (forwarded.length && net.isIP(forwarded[forwarded.length - 1]))
			address = forwarded[forwarded.length - 1];
	}
	return address.replace(/^::ffff:/, "");
}

export class UDPProxySession {
	constructor(websocket, options, context) {
		this.websocket = websocket;
		this.options = options;
		this.ip = context.ip;
		this.limiter = context.limiter;
		this.policy = context.policy;
		this.metrics = context.metrics;
		this.log = context.log;
		this.onClosed = context.onClosed || (() => {});
		this.mode = null;
		this.legacyTarget = null;
		this.mappings = new Map();
		// Insertion-ordered and capped: the oldest target is forgotten first.
		this.permittedResponses = new Map();
		this.closed = false;
		this.createdAt = Date.now();
		this.lastActivity = this.createdAt;
		this.pendingMessages = Promise.resolve();
		this.udp = dgram.createSocket("udp4");
		this.udp.on("message", (message, remote) => this.onUDPMessage(message, remote));
		this.udp.on("error", error => this.close(1011, "UDP socket error: " + error.message, "udp_error"));
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
		if (this.closed)
			return;
		try {
			if (!this.mode) {
				if (isBinary)
					throw new ProxyError("binary data before handshake", "protocol");
				const handshake = parseHandshake(data.toString());
				this.mode = handshake.mode;
				if (handshake.mode === "legacy")
					this.legacyTarget = this.authorize(handshake.address, handshake.port);
				this.sendText(handshake.mode === "encapsulated" ? "PROXY OK 1" : "PROXY OK");
				return;
			}

			if (!isBinary) {
				const text = data.toString();
				if (text.startsWith("RESOLVE ")) {
					if (this.mode !== "encapsulated")
						throw new ProxyError("RESOLVE is unavailable in legacy mode", "protocol");
					const request = parseResolve(text);
					if (!this.mappings.has(request.virtualAddress) &&
							this.mappings.size >= this.options.maxMappingsPerSession)
						throw new ProxyError("too many RESOLVE mappings", "protocol");
					this.consumeRate(0);
					const answer = await dns.lookup(request.hostname, {family: 4});
					this.mappings.set(request.virtualAddress, answer.address);
					return;
				}
				const ping = /^PING (\d+) (\d+(?:\.\d+)?)$/.exec(text);
				if (ping) {
					this.sendText("PONG " + ping[1] + " " + ping[2]);
					return;
				}
				throw new ProxyError("unsupported control message", "protocol");
			}

			if (this.mode === "legacy") {
				await this.forward(this.legacyTarget.address, this.legacyTarget.port, data);
				return;
			}
			const frame = decodeFrame(data);
			const mapped = this.mappings.get(frame.address) || frame.address;
			const target = this.authorize(mapped, frame.port);
			await this.forward(target.address, target.port, frame.payload);
		} catch (error) {
			this.close(1008, error.message, error.tag || "protocol");
		}
	}

	authorize(address, port) {
		const denied = this.policy.check(address, port);
		if (denied) {
			this.metrics.inc("luanti_proxy_targets_denied_total");
			throw new ProxyError(denied, "target_denied");
		}
		return {address, port};
	}

	async forward(address, port, payload) {
		const bytes = Buffer.from(payload);
		this.consumeRate(bytes.length);
		const key = address + ":" + port;
		this.permittedResponses.delete(key);
		this.permittedResponses.set(key, true);
		if (this.permittedResponses.size > this.options.maxTargetsPerSession)
			this.permittedResponses.delete(this.permittedResponses.keys().next().value);
		this.lastActivity = Date.now();
		await /** @type {Promise<void>} */ (new Promise((resolve, reject) => {
			if (!this.udp)
				return resolve();
			this.udp.send(bytes, port, address, error => error ? reject(error) : resolve());
		}));
		this.metrics.inc("luanti_proxy_datagrams_forwarded_total");
		this.metrics.inc("luanti_proxy_bytes_forwarded_total", null, bytes.length);
	}

	onUDPMessage(message, remote) {
		if (!this.permittedResponses.has(remote.address + ":" + remote.port))
			return;
		if (!this.websocket || this.websocket.readyState !== WebSocket.OPEN)
			return;
		this.lastActivity = Date.now();
		this.metrics.inc("luanti_proxy_datagrams_received_total");
		this.metrics.inc("luanti_proxy_bytes_received_total", null, message.length);
		if (this.mode === "legacy")
			this.websocket.send(message, {binary: true});
		else
			this.websocket.send(encodeFrame(remote.address, remote.port, message), {binary: true});
	}

	// One bucket per source address, shared by all of its connections.
	consumeRate(bytes) {
		if (!this.limiter.consume(this.ip, bytes)) {
			this.metrics.inc("luanti_proxy_rate_limited_total");
			throw new ProxyError("UDP rate limit exceeded", "rate_limited");
		}
	}

	sendText(text) {
		if (this.websocket && this.websocket.readyState === WebSocket.OPEN)
			this.websocket.send(text, {binary: false});
	}

	close(code = 1000, reason = "", tag = "closed") {
		if (this.closed)
			return;
		this.closed = true;
		this.endReason = tag;
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
		this.onClosed(this, tag);
	}
}

export function createProxyServer(userOptions = {}) {
	const options = /** @type {any} */ ({...defaultConfig(), ...userOptions});
	if (!isLoopbackHost(options.host) && !options.allowedOrigins)
		throw new Error("LUANTI_PROXY_ALLOWED_ORIGINS must be set (use * to allow every origin) " +
			"when listening on a non-loopback address");

	const log = options.log || defaultLog;
	const metrics = new Metrics();
	const tracker = new ConnectionTracker(options);
	const limiter = options.limiter || new RateLimiter({
		packetsPerSecond: options.maxPacketsPerSecond, bytesPerSecond: options.maxBytesPerSecond});
	const registry = options.registry || (options.serverListUrl ? new ServerRegistry({
		url: options.serverListUrl, refreshMs: options.serverListRefreshMs, log}) : null);
	const policy = new TargetPolicy({
		allowedTargets: options.allowedTargets, allowPublic: options.allowPublic,
		allowedPorts: options.allowedPorts, registry});
	const sessions = new Set();

	metrics.gauge("luanti_proxy_connections_active", () => tracker.total);
	if (registry)
		metrics.gauge("luanti_proxy_registry_targets", () => registry.size);

	const httpServer = http.createServer((request, response) => {
		const path = (request.url || "").split("?")[0];
		const reply = (status, type, body) => {
			response.writeHead(status, {"Content-Type": type, "Cache-Control": "no-store"});
			response.end(body);
		};
		if (request.method === "GET" && path === "/healthz") {
			reply(200, "application/json", JSON.stringify({
				status: "ok", connections: tracker.total,
				registry: registry ? {loaded: registry.loaded, targets: registry.size} : undefined}));
		} else if (request.method === "GET" && path === "/metrics") {
			if (!metricsAuthorized(request, options))
				reply(options.metricsToken ? 401 : 404, "text/plain", "not available\n");
			else
				reply(200, "text/plain; version=0.0.4", metrics.render());
		} else {
			reply(404, "text/plain", "Luanti WebSocket UDP proxy\n");
		}
	});

	const server = new WebSocketServer({
		server: httpServer, maxPayload: 65519, perMessageDeflate: false,
		verifyClient: (info, callback) => {
			const ip = clientAddress(info.req, options.trustProxy);
			const reject = (reason, status, message) => {
				metrics.inc("luanti_proxy_connections_rejected_total", {reason});
				log("warn", "connection_rejected", {reason, ip, origin: info.origin || null});
				callback(false, status, message);
			};
			if (!originAllowed(options.allowedOrigins, info.origin))
				return reject("origin", 403, "Origin not allowed");
			const full = tracker.check(ip);
			if (full)
				return reject(full, full === "global_limit" ? 503 : 429, "Too many connections");
			callback(true);
		},
	});

	server.on("connection", (websocket, request) => {
		const ip = clientAddress(request, options.trustProxy);
		// verifyClient checked too, but connections can arrive in the same tick.
		const full = tracker.acquire(ip);
		if (full) {
			metrics.inc("luanti_proxy_connections_rejected_total", {reason: full});
			log("warn", "connection_rejected", {reason: full, ip});
			websocket.close(1013, "Too many connections");
			return;
		}
		metrics.inc("luanti_proxy_connections_total");
		const session = new UDPProxySession(websocket, options, {
			ip, limiter, policy, metrics, log,
			onClosed: (closed, tag) => {
				tracker.release(ip);
				sessions.delete(closed);
				metrics.inc("luanti_proxy_sessions_closed_total", {reason: tag});
				log("info", "session_closed", {ip, reason: tag, mode: closed.mode,
					seconds: Math.round((Date.now() - closed.createdAt) / 1000)});
			},
		});
		sessions.add(session);
		log("info", "session_opened", {ip, origin: request.headers.origin || null});
		websocket.on("message", (data, isBinary) => session.receive(data, isBinary));
		websocket.on("error", () => session.close(1011, "", "socket_error"));
		websocket.on("close", () => session.close(1000, "", "client_closed"));
	});

	const sweeper = setInterval(() => {
		const now = Date.now();
		for (const session of sessions) {
			if (!session.mode && now - session.createdAt > options.handshakeTimeoutMs)
				session.close(1008, "handshake timeout", "handshake_timeout");
			else if (now - session.lastActivity > options.idleTimeoutMs)
				session.close(1001, "idle timeout", "idle");
		}
	}, options.sweepIntervalMs);
	sweeper.unref();

	if (registry)
		registry.start();

	const closeServer = server.close.bind(server);
	server.close = callback => {
		clearInterval(sweeper);
		if (registry)
			registry.stop();
		for (const session of [...sessions])
			session.close(1001, "server shutting down", "shutdown");
		closeServer(() => {});
		httpServer.close(callback);
		httpServer.closeAllConnections();
		return server;
	};
	server.proxy = {options, sessions, metrics, tracker, limiter, policy, registry};
	httpServer.listen(options.port, options.host);
	return server;
}

function metricsAuthorized(request, options) {
	const header = String(request.headers.authorization || "");
	if (options.metricsToken) {
		const expected = Buffer.from("Bearer " + options.metricsToken);
		const given = Buffer.from(header);
		return given.length === expected.length && crypto.timingSafeEqual(given, expected);
	}
	// Without a token, only a direct local request (not via a reverse proxy).
	return isLoopbackHost((request.socket.remoteAddress || "").replace(/^::ffff:/, "")) &&
		!request.headers["x-forwarded-for"];
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
	const server = createProxyServer();
	const {options} = server.proxy;
	server.on("listening", () => {
		const address = server.address();
		defaultLog("info", "listening", {
			address: address.address, port: address.port,
			publicTargets: options.allowPublic,
			allowedPorts: options.allowPublic && !options.serverListUrl ? options.allowedPorts : undefined,
			serverList: options.serverListUrl || undefined,
			origins: !options.allowedOrigins ? "loopback only" :
				options.allowedOrigins.any ? "any" : "restricted",
			maxConnections: options.maxConnections,
			maxConnectionsPerIp: options.maxConnectionsPerIp,
		});
	});
	for (const signal of ["SIGINT", "SIGTERM"]) {
		process.once(signal, () => {
			defaultLog("info", "shutdown", {signal});
			server.close(() => process.exit(0));
		});
	}
}
