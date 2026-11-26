// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 The Luanti Contributors

// Checks a deployed proxy from the outside, the way a page would meet it:
//
//   node check.mjs wss://proxy.example.org/ --origin https://play.example.org
//
// It answers "is this deployment reachable, and is it an allowlist rather than
// an open relay?" without a browser and without a game server:
//
//   tls         the wss:// connection verifies the certificate and upgrades
//   handshake   the allowed origin gets PROXY OK 1
//   rtt         PING/PONG round trips over that connection
//   origin      an origin that is not allowed is closed with `origin: ...` (1008)
//   target      a datagram for an address that must not be allowed (default
//               192.0.2.1:30000, reserved for documentation) is closed with
//               `target_denied: ...` (1008); the proxy refuses it before any UDP
//               leaves, and nothing is ever sent to a target that IS allowed
//   metrics     /metrics is not readable from the internet
//
// Exits 1 if any check fails. Needs `npm ci` in this directory (the `ws` client).

import {pathToFileURL} from "node:url";
import {WebSocket} from "ws";
import {encodeFrame} from "./protocol.mjs";

const DEFAULT_BAD_ORIGIN = "https://luanti-acceptance.invalid";
const DEFAULT_DENIED_TARGET = "192.0.2.1:30000";

/** Open a socket with an Origin header and settle on the first useful event. */
function dial(url, origin, timeoutMs) {
	return new Promise(resolve => {
		const socket = new WebSocket(url, {origin, handshakeTimeout: timeoutMs});
		const result = {socket, opened: false, closed: null, error: null, messages: []};
		const waiters = [];
		const settle = () => waiters.splice(0).forEach(waiter => waiter());
		socket.on("open", () => {
			result.opened = true;
			settle();
		});
		socket.on("message", (data, isBinary) => {
			result.messages.push({text: isBinary ? null : data.toString(), isBinary});
			settle();
		});
		socket.on("error", error => {
			result.error = error;
			settle();
		});
		socket.on("close", (code, reason) => {
			result.closed = {code, reason: reason.toString()};
			settle();
		});
		result.wait = (predicate, ms = timeoutMs) => new Promise(done => {
			if (predicate(result))
				return done(true);
			const timer = setTimeout(() => done(predicate(result)), ms);
			waiters.push(function again() {
				if (predicate(result)) {
					clearTimeout(timer);
					done(true);
				} else {
					waiters.push(again);
				}
			});
		});
		resolve(result);
	});
}

export function parseTarget(value) {
	const separator = value.lastIndexOf(":");
	const address = value.slice(0, separator);
	const port = Number(value.slice(separator + 1));
	if (separator < 1 || !Number.isInteger(port) || port < 1 || port > 65535)
		throw new Error(`expected host:port, got ${value}`);
	return {address, port};
}

function httpUrl(proxyUrl, path) {
	const url = new URL(proxyUrl);
	url.protocol = url.protocol === "wss:" ? "https:" : "http:";
	url.pathname = path;
	url.search = "";
	return url.href;
}

/**
 * @param {object} options
 * @param {string} options.url wss:// (or ws://, for a local proxy) URL
 * @param {string} options.origin an origin the proxy is configured to allow
 * @param {string} [options.badOrigin] an origin it must refuse; "" skips the check
 * @param {string} [options.deniedTarget] host:port it must refuse; "" skips the check
 * @param {number} [options.timeoutMs]
 * @returns {Promise<Array<{name: string, ok: boolean, detail: string}>>}
 */
export async function runChecks({url, origin, badOrigin = DEFAULT_BAD_ORIGIN,
		deniedTarget = DEFAULT_DENIED_TARGET, timeoutMs = 10000}) {
	const checks = [];
	const record = (name, ok, detail) => checks.push({name, ok: !!ok, detail});
	const parsed = new URL(url);
	if (parsed.protocol !== "wss:" && parsed.protocol !== "ws:")
		throw new Error("the proxy URL must be wss:// (or ws:// for a local proxy)");

	// tls + handshake: the allowed origin gets in.
	const good = await dial(url, origin, timeoutMs);
	if (!(await good.wait(r => r.opened || r.error || r.closed))) {
		record("tls", false, `no answer within ${timeoutMs / 1000} s`);
	} else if (!good.opened) {
		record("tls", false, good.error ? good.error.message : "closed before the upgrade finished" +
			(good.closed ? ` (${good.closed.code} ${good.closed.reason})` : ""));
	} else {
		record("tls", true, parsed.protocol === "wss:" ?
			"certificate verified, WebSocket upgraded" : "plain ws:// (local use only)");
		good.socket.send("PROXY IPV4 UDP 1");
		await good.wait(r => r.messages.length > 0 || r.closed);
		const first = good.messages[0];
		if (first && first.text === "PROXY OK 1") {
			record("handshake", true, `PROXY OK 1 for origin ${origin}`);
			const samples = [];
			for (let id = 1; id <= 5; id++) {
				const sent = performance.now();
				const before = good.messages.length;
				good.socket.send(`PING ${id} ${sent}`);
				if (!(await good.wait(r => r.messages.length > before || r.closed, 5000)) ||
						good.closed)
					break;
				const reply = good.messages[good.messages.length - 1];
				if (reply.text && reply.text.startsWith(`PONG ${id} `))
					samples.push(performance.now() - sent);
			}
			samples.sort((a, b) => a - b);
			record("rtt", samples.length === 5, samples.length ?
				`${samples.length}/5 answered, min ${samples[0].toFixed(0)} ms, ` +
				`median ${samples[Math.floor(samples.length / 2)].toFixed(0)} ms, ` +
				`max ${samples[samples.length - 1].toFixed(0)} ms` : "no PONG");
		} else {
			record("handshake", false, good.closed ?
				`closed with ${good.closed.code} "${good.closed.reason}": is ${origin} in the proxy's ` +
				"allowed origins?" : `unexpected reply ${JSON.stringify(first && first.text)}`);
		}
	}

	// origin: an origin the proxy was not configured for. A refused page gets
	// its upgrade and is closed at once; an accepted one answers the handshake.
	if (badOrigin) {
		const bad = await dial(url, badOrigin, timeoutMs);
		await bad.wait(r => r.opened || r.closed || r.error);
		if (bad.opened && !bad.closed) {
			bad.socket.send("PROXY IPV4 UDP 1");
			await bad.wait(r => r.messages.length > 0 || r.closed);
		}
		const refused = bad.opened && bad.closed && bad.closed.code === 1008 &&
			bad.closed.reason.startsWith("origin:");
		const accepted = bad.messages.some(message => message.text === "PROXY OK 1");
		record("origin", refused, refused ? `${badOrigin} refused: ${bad.closed.reason}` : accepted ?
			`${badOrigin} was ACCEPTED: LUANTI_PROXY_ALLOWED_ORIGINS may be too wide` : bad.closed ?
			`${badOrigin} closed with ${bad.closed.code} "${bad.closed.reason}", not an origin refusal` :
			`no refusal seen (${bad.error ? bad.error.message : "timeout"})`);
		bad.socket.terminate();
	}

	// target: a datagram toward an address that must not be allowed. The proxy
	// closes before any UDP is sent, so this never touches a third party.
	if (deniedTarget && good.opened) {
		const {address, port} = parseTarget(deniedTarget);
		const probe = await dial(url, origin, timeoutMs);
		await probe.wait(r => r.opened || r.error || r.closed);
		if (probe.opened) {
			probe.socket.send("PROXY IPV4 UDP 1");
			await probe.wait(r => r.messages.length > 0 || r.closed);
			probe.socket.send(encodeFrame(address, port, Buffer.from([0])));
			await probe.wait(r => r.closed);
			const denied = probe.closed && probe.closed.code === 1008 &&
				probe.closed.reason.startsWith("target_denied:");
			record("target", denied, denied ? `${deniedTarget} refused: ${probe.closed.reason}` :
				`${deniedTarget} was NOT refused (${probe.closed ? probe.closed.code + ' "' + probe.closed.reason + '"' : "still open"}): ` +
				"the allowlist is too wide for a public deployment");
		} else {
			record("target", false, "could not connect to run the check");
		}
		probe.socket.terminate();
	}

	// metrics: Prometheus text must not be readable by the internet.
	try {
		const response = await fetch(httpUrl(url, "/metrics"), {signal: AbortSignal.timeout(timeoutMs)});
		record("metrics", response.status !== 200, response.status === 200 ?
			"/metrics is public: hide it in the reverse proxy (deploy/Caddyfile does)" :
			`/metrics answers ${response.status}`);
	} catch (error) {
		record("metrics", false, `could not ask: ${error.message}`);
	}

	good.socket.terminate();
	return checks;
}

function usage() {
	return "usage: node check.mjs <wss-url> --origin <allowed origin> [--bad-origin <origin>|none] " +
		"[--denied <host:port>|none] [--json]\n";
}

async function main(argv) {
	const options = /** @type {any} */ ({badOrigin: DEFAULT_BAD_ORIGIN, deniedTarget: DEFAULT_DENIED_TARGET});
	let json = false;
	const positional = [];
	for (let i = 0; i < argv.length; i++) {
		const value = argv[i];
		if (value === "--origin")
			options.origin = argv[++i];
		else if (value === "--bad-origin")
			options.badOrigin = argv[++i] === "none" ? "" : argv[i];
		else if (value === "--denied")
			options.deniedTarget = argv[++i] === "none" ? "" : argv[i];
		else if (value === "--json")
			json = true;
		else if (value.startsWith("--"))
			throw new Error(`unknown option ${value}`);
		else
			positional.push(value);
	}
	if (positional.length !== 1 || !options.origin) {
		process.stderr.write(usage());
		return 2;
	}
	options.url = positional[0];
	const checks = await runChecks(options);
	if (json) {
		process.stdout.write(JSON.stringify(checks, null, 2) + "\n");
	} else {
		for (const check of checks)
			process.stdout.write(`${check.ok ? "ok  " : "FAIL"} ${check.name.padEnd(9)} ${check.detail}\n`);
	}
	return checks.every(check => check.ok) ? 0 : 1;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
	main(process.argv.slice(2)).then(code => process.exit(code), error => {
		process.stderr.write(`${error.message}\n`);
		process.exit(2);
	});
}
