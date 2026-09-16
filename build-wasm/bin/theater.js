// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 The Luanti Contributors

// Theater Tier B: the browser video overlay.
//
// Luanti cannot bind an MP4 to a node tile, and teaching IrrlichtMt to demux
// one would be a large detour. The web client does not have to: the page owns
// a real HTML <video>, so the engine asks for a clip by name and this file
// raises the element over the canvas.
//
// Contract with the engine (src/porting_emscripten.cpp):
//
//   Module.luantiTheater.show({clip, title, loop, muted}) -> boolean
//   Module.luantiTheater.hide()
//
// show() returns false when it cannot play — no overlay in this shell, no such
// clip, a decoder the browser refuses. A false return is a normal outcome, not
// an error: the theater falls back to its animated-tile screen, which needs no
// JavaScript at all.
//
// Clips live in media/ next to luanti.html and are fetched at runtime. They are
// deliberately NOT baked into luanti.data — see client/web/media/README.md and
// the content budget in wasm_porting.md.

(function () {
	"use strict";

	var MEDIA_DIR = "media/";
	// Anything the engine sends has already been checked there, but this file
	// is also reachable from the page, so re-check rather than trust.
	var SAFE_CLIP = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;

	var state = {
		root: null,
		video: null,
		caption: null,
		sound: null,
		message: null,
		visible: false,
		relockOnHide: false
	};

	function byId(id) {
		return document.getElementById(id);
	}

	function build() {
		if (state.root)
			return state.root;
		var shell = byId("luanti-game-shell");
		if (!shell)
			return null;

		var root = document.createElement("div");
		root.id = "luanti-theater";
		root.className = "theater-overlay";
		root.hidden = true;

		var stage = document.createElement("div");
		stage.className = "theater-stage";

		var video = document.createElement("video");
		video.id = "luanti-theater-video";
		video.playsInline = true;
		video.setAttribute("playsinline", "");
		video.preload = "none";
		video.controls = false;
		stage.appendChild(video);

		var message = document.createElement("p");
		message.className = "theater-message";
		message.hidden = true;
		stage.appendChild(message);

		var bar = document.createElement("div");
		bar.className = "theater-bar";

		var caption = document.createElement("span");
		caption.className = "theater-caption";
		bar.appendChild(caption);

		var sound = document.createElement("button");
		sound.type = "button";
		sound.textContent = "Unmute";
		bar.appendChild(sound);

		var close = document.createElement("button");
		close.type = "button";
		close.textContent = "Close";
		bar.appendChild(close);

		root.appendChild(stage);
		root.appendChild(bar);
		shell.appendChild(root);

		sound.addEventListener("click", function () {
			video.muted = !video.muted;
			sound.textContent = video.muted ? "Unmute" : "Mute";
			if (!video.muted)
				play();
		});
		close.addEventListener("click", function () {
			hide();
		});
		// Escape is the same "put me back in the game" gesture the engine uses.
		root.addEventListener("keydown", function (event) {
			if (event.key === "Escape") {
				event.preventDefault();
				hide();
			}
		});
		video.addEventListener("error", function () {
			showMessage("That clip could not be played in this browser. " +
				"The in-world screen is still running.");
		});

		state.root = root;
		state.video = video;
		state.caption = caption;
		state.sound = sound;
		state.message = message;
		return root;
	}

	function showMessage(text) {
		if (!state.message)
			return;
		state.message.textContent = text;
		state.message.hidden = false;
		if (state.video)
			state.video.hidden = true;
	}

	function play() {
		var promise = state.video.play();
		if (promise && typeof promise.catch === "function") {
			promise.catch(function () {
				// Autoplay policy, or a decode failure. Either way the visitor
				// still has the animated screen behind the overlay.
				showMessage("Press Unmute to start the clip.");
			});
		}
	}

	function show(options) {
		options = options || {};
		var clip = String(options.clip || "");
		if (!SAFE_CLIP.test(clip) || clip.indexOf("..") !== -1)
			return false;
		if (!build())
			return false;

		state.message.hidden = true;
		state.video.hidden = false;
		state.video.loop = options.loop !== false;
		// Start muted whatever the caller asked for: a browser will refuse to
		// autoplay audible media without a user gesture, and refusing is worse
		// than starting silent with an Unmute button.
		state.video.muted = true;
		state.sound.textContent = "Unmute";
		state.caption.textContent = options.title || "Now playing";

		var src = MEDIA_DIR + clip;
		if (state.video.getAttribute("src") !== src) {
			state.video.setAttribute("src", src);
			state.video.load();
		}

		state.root.hidden = false;
		state.visible = true;
		// The engine keeps pointer lock while the visitor plays. Release it so
		// the overlay's own controls are clickable, and remember to hand it
		// back on the way out.
		state.relockOnHide = document.pointerLockElement === Module.canvas;
		if (state.relockOnHide && document.exitPointerLock)
			document.exitPointerLock();
		state.root.tabIndex = -1;
		state.root.focus();
		play();
		return true;
	}

	function hide() {
		if (!state.root || !state.visible)
			return;
		state.visible = false;
		state.root.hidden = true;
		try {
			state.video.pause();
		} catch (error) {
			// A video that never loaded cannot be paused; nothing to undo.
		}
		if (state.relockOnHide && Module.canvas && Module.canvas.requestPointerLock)
			Module.canvas.requestPointerLock();
		state.relockOnHide = false;
		if (Module.canvas && Module.canvas.focus)
			Module.canvas.focus();
	}

	if (typeof Module === "undefined")
		window.Module = {};
	Module["luantiTheater"] = {
		"show": show,
		"hide": hide,
		"isVisible": function () {
			return state.visible;
		}
	};
})();
