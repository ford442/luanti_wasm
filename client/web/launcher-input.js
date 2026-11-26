// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 The Luanti Contributors

// @ts-check

// Touch and input chrome of the launcher page: the pointer-lock resume panel,
// the user-gesture audio unlock (the engine's OpenAL contexts start
// suspended), the canvas backing-store size before the engine owns it, and
// the one-off pointer probe the engine reads before `callMain`. The engine
// itself handles the keys, mouse and touch events on the canvas.
//
// Loads after launcher.js; launcher-start.js uses `luantiShell.input`.

(function() {
	"use strict";

	var shell = window.luantiShell;
	if (!shell)
		throw new Error("launcher-input.js must load after launcher.js");
	var ui = shell.ui;
	var state = shell.state;
	var hadPointerLock = false;

	function syncCanvasBackingStore() {
		var canvas = Module.canvas;
		if (!canvas)
			return;
		// After the engine owns the WebGL context, only CIrrDeviceSDL may
		// change canvas.width/height. Direct assignment here would desync the
		// OFFSCREEN_FRAMEBUFFER backing store from the CSS box.
		if (state.started)
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
		// audio_unlock.js (a --pre-js) owns the OpenAL contexts and logs them.
		if (typeof Module !== "undefined" && typeof Module["luantiResumeAudio"] === "function") {
			try {
				Module["luantiResumeAudio"]("launcher");
			} catch (_) {}
		}
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

	// Tell the engine what kind of pointer the page has; read once from C++
	// (porting::emscripten_input_probe) to choose touch defaults.
	function probeInput() {
		var coarse = false;
		try {
			coarse = !!(window.matchMedia && window.matchMedia("(pointer: coarse)").matches);
		} catch (_) {}
		return {
			maxTouchPoints: Math.max(0, navigator.maxTouchPoints | 0),
			coarsePointer: coarse
		};
	}

	document.addEventListener("pointerlockchange", function() {
		if (document.pointerLockElement === Module.canvas) {
			hadPointerLock = true;
			ui.resume.hidden = true;
		} else if (hadPointerLock && state.started && state.activePhase === "playing") {
			ui.resume.hidden = false;
		}
	});

	window.addEventListener("resize", syncCanvasBackingStore);

	Module.canvas.addEventListener("click", function() {
		unlockAudio();
		if (state.started && state.activePhase === "playing" && document.pointerLockElement !== Module.canvas) {
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
		ui.mobileWarning.hidden = false;

	shell.input = {
		unlockAudio: unlockAudio,
		syncCanvasBackingStore: syncCanvasBackingStore,
		probe: probeInput
	};
})();
