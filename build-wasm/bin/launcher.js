// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 The Luanti Contributors

(function() {
	"use strict";

	var config = window.LUANTI_WEB_CONFIG || {};
	var query = new URLSearchParams(location.search);
	var runtimeReady = false;
	var started = false;
	var activeMode = query.get("address") ? "remote" : "local";
	var activePhase = "assets";
	var currentSession = null;
	var hadPointerLock = false;
	var loadingShellDismissed = false;
	var logs = [];

	function element(id) {
		return document.getElementById(id);
	}

	var ui = {
		launcher: element("luanti-launcher"),
		gameShell: element("luanti-game-shell"),
		form: element("luanti-launch-form"),
		localTab: element("luanti-local-tab"),
		remoteTab: element("luanti-remote-tab"),
		localPanel: element("luanti-local-panel"),
		remotePanel: element("luanti-remote-panel"),
		address: element("luanti-address"),
		port: element("luanti-port"),
		name: element("luanti-player-name"),
		game: element("luanti-game"),
		quality: element("luanti-quality"),
		language: element("luanti-language"),
		proxyRegion: element("luanti-proxy-region"),
		customProxyRow: element("luanti-custom-proxy-row"),
		proxyUrl: element("luanti-proxy-url"),
		play: element("luanti-play-button"),
		playLabel: element("luanti-play-label"),
		error: element("luanti-launch-error"),
		serverListButton: element("luanti-server-list-button"),
		serverList: element("luanti-server-list"),
		loading: element("luanti-loading"),
		loadingPhase: element("luanti-loading-phase"),
		loadingStatus: element("luanti-loading-status"),
		loadingProgress: element("luanti-loading-progress"),
		share: element("luanti-share-button"),
		fullscreen: element("luanti-fullscreen-button"),
		consoleButton: element("luanti-console-button"),
		consolePanel: element("luanti-console"),
		consoleOutput: element("luanti-console-output"),
		resume: element("luanti-resume"),
		resumeButton: element("luanti-resume-button")
	};

	function safeStorageGet(key) {
		try {
			return localStorage.getItem(key) || "";
		} catch (_) {
			return "";
		}
	}

	function safeStorageSet(key, value) {
		try {
			localStorage.setItem(key, value);
		} catch (_) {
		}
	}

	function appendLog(kind, values) {
		var line = Array.prototype.map.call(values, String).join(" ");
		logs.push("[" + kind + "] " + line);
		if (logs.length > 300)
			logs.splice(0, logs.length - 300);
		ui.consoleOutput.textContent = logs.join("\n");
		ui.consoleOutput.scrollTop = ui.consoleOutput.scrollHeight;
	}

	Module["print"] = function() {
		appendLog("info", arguments);
		console.log.apply(console, arguments);
	};
	Module["printErr"] = function() {
		appendLog("error", arguments);
		console.error.apply(console, arguments);
	};

	function setProgress(percent) {
		var value = Number(percent);
		if (!Number.isFinite(value))
			return;
		ui.loadingProgress.style.width = Math.max(2, Math.min(100, value)) + "%";
	}

	function dismissLoadingShell() {
		if (!ui.loading || loadingShellDismissed)
			return;
		loadingShellDismissed = true;
		// Keep the node in the layout tree (OFFSCREEN_FRAMEBUFFER compositing)
		// but never cover the canvas again for this session.
		ui.loading.style.opacity = "0";
		ui.loading.style.pointerEvents = "none";
	}

	function showLoadingShell() {
		if (!ui.loading || loadingShellDismissed)
			return;
		ui.loading.hidden = false;
		ui.loading.style.opacity = "1";
		ui.loading.style.pointerEvents = "";
	}

	function reportStatus(message, percent, phase) {
		if (phase)
			activePhase = phase;
		var phaseLabels = {
			"assets": "Downloading assets",
			"storage": "Opening local storage",
			"engine": "Starting engine",
			"menu": "Main menu",
			"loading": "Loading world",
			"playing": "Entering world"
		};
		if (!loadingShellDismissed) {
			ui.loadingPhase.textContent = phaseLabels[activePhase] || activePhase;
			if (message)
				ui.loadingStatus.textContent = message;
			setProgress(percent);
		}
		if (started && (activePhase === "engine" || activePhase === "loading"))
			showLoadingShell();
		if (activePhase === "menu") {
			ui.loading.hidden = true;
			ui.share.hidden = true;
		}
		if (activePhase === "playing") {
			// Dismiss as soon as the engine enters the game loop. Waiting for
			// the first GL commit left a full-screen "World ready" panel that
			// flickered against the canvas whenever status/frame hooks raced.
			dismissLoadingShell();
			ui.share.hidden = false;
			ui.share.textContent = currentSession && currentSession.mode === "remote" ?
				"Copy invite link" : "Copy launcher link";
		}
	}

	Module["luantiLauncher"] = {
		"reportEngineStatus": reportStatus,
		"prepareCompositor": function(percent) {
			// Never re-show the shell. Progress only.
			if (!loadingShellDismissed)
				setProgress(percent);
		},
		"notifyFramePresented": function() {
			if (started && activePhase === "playing")
				dismissLoadingShell();
		},
		"getState": function() {
			return {
				"runtimeReady": runtimeReady,
				"started": started,
				"phase": activePhase,
				"mode": currentSession ? currentSession.mode : activeMode,
				"loadingDismissed": loadingShellDismissed
			};
		}
	};

	Module["setStatus"] = function(text) {
		text = String(text || "").trim();
		if (!text)
			return;
		var counts = /\((\d+(?:\.\d+)?)\s*\/\s*(\d+(?:\.\d+)?)\)/.exec(text);
		var percent = counts && Number(counts[2]) > 0 ? Number(counts[1]) / Number(counts[2]) * 100 : null;
		reportStatus(text, percent, activePhase === "storage" ? "storage" : "assets");
	};

	Module["onRuntimeInitialized"] = function() {
		runtimeReady = true;
		ui.play.disabled = false;
		ui.playLabel.textContent = activeMode === "remote" ? "Join server" : "Start world";
		reportStatus("Ready to launch", 100, "engine");
		if (query.get("autostart") === "1")
			ui.form.requestSubmit();
	};

	window.addEventListener("luanti:persistence", function(event) {
		var state = event.detail || {};
		if (!started && state.state === "loading")
			reportStatus("Loading saved worlds…", 80, "storage");
		if (state.fatal) {
			showError("Persistent storage could not start: " + (state.error || "unknown error"));
			ui.play.disabled = true;
		}
	});

	function showError(message) {
		ui.error.textContent = message;
		ui.error.hidden = !message;
	}

	function setMode(mode) {
		activeMode = mode;
		var remote = mode === "remote";
		ui.localTab.classList.toggle("is-active", !remote);
		ui.remoteTab.classList.toggle("is-active", remote);
		ui.localTab.setAttribute("aria-selected", String(!remote));
		ui.remoteTab.setAttribute("aria-selected", String(remote));
		ui.localPanel.hidden = remote;
		ui.remotePanel.hidden = !remote;
		ui.playLabel.textContent = runtimeReady ? (remote ? "Join server" : "Start world") : "Preparing engine…";
		showError("");
	}

	ui.localTab.addEventListener("click", function() { setMode("local"); });
	ui.remoteTab.addEventListener("click", function() { setMode("remote"); });

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

		var initial = query.get("proxy") || Module["luantiProxyUrl"] || safeStorageGet("luanti.proxyUrl");
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

	ui.proxyRegion.addEventListener("change", function() {
		ui.customProxyRow.hidden = ui.proxyRegion.value !== "custom";
	});

	function validateProxy(remote) {
		var url = configuredProxyUrl();
		if (remote && !url)
			throw new Error("Remote servers need a multiplayer WebSocket proxy. Choose a hosted region or enter a self-hosted WSS URL.");
		if (!Module["luantiNetwork"])
			throw new Error("The multiplayer transport is not ready yet.");
		Module["luantiNetwork"]["setProxyUrl"](url);
		return url;
	}

	function valueFromQuery(name, fallback) {
		var value = query.get(name);
		return value === null ? fallback : value;
	}

	ui.address.value = valueFromQuery("address", "");
	ui.port.value = valueFromQuery("port", "30000");
	ui.name.value = valueFromQuery("name", safeStorageGet("luanti.playerName"));
	ui.game.value = valueFromQuery("game", "devtest");
	ui.language.value = valueFromQuery("language", safeStorageGet("luanti.language"));
	if (["60", "100", "160"].indexOf(query.get("view")) !== -1)
		ui.quality.value = query.get("view");
	else if (["60", "100", "160"].indexOf(safeStorageGet("luanti.viewDistance")) !== -1)
		ui.quality.value = safeStorageGet("luanti.viewDistance");

	function validatedSession() {
		var remote = activeMode === "remote";
		var name = ui.name.value.trim();
		if (name && !/^[A-Za-z0-9_-]{1,19}$/.test(name))
			throw new Error("Player names may contain up to 19 letters, numbers, dashes, or underscores.");
		if (remote && !name)
			throw new Error("Choose a player name before joining a server.");

		var port = Number(ui.port.value);
		var address = ui.address.value.trim();
		if (remote && !/^[A-Za-z0-9.-]+$/.test(address))
			throw new Error("Enter a hostname or IPv4 address without a URL scheme or path.");
		if (remote && (!Number.isInteger(port) || port < 1 || port > 65535))
			throw new Error("The server port must be between 1 and 65535.");

		return {
			mode: remote ? "remote" : "local",
			address: address,
			port: port,
			name: name,
			game: ui.game.value || "devtest",
			view: ui.quality.value,
			language: ui.language.value
		};
	}

	function argumentsForSession(session) {
		var args = ["--go", "--viewing-range", session.view];
		if (session.language)
			args.push("--language", session.language);
		if (session.mode === "remote")
			args.push("--address", session.address, "--port", String(session.port), "--name", session.name);
		else
			args.push("--gameid", session.game);
		return args;
	}

	function syncCanvasBackingStore() {
		var canvas = Module.canvas;
		if (!canvas)
			return;
		// After the engine owns the WebGL context, only CIrrDeviceSDL may
		// change canvas.width/height. Direct assignment here would desync the
		// OFFSCREEN_FRAMEBUFFER backing store from the CSS box.
		if (started)
			return;
		var rect = canvas.getBoundingClientRect();
		var width = Math.max(1, Math.round(rect.width));
		var height = Math.max(1, Math.round(rect.height));
		if (canvas.width !== width || canvas.height !== height) {
			canvas.width = width;
			canvas.height = height;
		}
	}

	function unlockAudio() {
		try {
			if (typeof window.AudioContext !== "undefined" || typeof window.webkitAudioContext !== "undefined") {
				if (window.AL && window.AL.contexts) {
					for (var ctxId in window.AL.contexts) {
						var ctx = window.AL.contexts[ctxId];
						if (ctx && ctx.audioCtx && ctx.audioCtx.state === "suspended") {
							ctx.audioCtx.resume().catch(function() {});
						}
					}
				}
				if (typeof Module !== "undefined" && Module["SDL2"] && Module["SDL2"].audioContext && Module["SDL2"].audioContext.state === "suspended") {
					Module["SDL2"].audioContext.resume().catch(function() {});
				}
			}
		} catch (_) {}
	}

	ui.form.addEventListener("submit", function(event) {
		event.preventDefault();
		if (started)
			return;
		unlockAudio();
		try {
			if (!runtimeReady || typeof Module["callMain"] !== "function")
				throw new Error("The engine is still preparing. Try again in a moment.");
			var session = validatedSession();
			validateProxy(session.mode === "remote");
			currentSession = session;
			safeStorageSet("luanti.playerName", session.name);
			safeStorageSet("luanti.language", session.language);
			safeStorageSet("luanti.viewDistance", session.view);
			ui.play.disabled = true;
			ui.launcher.hidden = true;
			ui.gameShell.hidden = false;
			syncCanvasBackingStore();
			started = true;
			reportStatus("Starting Luanti…", 4, "engine");
			Module["callMain"](argumentsForSession(session));
		} catch (error) {
			started = false;
			ui.play.disabled = !runtimeReady;
			ui.launcher.hidden = false;
			ui.gameShell.hidden = true;
			showError(String(error.message || error));
		}
	});

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
		showError("");
		try {
			var response = await fetch(config.serverListUrl || "https://servers.luanti.org/list.json", {mode: "cors"});
			if (!response.ok)
				throw new Error("Server directory request failed (HTTP " + response.status + ").");
			renderServers(await response.json());
			ui.serverListButton.textContent = "Refresh public servers";
		} catch (error) {
			showError("Could not load the public server directory. Direct connect still works. " + String(error.message || error));
			ui.serverListButton.textContent = "Try public servers again";
		} finally {
			ui.serverListButton.disabled = false;
		}
	});

	ui.share.addEventListener("click", async function() {
		if (!currentSession)
			return;
		var url = new URL(location.href);
		url.search = "";
		url.searchParams.set("game", currentSession.game);
		url.searchParams.set("view", currentSession.view);
		if (currentSession.mode === "remote") {
			url.searchParams.set("address", currentSession.address);
			url.searchParams.set("port", currentSession.port);
		}
		try {
			await navigator.clipboard.writeText(url.href);
			ui.share.textContent = "Link copied";
			setTimeout(function() {
				ui.share.textContent = currentSession.mode === "remote" ? "Copy invite link" : "Copy launcher link";
			}, 1800);
		} catch (_) {
			window.prompt("Copy this link", url.href);
		}
	});

	ui.fullscreen.addEventListener("click", function() {
		if (document.fullscreenElement)
			document.exitFullscreen();
		else
			ui.gameShell.requestFullscreen().catch(function(error) { appendLog("error", [error]); });
	});

	ui.consoleButton.addEventListener("click", function() {
		ui.consolePanel.open = !ui.consolePanel.open;
		ui.consoleButton.setAttribute("aria-expanded", String(ui.consolePanel.open));
	});
	element("luanti-console-clear").addEventListener("click", function() {
		logs = [];
		ui.consoleOutput.textContent = "";
	});

	document.addEventListener("pointerlockchange", function() {
		if (document.pointerLockElement === Module.canvas) {
			hadPointerLock = true;
			ui.resume.hidden = true;
		} else if (hadPointerLock && started && activePhase === "playing") {
			ui.resume.hidden = false;
		}
	});

	window.addEventListener("resize", syncCanvasBackingStore);

	Module.canvas.addEventListener("click", function() {
		unlockAudio();
		if (started && activePhase === "playing" && document.pointerLockElement !== Module.canvas) {
			Module.canvas.requestPointerLock();
			Module.canvas.focus();
		}
	});

	ui.resumeButton.addEventListener("click", function() {
		unlockAudio();
		Module.canvas.requestPointerLock();
		Module.canvas.focus();
	});

	document.addEventListener("click", unlockAudio, {capture: true, passive: true});
	document.addEventListener("keydown", unlockAudio, {capture: true, passive: true});
	document.addEventListener("touchstart", unlockAudio, {capture: true, passive: true});

	if (window.matchMedia("(pointer: coarse)").matches)
		element("luanti-mobile-warning").hidden = false;

	initializeProxies();
	setMode(activeMode);

	if ("serviceWorker" in navigator && (location.protocol === "https:" || location.hostname === "localhost" || location.hostname === "127.0.0.1")) {
		window.addEventListener("load", function() {
			navigator.serviceWorker.register("service-worker.js", {scope: "./"}).then(function(registration) {
				// Pull a fresh worker so network-first engine assets can replace
				// an older cache-first registration from prior builds.
				if (registration && registration.update)
					registration.update();
			}).catch(function(error) {
				appendLog("service-worker", [error]);
			});
		});
	}
})();
