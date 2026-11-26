// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 The Luanti Contributors

import dns from "node:dns/promises";
import net from "node:net";

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

// "30000-30010,31000" -> [[30000, 30010], [31000, 31000]]
export function parsePortRanges(value) {
	const ranges = [];
	for (const entry of String(value).split(",").map(item => item.trim()).filter(Boolean)) {
		const match = /^(\d{1,5})(?:-(\d{1,5}))?$/.exec(entry);
		const low = match ? Number(match[1]) : NaN;
		const high = match ? Number(match[2] || match[1]) : NaN;
		if (!match || low < 1 || high > 65535 || low > high)
			throw new Error("LUANTI_PROXY_ALLOWED_PORTS contains an invalid range: " + entry);
		ranges.push([low, high]);
	}
	if (!ranges.length)
		throw new Error("LUANTI_PROXY_ALLOWED_PORTS is empty");
	return ranges;
}

export function portAllowed(ranges, port) {
	return ranges.some(([low, high]) => port >= low && port <= high);
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

// Origins are compared as exact strings ("https://play.example.org"). A
// leading "*." on the host matches any subdomain ("https://*.pages.dev").
// "*" alone allows every origin and has to be asked for explicitly.
export function parseAllowedOrigins(value) {
	const entries = String(value).split(",").map(item => item.trim()).filter(Boolean);
	if (!entries.length)
		return null;
	if (entries.includes("*"))
		return {any: true, exact: new Set(), patterns: []};
	const exact = new Set();
	const patterns = [];
	for (const entry of entries) {
		const match = /^(https?):\/\/(\*\.)?([A-Za-z0-9.-]+|\[[0-9a-fA-F:]+\])(:\d{1,5})?$/.exec(entry);
		if (!match)
			throw new Error("LUANTI_PROXY_ALLOWED_ORIGINS contains an invalid origin: " + entry);
		if (match[2]) {
			const host = match[3].replace(/[.]/g, "\\.");
			patterns.push(new RegExp(`^${match[1]}://[A-Za-z0-9-]+(?:\\.[A-Za-z0-9-]+)*\\.${host}${match[4] || ""}$`, "i"));
		} else {
			exact.add(entry.toLowerCase());
		}
	}
	return {any: false, exact, patterns};
}

export function originAllowed(allowed, origin) {
	if (!allowed || allowed.any)
		return true;
	if (!origin)
		return false;
	const lower = origin.toLowerCase();
	return allowed.exact.has(lower) || allowed.patterns.some(pattern => pattern.test(origin));
}

// Public servers the proxy may reach, taken from a Luanti server list
// (https://servers.luanti.org/list.json). Fails closed until the first
// successful refresh and keeps the last good list if a later one fails.
export class ServerRegistry {
	constructor({url, refreshMs = 600000, fetchImpl = fetch,
			lookup = host => dns.lookup(host, {family: 4}), maxEntries = 5000,
			log = /** @type {(...args: any[]) => void} */ (() => {})}) {
		this.url = url;
		this.refreshMs = refreshMs;
		this.fetchImpl = fetchImpl;
		this.lookup = lookup;
		this.maxEntries = maxEntries;
		this.log = log;
		this.endpoints = new Set();
		this.loaded = false;
		this.timer = null;
	}

	has(address, port) {
		return this.endpoints.has(address + ":" + port);
	}

	get size() {
		return this.endpoints.size;
	}

	async refresh() {
		const response = await this.fetchImpl(this.url, {signal: AbortSignal.timeout(15000)});
		if (!response.ok)
			throw new Error("server list: HTTP " + response.status);
		const payload = await response.json();
		const list = Array.isArray(payload && payload.list) ? payload.list : [];
		const next = new Set();
		for (const entry of list.slice(0, this.maxEntries)) {
			const port = Number(entry && entry.port);
			const host = String(entry && entry.address || "");
			if (!Number.isInteger(port) || port < 1 || port > 65535 || !host)
				continue;
			try {
				const address = net.isIPv4(host) ? host : (await this.lookup(host)).address;
				if (isPublicIPv4(address))
					next.add(address + ":" + port);
			} catch (_) {
				// Unresolvable entries are simply not reachable through the proxy.
			}
		}
		if (!next.size)
			throw new Error("server list: no usable entries");
		this.endpoints = next;
		this.loaded = true;
		this.log("info", "registry_refreshed", {targets: next.size});
	}

	start() {
		const run = () => this.refresh().catch(error =>
			this.log("warn", "registry_refresh_failed", {error: error.message}));
		const first = run();
		this.timer = setInterval(run, this.refreshMs);
		this.timer.unref();
		return first;
	}

	stop() {
		clearInterval(this.timer);
		this.timer = null;
	}
}

// Decides whether a datagram may be sent to address:port.
//  1. An exact entry in `allowedTargets` is always allowed (this is how a
//     private or local server is reached).
//  2. Otherwise `allowPublic` must be on, the address must be public IPv4,
//     and the endpoint must be in the server registry when one is configured,
//     or else the port must be inside `allowedPorts`.
export class TargetPolicy {
	constructor({allowedTargets, allowPublic, allowedPorts, registry = null}) {
		this.allowedTargets = allowedTargets;
		this.allowPublic = allowPublic;
		this.allowedPorts = allowedPorts;
		this.registry = registry;
	}

	check(address, port) {
		if (!net.isIPv4(address))
			return "IPv4 target required";
		if (this.allowedTargets.has(address + ":" + port))
			return null;
		if (!this.allowPublic || !isPublicIPv4(address))
			return "UDP target is not allowed";
		if (this.registry) {
			if (!this.registry.loaded)
				return "server list is not loaded yet";
			return this.registry.has(address, port) ? null : "UDP target is not a listed server";
		}
		return portAllowed(this.allowedPorts, port) ? null : "UDP port is not allowed";
	}
}
