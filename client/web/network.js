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

	function proxyHost() {
		try {
			return new URL(configuredUrl).host;
		} catch (_) {
			return configuredUrl || "the proxy";
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
	 * @returns {NetworkCloseVerdict}
	 */
	function describeClose(code, reasonText, opened) {
		var host = proxyHost();
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
			ws.send("PROXY IPV4 UDP 1");
		};
		ws.onmessage = function(event) {
			try {
				if (link["state"] !== "ready") {
					if (event.data !== "PROXY OK 1")
						throw new Error("Proxy rejected protocol version 1");
					link["state"] = "ready";
					link["backoff"] = 0;
					link["retryAt"] = 0;
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
							Math.round(performance.now() - Number(pong[2])));
						emitState("ready", null);
						return;
					}
					throw new Error("Unexpected proxy control message");
				}
				var frame = decodeFrame(event.data);
				snapshot["receivedPackets"]++;
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
			emitState(configuredUrl ? "idle" : "disabled", null);
			return copyState();
		},
		"getState": copyState,
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
