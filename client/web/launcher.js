// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 The Luanti Contributors

// @ts-check

// Launcher shell and status: the first of the launcher scripts, and the only
// one that talks to the engine about its own lifecycle. It owns
//
//   - the shared state and element lookups every other launcher script uses
//     (published as `window.luantiShell`, typed in launcher-shell.d.ts),
//   - the loading panel, status line, runtime log and error line,
//   - `Module.luantiLauncher`, the object C++ and embedders call,
//   - the Local / Join server tabs and the in-game toolbar.
//
// The rest of the launcher is split by what it talks to and loads after this
// file, in the order shell.html lists them:
//
//   launcher-connect.js   Module.luantiNetwork: proxy picker, public server list
//   launcher-library.js   Module.luantiWorlds: the world list, dialogs, thumbnails
//   launcher-input.js     pointer lock, audio unlock, canvas size, touch probe
//   launcher-glloss.js    WebGL context-loss overlay
//   launcher-update.js    service worker and "new version" toast
//   launcher-start.js     the launch form (needs all of the above)
//
// These are classic scripts, not modules: the engine's --pre-js files share
// their page, and a module graph would not keep that order.

(function() {
	"use strict";

	var config = window.LUANTI_WEB_CONFIG || {};
	var query = new URLSearchParams(location.search);
	/** @type {LuantiLauncherState} */
	var state = {
		runtimeReady: false,
		coreReady: false,
		started: false,
		launchInFlight: false,
		backgroundStarted: false,
		// Embedder pause request (luantiLauncher.setPaused). Kept here so a
		// request made before the runtime exists is applied the moment it does.
		enginePaused: false,
		activeMode: query.get("address") ? "remote" : "local",
		activePhase: "assets",
		currentSession: null,
		loadingShellDismissed: false,
		startupFailure: null
	};
	/** @type {string[]} */
	var logs = [];
	// What network.js last said about the proxy link. `message` outlives the
	// "connecting" state of a retry, so a refusal does not flicker away every
	// time the transport redials, and clears only when the link is ready again
	// or the proxy choice changes.
	/** @type {{state: string, url: string | null, message: string, reason: string | null, closeCode: number | null}} */
	var proxyStatus = {state: "disabled", url: null, message: "", reason: null, closeCode: null};

	/** @type {Record<LuantiLauncherEvent, Array<() => void>>} */
	var listeners = {"playing": [], "framepresented": []};

	/**
	 * The launcher markup is fixed (client/web/shell.html) and typed in
	 * launcher-shell.d.ts, so this lookup is the one place an element is
	 * trusted to exist and to have the type its id promises.
	 * @param {string} id
	 * @returns {any}
	 */
	function element(id) {
		return document.getElementById(id);
	}

	/** @type {LuantiLauncherUi} */
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
		proxyNotice: element("luanti-proxy-notice"),
		proxyAlert: element("luanti-proxy-alert"),
		proxyAlertText: element("luanti-proxy-alert-text"),
		proxyAlertReload: element("luanti-proxy-alert-reload"),
		play: element("luanti-play-button"),
		playLabel: element("luanti-play-label"),
		error: element("luanti-launch-error"),
		serverListButton: element("luanti-server-list-button"),
		serverList: element("luanti-server-list"),
		mobileWarning: element("luanti-mobile-warning"),
		loading: element("luanti-loading"),
		loadingPhase: element("luanti-loading-phase"),
		loadingStatus: element("luanti-loading-status"),
		loadingProgress: element("luanti-loading-progress"),
		share: element("luanti-share-button"),
		fullscreen: element("luanti-fullscreen-button"),
		consoleButton: element("luanti-console-button"),
		consolePanel: element("luanti-console"),
		consoleOutput: element("luanti-console-output"),
		consoleClear: element("luanti-console-clear"),
		resume: element("luanti-resume"),
		resumeButton: element("luanti-resume-button"),
		glLost: element("luanti-gl-lost"),
		glLostText: element("luanti-gl-lost-text"),
		glLostReload: element("luanti-gl-lost-reload"),
		update: element("luanti-update"),
		updateReload: element("luanti-update-reload"),
		worldList: element("luanti-world-list"),
		newWorld: element("luanti-new-world"),
		importWorld: element("luanti-import-world"),
		importFile: element("luanti-import-file"),
		libraryStatus: element("luanti-library-status"),
		storageNote: element("luanti-storage-note"),
		dialog: element("luanti-dialog"),
		dialogForm: element("luanti-dialog-form"),
		dialogTitle: element("luanti-dialog-title"),
		dialogBody: element("luanti-dialog-body"),
		dialogError: element("luanti-dialog-error"),
		dialogCancel: element("luanti-dialog-cancel"),
		dialogConfirm: element("luanti-dialog-confirm")
	};

	// Render overrides read by CIrrDeviceSDL.cpp, for tests and benchmarks:
	// ?render=proxy|offscreen|auto picks the thread that owns WebGL (default:
	// the build's WASM_RENDER_THREAD), ?webgl=1|2 forces a single WebGL
	// version, ?swapsleep=N sleeps N ms after each proxied frame,
	// ?glrestore=off keeps the reload-only response to a lost WebGL context and
	// ?glrestore=fail makes every restore fail (tests of the fallback).
	var webglOptions = Module["luantiWebGL"] || {};
	var renderMode = query.get("render");
	if (renderMode === "proxy" || renderMode === "offscreen" || renderMode === "auto")
		webglOptions["render"] = renderMode;
	var forcedWebGL = Number(query.get("webgl"));
	if (forcedWebGL === 1 || forcedWebGL === 2)
		webglOptions["major"] = forcedWebGL;
	var swapSleep = Number(query.get("swapsleep"));
	if (swapSleep > 0 && swapSleep <= 100)
		webglOptions["swapSleepMs"] = swapSleep;
	var glRestoreOption = query.get("glrestore");
	if (glRestoreOption === "0" || glRestoreOption === "off")
		webglOptions["restore"] = "off";
	else if (glRestoreOption === "fail")
		webglOptions["restore"] = "fail";
	Module["luantiWebGL"] = webglOptions;

	/** @param {string} key */
	function safeStorageGet(key) {
		try {
			return localStorage.getItem(key) || "";
		} catch (_) {
			return "";
		}
	}

	/**
	 * @param {string} key
	 * @param {string} value
	 */
	function safeStorageSet(key, value) {
		try {
			localStorage.setItem(key, value);
		} catch (_) {
		}
	}

	/**
	 * @param {string} kind
	 * @param {ArrayLike<unknown>} values
	 */
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

	/** @param {number | null | undefined} percent */
	function setProgress(percent) {
		var value = Number(percent);
		if (!Number.isFinite(value))
			return;
		ui.loadingProgress.style.width = Math.max(2, Math.min(100, value)) + "%";
	}

	function dismissLoadingShell() {
		if (!ui.loading || state.loadingShellDismissed)
			return;
		state.loadingShellDismissed = true;
		// Keep the node in the layout tree (OFFSCREEN_FRAMEBUFFER compositing)
		// but never cover the canvas again for this session.
		ui.loading.style.opacity = "0";
		ui.loading.style.pointerEvents = "none";
	}

	function showLoadingShell() {
		if (!ui.loading || state.loadingShellDismissed)
			return;
		ui.loading.hidden = false;
		ui.loading.style.opacity = "1";
		ui.loading.style.pointerEvents = "";
	}

	/** @param {string} message an empty message hides the line */
	function showError(message) {
		ui.error.textContent = message;
		ui.error.hidden = !message;
	}

	// A game's optional `background` packages stream in once the world is up,
	// so they never delay the first frame. (None today: the showcase songs are
	// runtime media, fetched when a mod asks; see runtime_media.js.)
	function startBackgroundContent() {
		if (state.backgroundStarted || !state.currentSession || state.currentSession.mode !== "local")
			return;
		state.backgroundStarted = true;
		Module["luantiPackages"]["loadBackground"](state.currentSession.game).catch(function(/** @type {any} */ error) {
			appendLog("packages", ["background content failed: " + String(error && error.message || error)]);
		});
	}

	/** @type {Record<string, string>} */
	var phaseLabels = {
		"assets": "Downloading assets",
		"storage": "Opening local storage",
		"engine": "Starting engine",
		"menu": "Main menu",
		"loading": "Loading world",
		"playing": "Entering world"
	};

	/**
	 * @param {string | null} message
	 * @param {number | null} [percent]
	 * @param {string | null} [phase]
	 */
	function reportStatus(message, percent, phase) {
		if (phase)
			state.activePhase = phase;
		if (!state.loadingShellDismissed) {
			ui.loadingPhase.textContent = phaseLabels[state.activePhase] || state.activePhase;
			if (message)
				ui.loadingStatus.textContent = message;
			setProgress(percent);
		}
		if (state.started && (state.activePhase === "engine" || state.activePhase === "loading"))
			showLoadingShell();
		if (state.activePhase === "menu") {
			ui.loading.hidden = true;
			ui.share.hidden = true;
		}
		if (state.activePhase === "playing") {
			startBackgroundContent();
			emit("playing");
			// Dismiss as soon as the engine enters the game loop. Waiting for
			// the first GL commit left a full-screen "World ready" panel that
			// flickered against the canvas whenever status/frame hooks raced.
			dismissLoadingShell();
			ui.share.hidden = false;
			ui.share.textContent = state.currentSession && state.currentSession.mode === "remote" ?
				"Copy invite link" : "Copy launcher link";
		}
	}

	/** @param {LuantiLauncherEvent} name */
	function emit(name) {
		listeners[name].forEach(function(handler) { handler(); });
	}

	// network.js calls this for every proxy-link state change. A refusal
	// arrives as a specific sentence ("... does not allow pages from ...") taken
	// from the close reason the proxy sent; see util/wasm/proxy/README.md.
	/** @param {LuantiNetworkState} detail */
	function reportProxyStatus(detail) {
		var linkState = String(detail && detail["state"] || "");
		proxyStatus.state = linkState;
		proxyStatus.url = detail && detail["url"] || null;
		if (linkState === "ready" || linkState === "idle" || linkState === "disabled") {
			proxyStatus.message = "";
			proxyStatus.reason = null;
			proxyStatus.closeCode = null;
		} else if ((linkState === "error" || linkState === "closed") && detail["error"]) {
			proxyStatus.message = String(detail["error"]);
			proxyStatus.reason = detail["reason"] || null;
			proxyStatus.closeCode = typeof detail["closeCode"] === "number" ? detail["closeCode"] : null;
			appendLog("proxy", [proxyStatus.message]);
		}
		// Only a join through the proxy has a game shell to show it in; the
		// launcher's own "Connection" section already shows network.js's text.
		var visible = state.started && !!proxyStatus.message && state.currentSession &&
			state.currentSession.mode === "remote";
		ui.proxyAlert.hidden = !visible;
		ui.proxyAlertText.textContent = visible ? proxyStatus.message : "";
	}

	ui.proxyAlertReload.addEventListener("click", function() {
		location.reload();
	});

	function applyPaused() {
		var setPaused = Module["_luanti_set_paused"];
		if (state.runtimeReady && typeof setPaused === "function")
			setPaused(state.enginePaused ? 1 : 0);
	}

	// The engine skips its audio stream stepping while paused; the page stops
	// the audio clock to match (audio_unlock.js), and restarts it on unpause.
	function applyAudioPause() {
		var fn = Module[state.enginePaused ? "luantiSuspendAudio" : "luantiUnpauseAudio"];
		if (typeof fn !== "function")
			return;
		try {
			fn(state.enginePaused ? "pause" : "unpause");
		} catch (_) {}
	}

	// The members that need the WebGL context-loss overlay (getGLState and the
	// notifyContext* calls) are added to this object by launcher-glloss.js.
	Module["luantiLauncher"] = {
		"reportProxyStatus": reportProxyStatus,
		"reportEngineStatus": reportStatus,
		"prepareCompositor": function(percent) {
			// Never re-show the shell. Progress only.
			if (!state.loadingShellDismissed)
				setProgress(percent);
		},
		"notifyFramePresented": function() {
			if (state.started && state.activePhase === "playing") {
				dismissLoadingShell();
				emit("framepresented");
			}
		},
		// Stand the engine's frame loop still (or resume it). The flag is an
		// atomic in the engine's shared memory, so this is safe at any point of
		// the page lifetime: before callMain it is remembered and applied once
		// the runtime exists, afterwards it takes effect on the next frame. The
		// world, input and presents wait; an integrated server thread does not.
		"setPaused": function(paused) {
			state.enginePaused = !!paused;
			applyPaused();
			applyAudioPause();
			return state.enginePaused;
		},
		"isPaused": function() {
			return state.enginePaused;
		},
		// Measured frame clock of the engine loop: frames counted so far and
		// the latest dtime in milliseconds (null until the runtime exists).
		"getFrameClock": function() {
			var count = Module["_luanti_frame_clock_count"];
			var last = Module["_luanti_frame_clock_last_dtime_ms"];
			if (!state.runtimeReady || typeof count !== "function" || typeof last !== "function")
				return null;
			return {"frames": count(), "lastDtimeMs": last(), "paused": state.enginePaused};
		},
		"getState": function() {
			return {
				"runtimeReady": state.runtimeReady,
				"started": state.started,
				"phase": state.activePhase,
				"mode": state.currentSession ? state.currentSession.mode : state.activeMode,
				"loadingDismissed": state.loadingShellDismissed,
				// Proxy render mode stops calling notifyFramePresented once the
				// shell is dismissed (irr/src/CIrrDeviceSDL.cpp); keep it coming
				// until the world thumbnail is taken.
				"frameHookWanted": shell.frameHookWanted(),
				"world": state.currentSession && state.currentSession.world || null,
				"coreReady": state.coreReady,
				"packages": Module["luantiPackages"] ? Module["luantiPackages"]["getStates"]() : {},
				"proxy": {
					"state": proxyStatus.state,
					"url": proxyStatus.url,
					"message": proxyStatus.message,
					"reason": proxyStatus.reason,
					"closeCode": proxyStatus.closeCode
				}
			};
		}
	};

	Module["setStatus"] = function(text) {
		text = String(text || "").trim();
		if (!text)
			return;
		var counts = /\((\d+(?:\.\d+)?)\s*\/\s*(\d+(?:\.\d+)?)\)/.exec(text);
		var percent = counts && Number(counts[2]) > 0 ? Number(counts[1]) / Number(counts[2]) * 100 : null;
		reportStatus(text, percent, state.activePhase === "storage" ? "storage" : "assets");
	};

	// The core package (builtin, fonts, textures, shaders) starts downloading
	// from packages.js as soon as the engine script is evaluated. Everything
	// else is fetched when a game is chosen.
	window.addEventListener("luanti:package", function(event) {
		/** @type {Partial<LuantiPackageEvent>} */
		var detail = event.detail || {};
		if (detail.name !== "core" || state.coreReady)
			return;
		if (detail.state === "loading" && detail.total > 0) {
			ui.playLabel.textContent = "Downloading engine data… " +
				Math.floor(detail.loaded / detail.total * 100) + "%";
		}
	});

	function enablePlayIfReady() {
		if (!state.runtimeReady || !state.coreReady)
			return;
		ui.play.disabled = false;
		ui.playLabel.textContent = state.activeMode === "remote" ? "Join server" : "Start world";
		reportStatus("Ready to launch", 100, "engine");
		// A shared world link always waits for the player to confirm it.
		if (query.get("autostart") === "1" && !query.get("world"))
			ui.form.requestSubmit();
	}

	Module["onRuntimeInitialized"] = function() {
		state.runtimeReady = true;
		applyPaused();
		var packages = Module["luantiPackages"];
		if (!packages) {
			showError("This build is missing its asset loader (packages.js).");
			return;
		}
		packages["core"].then(function() {
			state.coreReady = true;
			enablePlayIfReady();
		}, function(/** @type {any} */ error) {
			ui.playLabel.textContent = "Engine data failed to load";
			showError("Could not download the engine data: " + String(error && error.message || error) +
				". Check your connection and reload the page.");
		});
	};

	// startup.js ends luanti.js before the engine exists when the browser
	// cannot run this build (no SIMD, no shared memory at any ceiling), so
	// onRuntimeInitialized never fires. Say why, in the panel the player is
	// already looking at.
	/** @param {{code?: string, message?: string} | null | undefined} failure */
	function showStartupError(failure) {
		state.startupFailure = failure || {};
		var message = String(state.startupFailure.message || "This browser cannot start the engine.");
		ui.playLabel.textContent = "Can't start on this browser";
		ui.play.disabled = true;
		if (ui.loading) {
			ui.loading.hidden = false;
			ui.loadingPhase.textContent = "Cannot start";
			ui.loadingStatus.textContent = message;
		}
		setProgress(0);
		showError(message);
		appendLog("error", [message]);
		// On a phone the launcher form is taller than the screen, and a phone
		// is the likeliest browser to land here: bring the reason into view.
		if (ui.error.scrollIntoView)
			ui.error.scrollIntoView({block: "center"});
	}

	window.addEventListener("luanti:startup-error", function(event) {
		showStartupError(event.detail);
	});
	if (Module["luantiStartup"] && Module["luantiStartup"]["fatal"])
		showStartupError(Module["luantiStartup"]["fatal"]);

	// The saved-worlds list and thumbnails react to the same event in
	// launcher-library.js; this is only the status line and the fatal case.
	window.addEventListener("luanti:persistence", function(event) {
		/** @type {Partial<LuantiPersistenceEvent>} */
		var detail = event.detail || {};
		if (!state.started && detail.state === "loading")
			reportStatus("Loading saved worlds…", 80, "storage");
		if (detail.fatal) {
			showError("Persistent storage could not start: " + (detail.error || "unknown error"));
			ui.play.disabled = true;
		}
	});

	/** @param {"local" | "remote"} mode */
	function setMode(mode) {
		state.activeMode = mode;
		var remote = mode === "remote";
		ui.localTab.classList.toggle("is-active", !remote);
		ui.remoteTab.classList.toggle("is-active", remote);
		ui.localTab.setAttribute("aria-selected", String(!remote));
		ui.remoteTab.setAttribute("aria-selected", String(remote));
		ui.localPanel.hidden = remote;
		ui.remotePanel.hidden = !remote;
		ui.playLabel.textContent = state.runtimeReady ? (remote ? "Join server" : "Start world") : "Preparing engine…";
		showError("");
		if (state.startupFailure)
			showStartupError(state.startupFailure);
	}

	ui.localTab.addEventListener("click", function() { setMode("local"); });
	ui.remoteTab.addEventListener("click", function() { setMode("remote"); });

	// --- the in-game toolbar

	ui.share.addEventListener("click", async function() {
		var session = state.currentSession;
		if (!session)
			return;
		var url = new URL(location.href);
		url.search = "";
		url.searchParams.set("game", session.game);
		url.searchParams.set("view", session.view);
		if (session.mode === "remote") {
			url.searchParams.set("address", session.address);
			url.searchParams.set("port", String(session.port));
		}
		try {
			await navigator.clipboard.writeText(url.href);
			ui.share.textContent = "Link copied";
			setTimeout(function() {
				ui.share.textContent = session.mode === "remote" ? "Copy invite link" : "Copy launcher link";
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
	ui.consoleClear.addEventListener("click", function() {
		logs = [];
		ui.consoleOutput.textContent = "";
	});

	/** @type {LuantiLauncherShell} */
	var shell = {
		config: config,
		query: query,
		ui: ui,
		state: state,
		appendLog: appendLog,
		showError: showError,
		reportStatus: reportStatus,
		safeStorageGet: safeStorageGet,
		safeStorageSet: safeStorageSet,
		on: function(name, handler) {
			listeners[name].push(handler);
		},
		frameHookWanted: function() {
			return false;
		}
	};
	window.luantiShell = shell;

	setMode(state.activeMode);
})();
