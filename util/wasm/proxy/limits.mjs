// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 The Luanti Contributors

// Token buckets shared by every connection from one source address, so that
// opening N WebSockets does not multiply a client's budget by N.
export class RateLimiter {
	constructor({packetsPerSecond, bytesPerSecond, now = Date.now, maxKeys = 10000}) {
		this.packetsPerSecond = packetsPerSecond;
		this.bytesPerSecond = bytesPerSecond;
		this.now = now;
		this.maxKeys = maxKeys;
		this.buckets = new Map();
	}

	// Returns true and spends the tokens, or false and spends nothing.
	consume(key, bytes) {
		const now = this.now();
		let bucket = this.buckets.get(key);
		if (!bucket) {
			if (this.buckets.size >= this.maxKeys)
				this.sweep(now);
			bucket = {packets: this.packetsPerSecond, bytes: this.bytesPerSecond, at: now};
			this.buckets.set(key, bucket);
		} else {
			const elapsed = Math.max(0, now - bucket.at) / 1000;
			bucket.packets = Math.min(this.packetsPerSecond,
				bucket.packets + elapsed * this.packetsPerSecond);
			bucket.bytes = Math.min(this.bytesPerSecond,
				bucket.bytes + elapsed * this.bytesPerSecond);
			bucket.at = now;
		}
		if (bucket.packets < 1 || bucket.bytes < bytes)
			return false;
		bucket.packets -= 1;
		bucket.bytes -= bytes;
		return true;
	}

	// Buckets that have refilled completely carry no information.
	sweep(now = this.now()) {
		for (const [key, bucket] of this.buckets) {
			if (now - bucket.at >= 1000)
				this.buckets.delete(key);
		}
		if (this.buckets.size >= this.maxKeys) {
			// Everything is busy: drop the oldest half rather than grow.
			let drop = Math.ceil(this.buckets.size / 2);
			for (const key of this.buckets.keys()) {
				if (drop-- <= 0)
					break;
				this.buckets.delete(key);
			}
		}
	}
}

// Counts live connections, overall and per source address.
export class ConnectionTracker {
	constructor({maxConnections, maxConnectionsPerIp}) {
		this.maxConnections = maxConnections;
		this.maxConnectionsPerIp = maxConnectionsPerIp;
		this.total = 0;
		this.perIp = new Map();
	}

	// Returns null when there is room, otherwise the reason it is refused.
	check(ip) {
		if (this.total >= this.maxConnections)
			return "global_limit";
		if ((this.perIp.get(ip) || 0) >= this.maxConnectionsPerIp)
			return "per_ip_limit";
		return null;
	}

	acquire(ip) {
		const reason = this.check(ip);
		if (reason)
			return reason;
		this.total++;
		this.perIp.set(ip, (this.perIp.get(ip) || 0) + 1);
		return null;
	}

	release(ip) {
		this.total = Math.max(0, this.total - 1);
		const left = (this.perIp.get(ip) || 1) - 1;
		if (left <= 0)
			this.perIp.delete(ip);
		else
			this.perIp.set(ip, left);
	}
}
