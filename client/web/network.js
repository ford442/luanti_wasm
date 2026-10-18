// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 The Luanti Contributors

// Browser-main-thread client for Luanti's versioned UDP-over-WebSocket proxy.
// Public Module properties are quoted so they survive JS optimization.

(function() {
	"use strict";
	if (typeof window === "undefined" && typeof document === "undefined")
		return;

	var MAGIC = 0x778B4CF3;
	var HEADER_SIZE = 12;
	var MAX_DATAGRAM = 65507;
	var links = new Map();
	var hostnames = new Map();
	var pingSequence = 0;
	var configuredUrl = readConfiguredUrl();
	var snapshot = {
		"state": configuredUrl ? "idle" : "disabled",
		"url": configuredUrl || null,
		"rttMs": null,
		"sentPackets": 0,
		"receivedPackets": 0,
		"droppedPackets": 0,
		"error": null
	};

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

	function copyState() {
		return {
			"state": snapshot["state"],
			"url": snapshot["url"],
			"rttMs": snapshot["rttMs"],
			"sentPackets": snapshot["sentPackets"],
			"receivedPackets": snapshot["receivedPackets"],
			"droppedPackets": snapshot["droppedPackets"],
			"error": snapshot["error"]
		};
	}

	function updateShell(state) {
		if (typeof document === "undefined")
			return;
		var status = document.getElementById("luanti-network-status");
		var error = document.getElementById("luanti-network-error");
		var input = document.getElementById("luanti-proxy-url");
		if (input && document.activeElement !== input)
			input.value = state["url"] || "";
		if (status) {
			var label = {
				"disabled": "Multiplayer proxy disabled",
				"idle": "Multiplayer proxy configured",
				"connecting": "Connecting to multiplayer proxy…",
				"ready": "Multiplayer proxy connected",
				"closed": "Multiplayer proxy disconnected",
				"error": "Multiplayer proxy error"
			}[state["state"]] || state["state"];
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

	function emitState(state, error) {
		snapshot["state"] = state;
		snapshot["url"] = configuredUrl || null;
		snapshot["error"] = error ? String(error.message || error) : null;
		var detail = copyState();
		updateShell(detail);
		if (typeof window !== "undefined" && window.dispatchEvent)
			window.dispatchEvent(new CustomEvent("luanti:network", {"detail": detail}));
	}

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

	function ipv4String(value) {
		return [(value >>> 24) & 255, (value >>> 16) & 255,
			(value >>> 8) & 255, value & 255].join(".");
	}

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

	function reportDrop(error) {
		snapshot["droppedPackets"]++;
		emitState("error", error);
		console.error("Luanti multiplayer proxy:", error);
	}

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

	function sendMappings(link) {
		hostnames.forEach(function(hostname, address) {
			link["ws"].send("RESOLVE " + address + " " + hostname);
		});
	}

	function openLink(link) {
		if (!configuredUrl)
			return false;
		if (link["ws"] && (link["state"] === "connecting" || link["state"] === "ready"))
			return true;

		link["state"] = "connecting";
		emitState("connecting", null);
		var ws;
		try {
			ws = new WebSocket(configuredUrl);
		} catch (error) {
			link["state"] = "error";
			emitState("error", error);
			return false;
		}
		link["ws"] = ws;
		ws.binaryType = "arraybuffer";
		ws.onopen = function() {
			ws.send("PROXY IPV4 UDP 1");
		};
		ws.onmessage = function(event) {
			try {
				if (link["state"] !== "ready") {
					if (event.data !== "PROXY OK 1")
						throw new Error("Proxy rejected protocol version 1");
					link["state"] = "ready";
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
				reportDrop(error);
				ws.close(1002, "protocol error");
			}
		};
		ws.onerror = function() {
			link["state"] = "error";
			emitState("error", new Error("WebSocket connection failed"));
		};
		ws.onclose = function(event) {
			link["ws"] = null;
			if (link["state"] !== "error") {
				link["state"] = "closed";
				emitState("closed", event.reason || "Proxy connection closed");
			}
		};
		return true;
	}

	function closeLink(link) {
		if (link["ws"]) {
			link["ws"].onopen = link["ws"].onmessage =
				link["ws"].onerror = link["ws"].onclose = null;
			link["ws"].close();
		}
		link["ws"] = null;
		link["state"] = "closed";
		link["queue"] = [];
	}

	var api = {
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
		"_createSocket": function(handle, port) {
			links.set(handle, {"handle": handle, "port": port, "state": "idle",
				"ws": null, "queue": []});
		},
		"_destroySocket": function(handle) {
			var link = links.get(handle);
			if (link)
				closeLink(link);
			links.delete(handle);
		},
		"_registerHostname": function(address, hostname) {
			if (!address || !hostname || address === hostname)
				return;
			hostnames.set(address, hostname);
			links.forEach(function(link) {
				if (link["state"] === "ready")
					link["ws"].send("RESOLVE " + address + " " + hostname);
			});
		},
		"_send": function(handle, pointer, length, address, port) {
			var link = links.get(handle);
			if (!link) {
				link = {"handle": handle, "port": 0, "state": "idle",
					"ws": null, "queue": []};
				links.set(handle, link);
			}
			if (!configuredUrl)
				return false;
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
			var input = document.getElementById("luanti-proxy-url");
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
