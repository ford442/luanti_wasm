// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 The Luanti Contributors

// @ts-check

// The launch form: fills it from the query string and local storage,
// validates it into a session, downloads the chosen game's asset package, and
// calls the engine's `main` once (`Module.callMain`). It is the last launcher
// script because it is the one that needs the others: the proxy
// (launcher-connect.js), the selected world (launcher-library.js), and the
// audio unlock, canvas size and pointer probe (launcher-input.js).

(function() {
	"use strict";

	var shell = window.luantiShell;
	if (!shell)
		throw new Error("launcher-start.js must load after launcher.js");
	var connect = shell.connect;
	var library = shell.library;
	var input = shell.input;
	if (!connect || !library || !input)
		throw new Error("launcher-start.js must load after launcher-connect.js, launcher-library.js and launcher-input.js");
	var ui = shell.ui;
	var state = shell.state;
	var query = shell.query;

	/**
	 * @param {string} name
	 * @param {string} fallback
	 */
	function valueFromQuery(name, fallback) {
		var value = query.get(name);
		return value === null ? fallback : value;
	}

	ui.address.value = valueFromQuery("address", "");
	ui.port.value = valueFromQuery("port", "30000");
	ui.name.value = valueFromQuery("name", shell.safeStorageGet("luanti.playerName"));
	ui.game.value = valueFromQuery("game", "luanti_web");
	ui.language.value = valueFromQuery("language", shell.safeStorageGet("luanti.language"));
	if (["60", "100", "160"].indexOf(query.get("view")) !== -1)
		ui.quality.value = query.get("view");
	else if (["60", "100", "160"].indexOf(shell.safeStorageGet("luanti.viewDistance")) !== -1)
		ui.quality.value = shell.safeStorageGet("luanti.viewDistance");

	/** @returns {LuantiSession} */
	function validatedSession() {
		var remote = state.activeMode === "remote";
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
			game: ui.game.value || "luanti_web",
			world: remote ? null : library.selectedWorld(),
			view: ui.quality.value,
			language: ui.language.value
		};
	}

	/** @param {LuantiSession} session */
	function argumentsForSession(session) {
		var args = ["--go", "--viewing-range", session.view];
		if (session.language)
			args.push("--language", session.language);
		if (session.mode === "remote")
			args.push("--address", session.address, "--port", String(session.port), "--name", session.name);
		else
			args.push("--gameid", session.game,
				"--world", "/home/web_user/.luanti/worlds/" + session.world);
		return args;
	}

	/** @param {any} error */
	function abortLaunch(error) {
		state.started = false;
		state.launchInFlight = false;
		ui.play.disabled = !(state.runtimeReady && state.coreReady);
		ui.launcher.hidden = false;
		ui.gameShell.hidden = true;
		shell.showError(String(error && error.message || error));
		// prepareWorld may have created the world before the launch failed.
		library.refresh();
	}

	/** @param {number} bytes */
	function megabytes(bytes) {
		return (bytes / 1048576).toFixed(1);
	}

	/**
	 * @param {string} label
	 * @param {number} loaded
	 * @param {number} total
	 */
	function reportDownload(label, loaded, total) {
		var percent = total > 0 ? loaded / total * 100 : null;
		shell.reportStatus("Downloading " + label + " (" + megabytes(loaded) + " / " + megabytes(total) + " MB)",
			percent, "assets");
	}

	/** @param {LuantiSession} session */
	function begin(session) {
		try {
			state.currentSession = session;
			shell.safeStorageSet("luanti.playerName", session.name);
			shell.safeStorageSet("luanti.language", session.language);
			shell.safeStorageSet("luanti.viewDistance", session.view);
			ui.play.disabled = true;
			ui.launcher.hidden = true;
			ui.gameShell.hidden = false;
			state.launchInFlight = true;
			state.backgroundStarted = false;
			var launchArgs = session.mode === "local" ? null : argumentsForSession(session);
			var label = ui.game.selectedOptions && ui.game.selectedOptions[0] ?
				ui.game.selectedOptions[0].textContent : session.game;
			// A local world needs its game's files in the filesystem; a
			// remote server brings its own content.
			var gameReady = session.mode === "local" ?
				library.prepareWorld(session).then(function() {
					launchArgs = argumentsForSession(session);
					shell.reportStatus("Downloading " + label + "…", 0, "assets");
					return Module["luantiPackages"]["loadGame"](session.game, function(loaded, total) {
						reportDownload(label, loaded, total);
					});
				}) :
				Promise.resolve();
			gameReady.then(function() {
				shell.reportStatus("Starting Luanti…", 4, "engine");
				requestAnimationFrame(function() {
					input.syncCanvasBackingStore();
					requestAnimationFrame(function() {
						input.syncCanvasBackingStore();
						try {
							if (typeof Module["callMain"] !== "function")
								throw new Error("The engine is still preparing. Try again in a moment.");
							state.started = true;
							Module["luantiInput"] = input.probe();
							Module["callMain"](launchArgs);
						} catch (error) {
							abortLaunch(error);
						}
					});
				});
			}, function(error) {
				if (error && error.name === "LuantiWorldError") {
					abortLaunch(error);
					return;
				}
				abortLaunch(new Error("Could not download " + label + " (" +
					String(error && error.message || error) +
					"). Check your connection and try again."));
			});
		} catch (error) {
			abortLaunch(error);
		}
	}

	ui.form.addEventListener("submit", function(event) {
		event.preventDefault();
		if (state.started || state.launchInFlight)
			return;
		input.unlockAudio();
		/** @type {LuantiSession} */
		var session;
		try {
			if (!state.runtimeReady || typeof Module["callMain"] !== "function")
				throw new Error("The engine is still preparing. Try again in a moment.");
			// With no proxy the server fields are disabled and empty, so the missing
			// proxy is the reason to give, not the missing address.
			var blocked = state.activeMode === "remote" ? connect.blocker() : "";
			if (blocked)
				throw new Error(blocked);
			session = validatedSession();
			connect.validateProxy(session.mode === "remote");
		} catch (error) {
			abortLaunch(error);
			return;
		}
		if (session.mode !== "remote") {
			begin(session);
			return;
		}
		// A remote join first checks that the proxy will take the page. The
		// launcher stays on screen meanwhile; a failure ends here with the
		// proxy's own reason (see launcher-connect.js, preflight).
		shell.showError("");
		state.launchInFlight = true;
		ui.play.disabled = true;
		ui.playLabel.textContent = "Checking proxy…";
		connect.preflight().then(function() {
			begin(session);
		}, function(/** @type {any} */ error) {
			ui.playLabel.textContent = "Join server";
			abortLaunch(error);
		});
	});
})();
