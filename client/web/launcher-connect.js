// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 The Luanti Contributors

// @ts-check

// The "Join server" side of the launcher: the multiplayer proxy picker, its
// privacy notice, the public server directory, and the check that a join can
// work before the engine is started. It talks to `Module.luantiNetwork`
// (network.js) and nothing else. The link's status (refusals, retries) is
// reported to launcher.js by network.js itself once the engine is running.
//
// Loads after launcher.js; launcher-start.js calls `luantiShell.connect`.

(function() {
	"use strict";

	var shell = window.luantiShell;
	if (!shell)
		throw new Error("launcher-connect.js must load after launcher.js");
	var ui = shell.ui;
	var config = shell.config;
	var query = shell.query;

	/**
	 * @param {string} value
	 * @param {string} label
	 */
	function addProxyOption(value, label) {
		var option = document.createElement("option");
		option.value = value;
		option.textContent = label;
		ui.proxyRegion.appendChild(option);
	}

	/**
	 * The deployment's own end date for a hosted proxy. A date that does not
	 * parse counts as passed: a typo must not keep a proxy on offer forever.
	 * @param {{expires?: string}} proxy
	 * @returns {string} The date it ended, or "" while it is on offer.
	 */
	function expiredOn(proxy) {
		if (proxy.expires === undefined || proxy.expires === null || proxy.expires === "")
			return "";
		var end = Date.parse(String(proxy.expires));
		if (Number.isNaN(end))
			return String(proxy.expires);
		return Date.now() >= end ? new Date(end).toISOString().slice(0, 10) : "";
	}

	/** @returns {Array<{id: string, label: string, url: string, expires?: string}>} */
	function listedProxies() {
		return (config.proxies || []).filter(function(proxy) { return proxy && proxy.id && proxy.url; });
	}

	// Hosted regions still on offer, and the ones whose end date has passed.
	var hostedProxies = listedProxies().filter(function(proxy) { return !expiredOn(proxy); });
	var expiredProxies = listedProxies().filter(function(proxy) { return !!expiredOn(proxy); });

	/** @param {string} url */
	function isExpiredHostedUrl(url) {
		return !!url && expiredProxies.some(function(proxy) { return proxy.url === url; });
	}

	function configuredProxyUrl() {
		if (ui.proxyRegion.value === "custom")
			return ui.proxyUrl.value.trim();
		var selected = hostedProxies.find(function(proxy) {
			return String(proxy.id) === ui.proxyRegion.value;
		});
		return selected ? String(selected.url || "").trim() : "";
	}

	function initializeProxies() {
		addProxyOption("none", "Singleplayer only — no proxy");
		hostedProxies.forEach(function(proxy) {
			addProxyOption(String(proxy.id), String(proxy.label || proxy.id));
		});
		addProxyOption("custom", "Custom / self-hosted");

		// An expired region the page was last used with (the deployment's default
		// before it lapsed, or a URL remembered from an earlier visit) is not a
		// custom proxy the player chose. Only an explicit ?proxy= is.
		var remembered = Module["luantiProxyUrl"] || shell.safeStorageGet("luanti.proxyUrl");
		if (isExpiredHostedUrl(remembered)) {
			remembered = "";
			Module["luantiProxyUrl"] = "";
		}
		var initial = query.get("proxy") || remembered;
		var match = hostedProxies.find(function(proxy) { return proxy.url === initial; });
		if (match) {
			ui.proxyRegion.value = String(match.id);
		} else if (initial) {
			ui.proxyRegion.value = "custom";
			ui.proxyUrl.value = initial;
		} else {
			ui.proxyRegion.value = "none";
		}
		ui.customProxyRow.hidden = ui.proxyRegion.value !== "custom";
	}

	// The proxy sees every Luanti datagram in the clear (the protocol has no
	// encryption), so a proxy that is not on this machine is a third party.
	/** @param {string} value */
	function isLoopbackProxyUrl(value) {
		var host = new URL(value).hostname.replace(/^\[|\]$/g, "").toLowerCase();
		return host === "localhost" || host.endsWith(".localhost") || host === "::1" ||
			/^127(?:\.\d{1,3}){3}$/.test(host);
	}

	function updateProxyNotice() {
		var show = false;
		try {
			var url = configuredProxyUrl();
			show = !!url && !isLoopbackProxyUrl(url);
		} catch (_) {
			// A half-typed URL is not a proxy yet.
		}
		ui.proxyNotice.hidden = !show;
	}

	/** @param {string} url */
	function hostOf(url) {
		try {
			return new URL(url).host;
		} catch (_) {
			return url;
		}
	}

	/**
	 * Why a join cannot work with the current choices, or "". A deployment with
	 * no proxy (none configured, or its only region expired) can only run
	 * singleplayer; saying so beats a connect loop that can never succeed.
	 */
	function blocker() {
		var choice = ui.proxyRegion.value;
		if (choice === "custom") {
			var url = ui.proxyUrl.value.trim();
			if (!url)
				return "Enter your proxy's WebSocket URL (wss://…) under Connection & language to join a server.";
			try {
				var parsed = new URL(url);
				if (parsed.protocol !== "ws:" && parsed.protocol !== "wss:")
					return "A proxy URL starts with wss:// (or ws:// for a proxy on this machine).";
			} catch (_) {
				return "That is not a valid proxy URL. It should look like wss://proxy.example.org/.";
			}
			return "";
		}
		if (choice !== "none")
			return "";
		if (hostedProxies.length)
			return "Choose a multiplayer proxy region under Connection & language to join a server.";
		if (expiredProxies.length) {
			var first = expiredProxies[0];
			return "The multiplayer proxy for " + String(first.label || first.id) + " expired on " +
				expiredOn(first) + ", so this deployment cannot join servers right now. " +
				"You can still play singleplayer, or enter your own proxy under Connection & language.";
		}
		return "This deployment has no multiplayer proxy, so it can only run singleplayer. " +
			"To join a server, enter your own proxy under Connection & language (Custom / self-hosted).";
	}

	/** @param {string} [suffix] Appended to the summary, e.g. the probe's result. */
	function updateSummary(suffix) {
		var reason = blocker();
		if (reason) {
			ui.proxySummary.textContent = reason;
			ui.proxySummary.dataset.state = "blocked";
			return;
		}
		var url = configuredProxyUrl();
		var label = ui.proxyRegion.value === "custom" ? "Custom proxy" :
			String((hostedProxies.find(function(proxy) {
				return String(proxy.id) === ui.proxyRegion.value;
			}) || {}).label || ui.proxyRegion.value);
		ui.proxySummary.textContent = "Proxy: " + label + " · " + hostOf(url) + (suffix || "");
		ui.proxySummary.dataset.state = "ready";
	}

	// The server fields stay disabled, with the reason beside them, until a
	// proxy is chosen: a remote join cannot succeed without one.
	function applyAvailability() {
		var reason = blocker();
		ui.address.disabled = !!reason;
		ui.port.disabled = !!reason;
		ui.serverListButton.disabled = !!reason;
		if (reason)
			ui.serverList.hidden = true;
		updateSummary();
	}

	ui.proxyRegion.addEventListener("change", function() {
		ui.customProxyRow.hidden = ui.proxyRegion.value !== "custom";
		updateProxyNotice();
		applyAvailability();
	});
	ui.proxyUrl.addEventListener("input", function() {
		updateProxyNotice();
		applyAvailability();
	});

	/** @param {boolean} remote */
	function validateProxy(remote) {
		var url = configuredProxyUrl();
		if (remote && (blocker() || !url))
			throw new Error(blocker() || "Remote servers need a multiplayer WebSocket proxy. " +
				"Choose a hosted region or enter a self-hosted WSS URL.");
		if (!Module["luantiNetwork"])
			throw new Error("The multiplayer transport is not ready yet.");
		Module["luantiNetwork"]["setProxyUrl"](url);
		return url;
	}

	/**
	 * Dial the proxy once before starting the engine. A stale or refusing proxy
	 * then fails here, in the launcher, with the proxy's own reason and the
	 * player free to choose another, instead of leaving them in a game shell
	 * whose connect loop can never succeed. Resolves with null where the
	 * network bridge has no probe (an embedder's older build).
	 * @returns {Promise<LuantiNetworkProbeResult | null>}
	 */
	function preflight() {
		var network = Module["luantiNetwork"];
		if (!network || typeof network["probe"] !== "function")
			return Promise.resolve(null);
		network["markJoin"]();
		updateSummary(" · checking…");
		return network["probe"](configuredProxyUrl()).then(function(result) {
			if (!result["ok"]) {
				updateSummary(" · unavailable");
				throw new Error(result["message"] || "The multiplayer proxy could not be reached.");
			}
			updateSummary(result["rttMs"] === null ? " · reachable" : " · reachable (" + result["rttMs"] + " ms)");
			return result;
		});
	}

	/** @param {{list?: Array<Record<string, any>>} | null} payload */
	function renderServers(payload) {
		var servers = payload && Array.isArray(payload.list) ? payload.list : [];
		servers = servers.filter(function(server) {
			return server && server.address && Number(server.port) > 0;
		}).sort(function(a, b) {
			return Number(b.clients || 0) - Number(a.clients || 0);
		}).slice(0, 16);
		ui.serverList.replaceChildren();
		if (!servers.length)
			throw new Error("The public directory returned no compatible servers.");
		servers.forEach(function(server) {
			var button = document.createElement("button");
			button.type = "button";
			button.className = "server-entry";
			var title = document.createElement("strong");
			title.textContent = server.name || server.address;
			var count = document.createElement("small");
			count.textContent = String(server.clients || 0) + "/" + String(server.clients_max || "?") + (server.password ? " · password" : "");
			var address = document.createElement("span");
			address.className = "server-address";
			address.textContent = server.address + ":" + server.port;
			button.append(title, count, address);
			button.addEventListener("click", function() {
				ui.address.value = server.address;
				ui.port.value = server.port;
				ui.serverList.hidden = true;
				ui.address.focus();
			});
			ui.serverList.appendChild(button);
		});
		ui.serverList.hidden = false;
	}

	ui.serverListButton.addEventListener("click", async function() {
		ui.serverListButton.disabled = true;
		ui.serverListButton.textContent = "Loading server directory…";
		shell.showError("");
		try {
			var response = await fetch(config.serverListUrl || "https://servers.luanti.org/list.json", {mode: "cors"});
			if (!response.ok)
				throw new Error("Server directory request failed (HTTP " + response.status + ").");
			renderServers(await response.json());
			ui.serverListButton.textContent = "Refresh public servers";
		} catch (error) {
			shell.showError("Could not load the public server directory. Direct connect still works. " +
				String(error.message || error));
			ui.serverListButton.textContent = "Try public servers again";
		} finally {
			applyAvailability();
		}
	});

	shell.connect = {validateProxy: validateProxy, preflight: preflight, blocker: blocker};

	initializeProxies();
	updateProxyNotice();
	applyAvailability();
})();
