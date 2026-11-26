// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 The Luanti Contributors

// Browser-main-thread client for Luanti's versioned UDP-over-WebSocket proxy.
// Public Module properties are quoted so they survive JS optimization.

(function() {
	"use strict";
	if (typeof window === "undefined" && typeof document === "undefined")
		return;

	/**
	 * The proxy connection behind one engine UDP socket handle. The fields
	 * after `queue` are set once a connection has been attempted.
	 * @typedef {Object} NetworkLink
	 * @property {number} handle
	 * @property {number} port
	 * @property {string} state One of idle, connecting, ready, closed, error.
	 * @property {WebSocket|null} ws
	 * @property {ArrayBuffer[]} queue Frames held until the link is ready.
	 * @property {boolean} [opened] Whether the WebSocket ever reached open.
	 * @property {Error|null} [failure] A malformed proxy message this end gave up on.
	 * @property {number} [backoff] Current retry delay in ms.
	 * @property {number} [readyAt] Date.now() when this connection completed the handshake.
	 * @property {number} [retryAt] Date.now() before which no reconnect is tried.
	 */

	/**
	 * How the proxy link ended, as passed on to emitState.
	 * @typedef {{reason: string|null, code: number}} NetworkCloseInfo
	 */

	/**
	 * The reading describeClose gives of a close.
	 * @typedef {{state: string, reason: string|null, message: string, retry: boolean}} NetworkCloseVerdict
	 */

	/**
	 * A decoded proxy frame: one UDP datagram and where it came from.
	 * @typedef {{address: string, port: number, payload: Uint8Array}} NetworkFrame
	 */

	/**
	 * Timing marks and receive statistics for one join, as performance.now()
	 * values (null until the moment happens). See copyTimings.
	 * @typedef {Object} NetworkSession
	 * @property {number|null} joinAt The launcher's mark, else the first datagram sent.
	 * @property {boolean} joinMarked Whether joinAt came from the launcher.
	 * @property {number|null} probeMs How long the pre-join probe needed to reach PROXY OK.
	 * @property {number|null} openAt The first WebSocket open.
	 * @property {number|null} readyAt The first PROXY OK.
	 * @property {number|null} firstSendAt
	 * @property {number|null} firstReceiveAt
	 * @property {number|null} firstPlayerPosAt The first TOSERVER_PLAYERPOS the engine sent.
	 * @property {number|null} lastReceiveAt
	 * @property {number} received Datagrams received from the proxy.
	 * @property {number} gaps100 Pauses of at least 100 ms between received datagrams.
	 * @property {number} gaps250 Pauses of at least STALL_GAP_MS.
	 * @property {number} gaps1000 Pauses of at least 1 s.
	 * @property {number} longestGapMs
	 * @property {{until: number, frames: number, gap: number}|null} burst A long pause whose
	 *   aftermath is still being watched for a pile-up of datagrams.
	 * @property {number} stalls Long pauses followed by a pile-up: the signature of
	 *   a lost TCP segment holding back everything behind it.
	 * @property {number} longestStallMs
	 * @property {number} rttCount
	 * @property {number|null} rttMin
	 * @property {number|null} rttMax
	 * @property {number} rttSum
	 */

	/**
	 * What probe() found out about a proxy before the engine was started.
	 * @typedef {Object} NetworkProbeResult
	 * @property {boolean} ok The proxy accepted the page and the protocol version.
	 * @property {string} url
	 * @property {string} message A sentence for the player; empty when ok.
	 * @property {string|null} reason The proxy's close tag, or "timeout" (this end gave up).
	 * @property {number|null} closeCode
	 * @property {number|null} handshakeMs Time from dialling to PROXY OK (TLS included).
	 * @property {number|null} rttMs One PING/PONG round trip over the open link.
	 */

	var MAGIC = 0x778B4CF3;
	var HEADER_SIZE = 12;
	var MAX_DATAGRAM = 65507;
	/** @type {Map<number, NetworkLink>} */
	var links = new Map();
	/** @type {Map<string, string>} */
	var hostnames = new Map();
	var pingSequence = 0;
	var configuredUrl = readConfiguredUrl();
	/** @type {LuantiNetworkState} */
	var snapshot = {
		"state": configuredUrl ? "idle" : "disabled",
		"url": configuredUrl || null,
		"rttMs": null,
		"sentPackets": 0,
		"receivedPackets": 0,
		"droppedPackets": 0,
		"error": null,
		// The tag the proxy gave for closing the link (origin, per_ip_limit,
		// global_limit, target_denied, rate_limited, ...) and the WebSocket
		// close code, when the link ended on the proxy's initiative.
		"reason": null,
		"closeCode": null
	};
	// A refused or unreachable proxy is not retried on every datagram: the
	// engine resends its handshake several times a second.
	var RETRY_FIRST_MS = 1000;
	var RETRY_MAX_MS = 30000;
	// The retry delay starts over only for a link that stayed up this long. The
	// handshake alone proves nothing: a proxy that refuses the target does so
	// after PROXY OK, on the first datagram, so a reset there would redial once
	// a second for as long as the engine keeps resending.
	var STABLE_LINK_MS = 10000;

	// What the TCP hop costs (util/wasm/proxy/README.md, "Measuring the TCP
	// hop"). A pause between server datagrams of at least STALL_GAP_MS that
	// ends with STALL_BURST_FRAMES arriving within STALL_BURST_MS of each other
	// is counted as a stall: that is what a lost segment looks like from the
	// page, because TCP holds every later datagram until the hole is filled.
	var STALL_GAP_MS = 250;
	var STALL_BURST_MS = 20;
	var STALL_BURST_FRAMES = 3;
	var PROBE_TIMEOUT_MS = 8000;
	var PROBE_PONG_WAIT_MS = 1500;
	// Luanti's UDP header is protocol id 0x4f457403, peer id (2), channel (1),
	// then the packet type; an ORIGINAL (1) packet carries a big-endian command
	// next. TOSERVER_PLAYERPOS (0x23) is sent unreliably, so it is that bare.
	// Read only to time the join; nothing is parsed otherwise and the datagram
	// is forwarded untouched.
	var TOSERVER_PLAYERPOS = 0x23;

	/** @returns {number} */
	function now() {
		return typeof performance !== "undefined" ? performance.now() : Date.now();
	}

	/** @returns {NetworkSession} */
	function newSession() {
		return {
			"joinAt": null, "joinMarked": false, "probeMs": null, "openAt": null, "readyAt": null,
			"firstSendAt": null, "firstReceiveAt": null, "firstPlayerPosAt": null,
			"lastReceiveAt": null, "received": 0,
			"gaps100": 0, "gaps250": 0, "gaps1000": 0, "longestGapMs": 0, "burst": null,
			"stalls": 0, "longestStallMs": 0,
			"rttCount": 0, "rttMin": null, "rttMax": null, "rttSum": 0
		};
	}
	var session = newSession();

	function readConfiguredUrl() {
		var queryUrl = null;
		if (typeof location !== "undefined") {
			try {
				queryUrl = new URLSearchParams(location.search).get("proxy");
			} catch (_) {
			}
		}
		var stored = null;
		try {
			stored = localStorage.getItem("luanti.proxyUrl");
		} catch (_) {
		}
		return String(queryUrl || Module["luantiProxyUrl"] || stored || "").trim();
	}

	/**
	 * @param {string} value
	 * @returns {string}
	 */
	function validateUrl(value) {
		if (!value)
			return "";
		var url = new URL(value, typeof location !== "undefined" ? location.href : undefined);
		if (url.protocol !== "ws:" && url.protocol !== "wss:")
			throw new Error("Proxy URL must use ws:// or wss://");
		if (typeof location !== "undefined" && location.protocol === "https:" &&
				url.protocol !== "wss:")
			throw new Error("HTTPS pages require a wss:// proxy");
		return url.href;
	}

	/** @returns {LuantiNetworkState} */
	function copyState() {
		return {
			"state": snapshot["state"],
			"url": snapshot["url"],
			"rttMs": snapshot["rttMs"],
			"sentPackets": snapshot["sentPackets"],
			"receivedPackets": snapshot["receivedPackets"],
			"droppedPackets": snapshot["droppedPackets"],
			"error": snapshot["error"],
			"reason": snapshot["reason"],
			"closeCode": snapshot["closeCode"]
		};
	}

	/** @param {LuantiNetworkState} state */
	function updateShell(state) {
		if (typeof document === "undefined")
			return;
		var status = document.getElementById("luanti-network-status");
		var error = document.getElementById("luanti-network-error");
		var input = /** @type {HTMLInputElement|null} */ (document.getElementById("luanti-proxy-url"));
		if (input && document.activeElement !== input)
			input.value = state["url"] || "";
		if (status) {
			/** @type {Record<string, string>} */
			var labels = {
				"disabled": "Multiplayer proxy disabled",
				"idle": "Multiplayer proxy configured",
				"connecting": "Connecting to multiplayer proxy…",
				"ready": "Multiplayer proxy connected",
				"closed": "Multiplayer proxy disconnected",
				"error": "Multiplayer proxy error"
			};
			var label = labels[state["state"]] || state["state"];
			if (state["rttMs"] !== null && state["state"] === "ready")
				label += " (" + state["rttMs"] + " ms)";
			status.textContent = label;
			status.dataset.state = state["state"];
		}
		if (error) {
			error.textContent = state["error"] || "";
			error.hidden = !state["error"];
		}
	}

	/**
	 * @param {string} state
	 * @param {Error|null} error
	 * @param {NetworkCloseInfo} [info]
	 */
	function emitState(state, error, info) {
		snapshot["state"] = state;
		snapshot["url"] = configuredUrl || null;
		snapshot["error"] = error ? String(error.message || error) : null;
		snapshot["reason"] = info ? info["reason"] || null : null;
		snapshot["closeCode"] = info && typeof info["code"] === "number" ? info["code"] : null;
		var detail = copyState();
		updateShell(detail);
		// The launcher shows the message where the player is looking: the
		// loading shell and game shell cover the connect panel once a join starts.
		var launcher = Module["luantiLauncher"];
		if (launcher && typeof launcher["reportProxyStatus"] === "function") {
			try {
				launcher["reportProxyStatus"](detail);
			} catch (reportError) {
				console.error("Luanti multiplayer proxy: launcher report failed:", reportError);
			}
		}
		if (typeof window !== "undefined" && window.dispatchEvent)
			window.dispatchEvent(new CustomEvent("luanti:network", {"detail": detail}));
	}

	/** @param {string} [url] The proxy URL; the configured one by default. */
	function proxyHost(url) {
		var value = url === undefined ? configuredUrl : url;
		try {
			return new URL(value).host;
		} catch (_) {
			return value || "the proxy";
		}
	}

	function pageOrigin() {
		var origin = typeof location !== "undefined" ? location.origin : "";
		return origin && origin !== "null" ? origin : "";
	}

	// The proxy closes every link it ends with "<tag>: <detail>"
	// (util/wasm/proxy/README.md, "Close reasons"). A browser cannot read the
	// HTTP status of a failed upgrade, so this text and the close code are all
	// there is to tell a refusing proxy from a dead one.
	// `opened` is whether the WebSocket ever reached the open state.
	// Returns {state, reason, message, retry}: `retry` is false for a close the
	// proxy ended in an ordinary way, where the next datagram may reconnect at once.
	/**
	 * @param {number} code WebSocket close code.
	 * @param {string} reasonText WebSocket close reason.
	 * @param {boolean} opened
	 * @param {string} [url] The proxy that closed; the configured one by default.
	 * @returns {NetworkCloseVerdict}
	 */
	function describeClose(code, reasonText, opened, url) {
		var host = proxyHost(url);
		var parsed = /^([a-z][a-z_]*)(?:: (.*))?$/.exec(String(reasonText || ""));
		var tag = parsed ? parsed[1] : null;
		var detail = parsed ? parsed[2] || "" : String(reasonText || "");
		var proxy = "The proxy at " + host;
		var message;
		var state = "error";
		var retry = true;
		switch (tag) {
		case "origin":
			var origin = pageOrigin();
			message = proxy + " does not allow " + (origin ? "pages from " + origin : "this page") +
				". Its operator has to add this origin to the proxy's allowed origins.";
			break;
		case "per_ip_limit":
			message = proxy + " already has the most connections it allows from your network. " +
				"Close other Luanti tabs, or try again shortly.";
			break;
		case "global_limit":
			message = proxy + " is full right now. Try again shortly.";
			break;
		case "target_denied":
			message = proxy + " will not forward to that server" +
				(detail ? " (" + detail + ")" : "") + ".";
			break;
		case "rate_limited":
			message = proxy + " cut the connection because too much traffic was sent too quickly.";
			break;
		case "handshake_timeout":
			message = proxy + " closed the connection because the handshake took too long.";
			break;
		case "protocol":
			message = proxy + " rejected a message it could not understand" +
				(detail ? " (" + detail + ")" : "") + ".";
			break;
		case "udp_error":
			message = proxy + " could not use its UDP socket" + (detail ? " (" + detail + ")" : "") + ".";
			break;
		case "idle":
			message = proxy + " closed the connection after a period with no traffic.";
			state = "closed";
			retry = false;
			break;
		case "shutdown":
			message = proxy + " is shutting down or restarting. Try again shortly.";
			state = "closed";
			break;
		default:
			if (reasonText) {
				message = proxy + " closed the connection: " + reasonText + ".";
			} else if (!opened) {
				// Down, wrong address, a TLS failure, or an upgrade refused by
				// something in front of the proxy: the browser reports all of
				// them as close code 1006 with no reason.
				message = "Could not connect to the proxy at " + host +
					". It may be down, or the address may be wrong.";
			} else if (code === 1000 || code === 1001) {
				message = proxy + " closed the connection.";
				state = "closed";
				retry = false;
			} else {
				message = "Lost the connection to the proxy at " + host + ".";
			}
		}
		return {"state": state, "reason": tag, "message": message, "retry": retry};
	}

	/** @param {NetworkLink} link */
	function scheduleRetry(link) {
		link["backoff"] = Math.min(RETRY_MAX_MS, (link["backoff"] || RETRY_FIRST_MS / 2) * 2);
		link["retryAt"] = Date.now() + link["backoff"];
	}

	/**
	 * @param {string} address Dotted-quad IPv4 address.
	 * @returns {number}
	 */
	function ipv4Number(address) {
		var parts = address.split(".");
		if (parts.length !== 4)
			throw new Error("IPv4 address required");
		var value = 0;
		parts.forEach(function(part) {
			var octet = Number(part);
			if (!Number.isInteger(octet) || octet < 0 || octet > 255)
				throw new Error("Invalid IPv4 address");
			value = value * 256 + octet;
		});
		return value >>> 0;
	}

	/**
	 * @param {number} value
	 * @returns {string}
	 */
	function ipv4String(value) {
		return [(value >>> 24) & 255, (value >>> 16) & 255,
			(value >>> 8) & 255, value & 255].join(".");
	}

	/**
	 * @param {string} address Dotted-quad IPv4 address of the target.
	 * @param {number} port
	 * @param {Uint8Array} bytes The datagram payload.
	 * @returns {ArrayBuffer} The proxy frame: header followed by the payload.
	 */
	function encapsulate(address, port, bytes) {
		if (bytes.byteLength > MAX_DATAGRAM)
			throw new Error("UDP datagram exceeds proxy limit");
		var frame = new ArrayBuffer(HEADER_SIZE + bytes.byteLength);
		var view = new DataView(frame);
		view.setUint32(0, MAGIC);
		view.setUint32(4, ipv4Number(address));
		view.setUint16(8, port);
		view.setUint16(10, bytes.byteLength);
		new Uint8Array(frame, HEADER_SIZE).set(bytes);
		return frame;
	}

	/**
	 * @param {unknown} data A binary WebSocket message.
	 * @returns {NetworkFrame}
	 */
	function decodeFrame(data) {
		if (!(data instanceof ArrayBuffer) || data.byteLength < HEADER_SIZE)
			throw new Error("Proxy sent a truncated UDP frame");
		var view = new DataView(data);
		if (view.getUint32(0) !== MAGIC)
			throw new Error("Proxy sent an invalid UDP frame magic");
		var length = view.getUint16(10);
		if (data.byteLength !== HEADER_SIZE + length)
			throw new Error("Proxy sent an invalid UDP frame length");
		return {
			"address": ipv4String(view.getUint32(4)),
			"port": view.getUint16(8),
			"payload": new Uint8Array(data, HEADER_SIZE, length)
		};
	}

	/** @param {Error} error */
	function reportDrop(error) {
		snapshot["droppedPackets"]++;
		emitState("error", error);
		console.error("Luanti multiplayer proxy:", error);
	}

	/**
	 * @param {number} handle
	 * @param {NetworkFrame} frame
	 */
	function deliver(handle, frame) {
		var callback = Module["_luanti_websocket_proxy_receive"];
		if (typeof callback !== "function") {
			reportDrop(new Error("Wasm UDP receive callback is unavailable"));
			return;
		}
		var pointer = _malloc(frame["payload"].byteLength);
		try {
			HEAPU8.set(frame["payload"], pointer);
			callback(handle, pointer, frame["payload"].byteLength,
				ipv4Number(frame["address"]), frame["port"]);
		} finally {
			_free(pointer);
		}
	}

	/** @param {Uint8Array} bytes One outgoing datagram. */
	function isPlayerPosition(bytes) {
		return bytes.length >= 10 && bytes[0] === 0x4f && bytes[1] === 0x45 &&
			bytes[2] === 0x74 && bytes[3] === 0x03 && bytes[7] === 1 &&
			bytes[8] === 0 && bytes[9] === TOSERVER_PLAYERPOS;
	}

	/** @param {Uint8Array} bytes One outgoing datagram. */
	function noteSend(bytes) {
		var at = now();
		if (session["joinAt"] === null)
			session["joinAt"] = at;
		if (session["firstSendAt"] === null)
			session["firstSendAt"] = at;
		if (session["firstPlayerPosAt"] === null && isPlayerPosition(bytes))
			session["firstPlayerPosAt"] = at;
	}

	function noteReceive() {
		var at = now();
		var s = session;
		s["received"]++;
		if (s["firstReceiveAt"] === null)
			s["firstReceiveAt"] = at;
		var burst = s["burst"];
		if (burst) {
			if (at <= burst["until"]) {
				burst["frames"]++;
				if (burst["frames"] >= STALL_BURST_FRAMES) {
					s["stalls"]++;
					s["longestStallMs"] = Math.max(s["longestStallMs"], burst["gap"]);
					s["burst"] = null;
				}
			} else {
				s["burst"] = null;
			}
		}
		if (s["lastReceiveAt"] !== null) {
			var gap = at - s["lastReceiveAt"];
			s["longestGapMs"] = Math.max(s["longestGapMs"], gap);
			if (gap >= 100)
				s["gaps100"]++;
			if (gap >= STALL_GAP_MS) {
				s["gaps250"]++;
				s["burst"] = {"until": at + STALL_BURST_MS, "frames": 1, "gap": gap};
			}
			if (gap >= 1000)
				s["gaps1000"]++;
		}
		s["lastReceiveAt"] = at;
	}

	/** @param {number} rtt */
	function noteRtt(rtt) {
		var s = session;
		s["rttCount"]++;
		s["rttSum"] += rtt;
		s["rttMin"] = s["rttMin"] === null ? rtt : Math.min(s["rttMin"], rtt);
		s["rttMax"] = s["rttMax"] === null ? rtt : Math.max(s["rttMax"], rtt);
	}

	/** @returns {LuantiNetworkTimings} */
	function copyTimings() {
		var s = session;
		/** @param {number|null} mark */
		var since = function(mark) {
			return mark === null || s["joinAt"] === null ? null :
				Math.round((mark - s["joinAt"]) * 10) / 10;
		};
		return {
			"joinMarked": s["joinMarked"],
			"probeMs": s["probeMs"],
			"proxyOpenMs": since(s["openAt"]),
			"proxyReadyMs": since(s["readyAt"]),
			"firstSendMs": since(s["firstSendAt"]),
			"firstReceiveMs": since(s["firstReceiveAt"]),
			"firstPlayerPosMs": since(s["firstPlayerPosAt"]),
			"receivedDatagrams": s["received"],
			"gapsOver100Ms": s["gaps100"],
			"gapsOver250Ms": s["gaps250"],
			"gapsOver1000Ms": s["gaps1000"],
			"longestGapMs": Math.round(s["longestGapMs"]),
			"stalls": s["stalls"],
			"longestStallMs": Math.round(s["longestStallMs"]),
			"rtt": {
				"samples": s["rttCount"],
				"minMs": s["rttMin"],
				"maxMs": s["rttMax"],
				"meanMs": s["rttCount"] ? Math.round(s["rttSum"] / s["rttCount"]) : null
			}
		};
	}

	/**
	 * Dial a proxy once, before the engine exists, to learn whether a join can
	 * work at all: the TLS certificate is valid, the proxy is up, it accepts this
	 * page's origin and speaks protocol 1. No datagram is sent, so this says
	 * nothing about the game server: the proxy checks that on the first datagram
	 * (a refusal then arrives as a `target_denied` close).
	 * @param {string} value
	 * @param {number} [timeoutMs]
	 * @returns {Promise<NetworkProbeResult>}
	 */
	function probe(value, timeoutMs) {
		return new Promise(function(resolve) {
			/**
			 * @param {string} url
			 * @param {string} message
			 * @param {string|null} reason
			 * @param {number|null} closeCode
			 * @returns {NetworkProbeResult}
			 */
			var failure = function(url, message, reason, closeCode) {
				return {"ok": false, "url": url, "message": message, "reason": reason,
					"closeCode": closeCode, "handshakeMs": null, "rttMs": null};
			};
			var url = "";
			try {
				url = validateUrl(String(value || "").trim());
			} catch (error) {
				resolve(failure("", String(error && error.message || error), null, null));
				return;
			}
			if (!url) {
				resolve(failure("", "No multiplayer proxy is selected.", null, null));
				return;
			}
			var limit = timeoutMs && timeoutMs > 0 ? timeoutMs : PROBE_TIMEOUT_MS;
			var started = now();
			var opened = false;
			var done = false;
			/** @type {number|null} */
			var handshakeMs = null;
			/** @type {any} */
			var timer = null;
			/** @type {WebSocket|null} */
			var ws = null;
			/** @param {NetworkProbeResult} result */
			var finish = function(result) {
				if (done)
					return;
				done = true;
				clearTimeout(timer);
				if (ws) {
					ws.onopen = ws.onmessage = ws.onerror = ws.onclose = null;
					try {
						ws.close(1000, "probe done");
					} catch (_) {
					}
				}
				resolve(result);
			};
			/** @param {number|null} rtt */
			var succeed = function(rtt) {
				session["probeMs"] = handshakeMs === null ? null : Math.round(handshakeMs * 10) / 10;
				finish({"ok": true, "url": url, "message": "", "reason": null, "closeCode": null,
					"handshakeMs": session["probeMs"], "rttMs": rtt});
			};
			timer = setTimeout(function() {
				finish(failure(url, "The proxy at " + proxyHost(url) + " did not answer within " +
					Math.round(limit / 1000) + " seconds. It may be down or overloaded.", "timeout", null));
			}, limit);
			try {
				ws = new WebSocket(url);
			} catch (error) {
				finish(failure(url, String(error && error.message || error), null, null));
				return;
			}
			var socket = ws;
			socket.onopen = function() {
				opened = true;
				socket.send("PROXY IPV4 UDP 1");
			};
			socket.onmessage = function(event) {
				if (handshakeMs === null) {
					if (event.data !== "PROXY OK 1") {
						finish(failure(url, "The proxy at " + proxyHost(url) +
							" does not speak protocol version 1.", "protocol", null));
						return;
					}
					handshakeMs = now() - started;
					clearTimeout(timer);
					timer = setTimeout(function() { succeed(null); }, PROBE_PONG_WAIT_MS);
					socket.send("PING 0 " + now());
					return;
				}
				var pong = typeof event.data === "string" ?
					/^PONG (\d+) (\d+(?:\.\d+)?)$/.exec(event.data) : null;
				if (pong)
					succeed(Math.max(0, Math.round(now() - Number(pong[2]))));
			};
			socket.onerror = function() {};
			socket.onclose = function(event) {
				var verdict = describeClose(event.code, event.reason, opened, url);
				finish(failure(url, verdict["message"], verdict["reason"], event.code));
			};
		});
	}

	/** @param {NetworkLink} link */
	function sendMappings(link) {
		hostnames.forEach(function(hostname, address) {
			link["ws"].send("RESOLVE " + address + " " + hostname);
		});
	}

	/**
	 * @param {NetworkLink} link
	 * @returns {boolean}
	 */
	function openLink(link) {
		if (!configuredUrl)
			return false;
		if (link["ws"] && (link["state"] === "connecting" || link["state"] === "ready"))
			return true;

		link["state"] = "connecting";
		link["opened"] = false;
		link["failure"] = null;
		emitState("connecting", null);
		/** @type {WebSocket} */
		var ws;
		try {
			ws = new WebSocket(configuredUrl);
		} catch (error) {
			link["state"] = "error";
			scheduleRetry(link);
			emitState("error", error);
			return false;
		}
		link["ws"] = ws;
		ws.binaryType = "arraybuffer";
		ws.onopen = function() {
			link["opened"] = true;
			if (session["openAt"] === null)
				session["openAt"] = now();
			ws.send("PROXY IPV4 UDP 1");
		};
		ws.onmessage = function(event) {
			try {
				if (link["state"] !== "ready") {
					if (event.data !== "PROXY OK 1")
						throw new Error("Proxy rejected protocol version 1");
					link["state"] = "ready";
					if (session["readyAt"] === null)
						session["readyAt"] = now();
					link["readyAt"] = Date.now();
					sendMappings(link);
					link["queue"].forEach(function(frame) { ws.send(frame); });
					link["queue"] = [];
					emitState("ready", null);
					return;
				}
				if (typeof event.data === "string") {
					var pong = /^PONG (\d+) (\d+(?:\.\d+)?)$/.exec(event.data);
					if (pong) {
						snapshot["rttMs"] = Math.max(0,
							Math.round(now() - Number(pong[2])));
						noteRtt(snapshot["rttMs"]);
						emitState("ready", null);
						return;
					}
					throw new Error("Unexpected proxy control message");
				}
				var frame = decodeFrame(event.data);
				snapshot["receivedPackets"]++;
				noteReceive();
				deliver(link["handle"], frame);
			} catch (error) {
				link["failure"] = error;
				reportDrop(error);
				ws.close(1002, "protocol error");
			}
		};
		// Always followed by onclose, which has the close code and reason.
		ws.onerror = function() {};
		ws.onclose = function(event) {
			link["ws"] = null;
			// Datagrams queued for a link that never became ready are stale by
			// the time the next attempt succeeds; the engine resends what matters.
			snapshot["droppedPackets"] += link["queue"].length;
			link["queue"] = [];
			if (link["readyAt"] && Date.now() - link["readyAt"] >= STABLE_LINK_MS)
				link["backoff"] = 0;
			link["readyAt"] = 0;
			var failure = link["failure"];
			link["failure"] = null;
			if (failure) {
				// This end gave up on a malformed proxy message; keep that
				// message instead of the echo of our own close frame.
				link["state"] = "error";
				scheduleRetry(link);
				emitState("error", failure, {"reason": "protocol", "code": event.code});
				return;
			}
			var verdict = describeClose(event.code, event.reason, !!link["opened"]);
			link["state"] = verdict["state"];
			if (verdict["retry"])
				scheduleRetry(link);
			emitState(verdict["state"], new Error(verdict["message"]),
				{"reason": verdict["reason"], "code": event.code});
		};
		return true;
	}

	/** @param {NetworkLink} link */
	function closeLink(link) {
		if (link["ws"]) {
			link["ws"].onopen = link["ws"].onmessage =
				link["ws"].onerror = link["ws"].onclose = null;
			link["ws"].close();
		}
		link["ws"] = null;
		link["state"] = "closed";
		link["queue"] = [];
		link["backoff"] = 0;
		link["retryAt"] = 0;
	}

	var api = {
		/**
		 * @param {string} value
		 * @returns {LuantiNetworkState}
		 */
		"setProxyUrl": function(value) {
			configuredUrl = validateUrl(String(value || "").trim());
			try {
				if (configuredUrl)
					localStorage.setItem("luanti.proxyUrl", configuredUrl);
				else
					localStorage.removeItem("luanti.proxyUrl");
			} catch (_) {
			}
			links.forEach(closeLink);
			snapshot["rttMs"] = null;
			session = newSession();
			emitState(configuredUrl ? "idle" : "disabled", null);
			return copyState();
		},
		"getState": copyState,
		/**
		 * Start the clock for a join: the launcher calls this when the player
		 * presses Join, so the timings include everything the player waits for.
		 * Without it, the first datagram the engine sends is the join.
		 */
		"markJoin": function() {
			session = newSession();
			session["joinAt"] = now();
			session["joinMarked"] = true;
		},
		/** Timings and TCP-hop statistics of the current join. */
		"getTimings": copyTimings,
		"probe": probe,
		/**
		 * @param {number} handle
		 * @param {number} port
		 */
		"_createSocket": function(handle, port) {
			links.set(handle, {"handle": handle, "port": port, "state": "idle",
				"ws": null, "queue": []});
		},
		/** @param {number} handle */
		"_destroySocket": function(handle) {
			var link = links.get(handle);
			if (link)
				closeLink(link);
			links.delete(handle);
		},
		/**
		 * @param {string} address
		 * @param {string} hostname
		 */
		"_registerHostname": function(address, hostname) {
			if (!address || !hostname || address === hostname)
				return;
			hostnames.set(address, hostname);
			links.forEach(function(link) {
				if (link["state"] === "ready")
					link["ws"].send("RESOLVE " + address + " " + hostname);
			});
		},
		/**
		 * @param {number} handle
		 * @param {number} pointer Heap address of the datagram.
		 * @param {number} length
		 * @param {string} address Dotted-quad IPv4 address of the target.
		 * @param {number} port
		 * @returns {boolean}
		 */
		"_send": function(handle, pointer, length, address, port) {
			var link = links.get(handle);
			if (!link) {
				link = {"handle": handle, "port": 0, "state": "idle",
					"ws": null, "queue": []};
				links.set(handle, link);
			}
			if (!configuredUrl)
				return false;
			if (link["retryAt"] && Date.now() < link["retryAt"] && !link["ws"]) {
				snapshot["droppedPackets"]++;
				return false;
			}
			try {
				var bytes = new Uint8Array(length);
				bytes.set(HEAPU8.subarray(pointer, pointer + length));
				var frame = encapsulate(address, port, bytes);
				if (!openLink(link))
					return false;
				if (link["state"] === "ready")
					link["ws"].send(frame);
				else if (link["queue"].length < 256)
					link["queue"].push(frame);
				else {
					snapshot["droppedPackets"]++;
					return false;
				}
				snapshot["sentPackets"]++;
				noteSend(bytes);
				return true;
			} catch (error) {
				reportDrop(error);
				return false;
			}
		},
		"_test": {"encapsulate": encapsulate, "decodeFrame": decodeFrame}
	};

	try {
		configuredUrl = validateUrl(configuredUrl);
	} catch (error) {
		configuredUrl = "";
		emitState("error", error);
	}
	Module["luantiNetwork"] = api;

	setInterval(function() {
		links.forEach(function(link) {
			if (link["state"] === "ready") {
				pingSequence++;
				link["ws"].send("PING " + pingSequence + " " + performance.now());
			}
		});
	}, 5000);

	if (typeof document !== "undefined") {
		var initializeShell = function() {
			var form = document.getElementById("luanti-proxy-form");
			var input = /** @type {HTMLInputElement|null} */ (document.getElementById("luanti-proxy-url"));
			if (form && input) {
				input.value = configuredUrl;
				form.addEventListener("submit", function(event) {
					event.preventDefault();
					try {
						api["setProxyUrl"](input.value);
					} catch (error) {
						emitState("error", error);
					}
				});
			}
			updateShell(copyState());
		};
		if (document.readyState === "loading")
			document.addEventListener("DOMContentLoaded", initializeShell);
		else
			initializeShell();
	}
})();
