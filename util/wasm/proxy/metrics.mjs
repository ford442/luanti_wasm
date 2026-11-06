// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 The Luanti Contributors

const HELP = {
	luanti_proxy_connections_total: ["counter", "WebSocket connections accepted."],
	luanti_proxy_connections_rejected_total: ["counter", "WebSocket connections refused, by reason."],
	luanti_proxy_sessions_closed_total: ["counter", "Sessions ended, by reason."],
	luanti_proxy_datagrams_forwarded_total: ["counter", "Datagrams sent from browsers to UDP targets."],
	luanti_proxy_bytes_forwarded_total: ["counter", "Bytes sent from browsers to UDP targets."],
	luanti_proxy_datagrams_received_total: ["counter", "Datagrams relayed from UDP targets to browsers."],
	luanti_proxy_bytes_received_total: ["counter", "Bytes relayed from UDP targets to browsers."],
	luanti_proxy_rate_limited_total: ["counter", "Datagrams refused by the per-address rate limit."],
	luanti_proxy_targets_denied_total: ["counter", "Datagrams or handshakes refused by the target policy."],
	luanti_proxy_connections_active: ["gauge", "Currently open WebSocket connections."],
	luanti_proxy_registry_targets: ["gauge", "Endpoints currently allowed by the server-list registry."],
};

function escapeLabel(value) {
	return String(value).replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n");
}

export class Metrics {
	constructor() {
		this.values = new Map();
		this.gauges = new Map();
	}

	inc(name, labels = null, amount = 1) {
		const key = name + (labels ? "|" + Object.entries(labels).map(
			([k, v]) => `${k}="${escapeLabel(v)}"`).join(",") : "");
		this.values.set(key, (this.values.get(key) || 0) + amount);
	}

	// Gauges are read when rendered.
	gauge(name, read) {
		this.gauges.set(name, read);
	}

	render() {
		const lines = [];
		const seen = new Set();
		const emit = (name, labelText, value) => {
			if (!seen.has(name)) {
				seen.add(name);
				const [type, help] = HELP[name] || ["untyped", name];
				lines.push(`# HELP ${name} ${help}`, `# TYPE ${name} ${type}`);
			}
			lines.push(`${name}${labelText ? "{" + labelText + "}" : ""} ${value}`);
		};
		// Counters that were never touched still appear, so rate() has a series.
		for (const [name, [type]] of Object.entries(HELP)) {
			if (type === "counter" && ![...this.values.keys()].some(k => k.split("|")[0] === name))
				emit(name, "", 0);
		}
		for (const [key, value] of this.values) {
			const [name, labelText] = key.split("|");
			emit(name, labelText, value);
		}
		for (const [name, read] of this.gauges)
			emit(name, "", read());
		return lines.join("\n") + "\n";
	}
}
