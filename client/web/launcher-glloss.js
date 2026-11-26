// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 The Luanti Contributors

// @ts-check

// The WebGL context-loss overlay. When the browser takes the GPU away the
// engine pauses presenting (CIrrDeviceSDL.cpp) and tries to rebuild its GL
// resources; this file shows the player what is going on ("Saving…",
// "Restoring graphics…", "Reload and resume"), flushes the world to IndexedDB
// first, and keeps the pointer unlocked so the reload button can be pressed.
//
// The engine reaches it through `Module.luantiLauncher`, which launcher.js
// creates and this file adds the context-loss members to. In proxy render
// mode the canvas's own `webglcontextlost` event fires on this thread; in
// offscreen mode the context lives on the engine's worker, so the engine
// reports the loss instead. Both end in the same handlers.
//
// Loads after launcher.js and launcher-input.js (their pointer-lock listeners
// run first).

(function() {
	"use strict";

	var shell = window.luantiShell;
	if (!shell)
		throw new Error("launcher-glloss.js must load after launcher.js");
	var ui = shell.ui;
	var state = shell.state;
	var launcher = Module["luantiLauncher"];

	var glLostCount = 0;
	var glRestoredCount = 0;
	var glRecoveredCount = 0;
	var glRestoreFailedCount = 0;
	var glLostDefaultText = ui.glLostText.textContent;
	var glLostSaved = false;
	var glOverlayActive = false;

	// The engine keeps asking for pointer lock while the game runs; with the
	// overlay up a locked pointer would route every click to the canvas and
	// the reload button could never be pressed.
	var nativeRequestPointerLock = Module.canvas.requestPointerLock;
	Module.canvas.requestPointerLock = function() {
		if (glOverlayActive)
			return undefined;
		return nativeRequestPointerLock.apply(this, arguments);
	};
	document.addEventListener("pointerlockchange", function() {
		if (glOverlayActive && document.pointerLockElement)
			document.exitPointerLock();
	});

	/** @param {string} label */
	function enableGlReload(label) {
		ui.glLostReload.disabled = false;
		ui.glLostReload.textContent = label;
	}

	/** @param {string} text */
	function showGlRestoreText(text) {
		if (state.started && !ui.glLost.hidden)
			ui.glLostText.textContent = text;
	}

	function handleContextLost() {
		glLostCount++;
		shell.appendLog("error", ["Luanti: WebGL context lost"]);
		if (!state.started)
			return;
		glLostSaved = false;
		ui.glLostText.textContent = glLostDefaultText;
		ui.glLost.hidden = false;
		ui.glLostReload.disabled = true;
		ui.glLostReload.textContent = "Saving…";
		glOverlayActive = true;
		if (document.pointerLockElement === Module.canvas)
			document.exitPointerLock();
		var persistence = Module["luantiPersistence"];
		var saved = persistence && persistence.requestSync ?
			persistence.requestSync({"reason": "webglcontextlost", "urgent": true}) :
			Promise.resolve();
		saved.then(function() {
			glLostSaved = true;
			enableGlReload("Reload and resume");
		}, function() {
			enableGlReload("Reload anyway");
		});
	}

	// The first frame after a successful restore has been presented.
	function handleContextRecovered() {
		glRecoveredCount++;
		shell.appendLog("info", ["Luanti: graphics restored"]);
		ui.glLost.hidden = true;
		ui.glLostText.textContent = glLostDefaultText;
		glOverlayActive = false;
	}

	Module.canvas.addEventListener("webglcontextlost", function(event) {
		// preventDefault lets the browser restore the context later.
		event.preventDefault();
		handleContextLost();
	});
	Module.canvas.addEventListener("webglcontextrestored", function() {
		glRestoredCount++;
		shell.appendLog("info", ["Luanti: WebGL context restored"]);
		// The engine rebuilds its GL resources next and reports back through
		// notifyContextRestored / notifyContextRestoreFailed.
		if (Module["luantiWebGL"] && Module["luantiWebGL"]["restore"] === "off")
			showGlRestoreText("Graphics are back, but the game has to reload its textures. " +
				(glLostSaved ? "Your world has been saved." : "Saving your world…"));
		else
			showGlRestoreText("Restoring graphics…");
	});
	ui.glLostReload.addEventListener("click", function() {
		location.reload();
	});

	launcher["getGLState"] = function() {
		return {
			"lost": glLostCount,
			"restored": glRestoredCount,
			"recovered": glRecoveredCount,
			"restoreFailed": glRestoreFailedCount,
			"overlay": !ui.glLost.hidden
		};
	};
	// Offscreen render mode: the engine's context lives on its worker, so the
	// DOM event above never fires and the engine reports the loss.
	// CIrrDeviceSDL::restoreAfterContextLoss() reports its progress.
	launcher["notifyContextRestoring"] = function() {
		showGlRestoreText("Restoring graphics…");
	};
	launcher["notifyContextRestored"] = function() {
		handleContextRecovered();
	};
	launcher["notifyContextRestoreFailed"] = function() {
		glRestoreFailedCount++;
		shell.appendLog("error", ["Luanti: graphics could not be restored"]);
		showGlRestoreText("Graphics could not be restored, so the game has to reload. " +
			(glLostSaved ? "Your world has been saved." : "Saving your world…"));
	};
	launcher["notifyContextLost"] = function() {
		handleContextLost();
	};
	// Tests: lose the engine's context in whichever thread owns it.
	launcher["debugLoseContext"] = function() {
		var info = Module["luantiWebGLInfo"];
		if (info && info["render"] === "offscreen") {
			Module["_luanti_debug_lose_webgl_context"]();
			return true;
		}
		var gl = Module.canvas.getContext("webgl2") || Module.canvas.getContext("webgl");
		var ext = gl && gl.getExtension("WEBGL_lose_context");
		if (!ext)
			return false;
		ext.loseContext();
		window["luantiLoseContextExt"] = ext;
		return true;
	};
})();
