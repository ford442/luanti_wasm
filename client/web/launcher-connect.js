// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 The Luanti Contributors

// @ts-check

// The "Join server" side of the launcher: the multiplayer proxy picker, its
// privacy notice, and the public server directory. It talks to
// `Module.luantiNetwork` (network.js) and nothing else. The link's status
// (refusals, retries) is reported to launcher.js by network.js itself.
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

	function configuredProxyUrl() {
		if (ui.proxyRegion.value === "custom")
			return ui.proxyUrl.value.trim();
		var selected = (config.proxies || []).find(function(proxy) {
			return String(proxy.id) === ui.proxyRegion.value;
		});
		return selected ? String(selected.url || "").trim() : "";
	}

	function initializeProxies() {
		addProxyOption("none", "Singleplayer only — no proxy");
		(config.proxies || []).forEach(function(proxy) {
			if (proxy && proxy.id && proxy.url)
				addProxyOption(String(proxy.id), String(proxy.label || proxy.id));
		});
		addProxyOption("custom", "Custom / self-hosted");

		var initial = query.get("proxy") || Module["luantiProxyUrl"] || shell.safeStorageGet("luanti.proxyUrl");
		var match = (config.proxies || []).find(function(proxy) { return proxy.url === initial; });
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

	ui.proxyRegion.addEventListener("change", function() {
		ui.customProxyRow.hidden = ui.proxyRegion.value !== "custom";
		updateProxyNotice();
	});
	ui.proxyUrl.addEventListener("input", updateProxyNotice);

	/** @param {boolean} remote */
	function validateProxy(remote) {
		var url = configuredProxyUrl();
		if (remote && !url)
			throw new Error("Remote servers need a multiplayer WebSocket proxy. Choose a hosted region or enter a self-hosted WSS URL.");
		if (!Module["luantiNetwork"])
			throw new Error("The multiplayer transport is not ready yet.");
		Module["luantiNetwork"]["setProxyUrl"](url);
		return url;
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
			ui.serverListButton.disabled = false;
		}
	});

	shell.connect = {validateProxy: validateProxy};

	initializeProxies();
	updateProxyNotice();
})();
