// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 The Luanti Contributors

// Browser autoplay unlock for the engine's OpenAL contexts.
// This file is included with --pre-js.
//
// Emscripten's OpenAL is a JavaScript implementation over Web Audio. Under
// PROXY_TO_PTHREAD the engine calls alcOpenDevice/alcCreateContext from the
// application worker, but those entry points are proxied to the browser main
// thread, so every AudioContext lives here in AL.contexts[id].audioCtx. A
// context created without a user gesture starts "suspended" and stays silent
// until resume() is called from inside one.
//
// Emscripten's own autoResumeAudioContext registers its listeners with
// {once: true}: if the first keydown/mousedown after the context exists is
// not one the browser counts as activation, that was the only try. And the
// launcher's form-submit click happens before the game creates its context.
// So: retry on every gesture until each context reports "running", and log
// the state on the way so a silent session can be told apart from a locked
// one.

(function() {
	"use strict";
	// The application workers run this pre-js too; they have no AudioContext
	// and no AL contexts of their own. AL itself is declared further down the
	// generated file, so it is only looked up once the page is running.
	if (typeof document === "undefined")
		return;

	var seen = typeof WeakSet === "function" ? new WeakSet() : null;

	function contexts() {
		var out = [];
		if (typeof AL === "undefined" || !AL || !AL.contexts)
			return out;
		for (var id in AL.contexts) {
			var ctx = AL.contexts[id];
			if (ctx && ctx.audioCtx)
				out.push({id: id, audioCtx: ctx.audioCtx});
		}
		return out;
	}

	function watch(entry) {
		if (!seen || seen.has(entry.audioCtx))
			return;
		seen.add(entry.audioCtx);
		console.info("[audio] OpenAL context " + entry.id + ": AudioContext " +
			entry.audioCtx.state + ", " + entry.audioCtx.sampleRate + " Hz");
		entry.audioCtx.addEventListener("statechange", function() {
			console.info("[audio] OpenAL context " + entry.id + ": AudioContext is now " +
				entry.audioCtx.state);
		});
	}

	// Called from gestures, and by launcher.js. Returns how many contexts were
	// still suspended, so the caller can tell nothing was there to unlock.
	function resumeAll(reason) {
		var list = contexts();
		var suspended = 0;
		for (var i = 0; i < list.length; i++) {
			var entry = list[i];
			watch(entry);
			if (entry.audioCtx.state !== "suspended")
				continue;
			suspended++;
			console.info("[audio] " + reason + ": resuming OpenAL context " + entry.id +
				" (state before: " + entry.audioCtx.state + ")");
			(function(e) {
				e.audioCtx.resume().then(function() {
					console.info("[audio] OpenAL context " + e.id + " after " + reason +
						": " + e.audioCtx.state);
				}, function(err) {
					console.warn("[audio] OpenAL context " + e.id + " did not resume: " + err);
				});
			})(entry);
		}
		return suspended;
	}

	Module["luantiResumeAudio"] = resumeAll;
	Module["luantiAudioState"] = function() {
		var list = contexts();
		if (!list.length)
			return "none";
		return list.map(function(e) { return e.audioCtx.state; }).join(",");
	};

	// Capture phase on the document, so a canvas that stops propagation (or
	// takes pointer lock) still counts. Never removed: they cost nothing once
	// every context is running.
	var gestures = ["pointerdown", "mousedown", "keydown", "touchend", "click"];
	for (var g = 0; g < gestures.length; g++) {
		(function(name) {
			document.addEventListener(name, function() {
				resumeAll(name);
			}, {capture: true, passive: true});
		})(gestures[g]);
	}

	// Report contexts as they appear, without waiting for a gesture.
	setInterval(function() {
		var list = contexts();
		for (var i = 0; i < list.length; i++)
			watch(list[i]);
	}, 1000);
})();
