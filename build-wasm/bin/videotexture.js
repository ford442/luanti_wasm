// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 The Luanti Contributors

// Theater Tier C spike: decode video frames in the browser and republish
// them onto an engine texture (GH issue #29). Unlike Tier B (theater.js),
// there is no HTML overlay here -- an offscreen <video> plus a small
// <canvas> feed RGBA pixels straight into the WebAssembly heap, and the
// engine uploads them onto whichever texture a mod named.
//
// Contract with the engine (src/porting_emscripten.cpp):
//
//   Module.luantiVideoTexture.start({
//     clip, width, height, fps, bufferPtr0, bufferPtr1, bufferSize
//   }) -> boolean
//   Module.luantiVideoTexture.stop()
//
// `bufferPtr0`/`bufferPtr1` are byte offsets into the shared WebAssembly
// heap for a double-buffered frame slot; a written frame is announced with
// Module._luanti_video_texture_frame(bufferIndex, width, height). This file
// never keeps a texture alive on its own -- if start() is refused (no
// decoder shell, browser rejects the codec) the caller's node/tile stays on
// whatever it was already showing.
//
// This is deliberately a feasibility spike, not a production video path:
// one quad, capped resolution/fps, no audio (see the Goals/Non-goals in
// issue #29). It is not wired into any showcase content by default.

(function () {
	"use strict";

	var MEDIA_DIR = "media/";
	// Re-checked here even though the engine already validated it -- this
	// file is reachable from the page too.
	var SAFE_CLIP = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;

	var state = {
		video: null,
		canvas: null,
		ctx: null,
		active: false,
		width: 0,
		height: 0,
		fps: 24,
		bufferPtr: [0, 0],
		bufferSize: 0,
		writeIndex: 0,
		frameIntervalMs: 1000 / 24,
		lastFrameTimeMs: 0,
		rafHandle: 0,
		usingVideoFrameCallback: false,
		vfcHandle: 0
	};

	function stop() {
		state.active = false;
		if (state.rafHandle) {
			cancelAnimationFrame(state.rafHandle);
			state.rafHandle = 0;
		}
		if (state.video) {
			if (state.vfcHandle &&
					typeof state.video.cancelVideoFrameCallback === "function") {
				state.video.cancelVideoFrameCallback(state.vfcHandle);
			}
			state.vfcHandle = 0;
			try {
				state.video.pause();
			} catch (error) {
				// A clip that never loaded cannot be paused; nothing to undo.
			}
			state.video.removeAttribute("src");
			state.video.load();
		}
	}

	// Copies one decoded frame into the WebAssembly heap at the currently
	// writable buffer slot and tells the engine it is ready. ECF_A8R8G8B8 is
	// BGRA in memory (irr/include/SColor.h), while canvas ImageData is RGBA,
	// so red and blue are swapped on the way in.
	function captureFrame() {
		if (!state.active || state.video.readyState < 2 /* HAVE_CURRENT_DATA */)
			return;

		state.ctx.drawImage(state.video, 0, 0, state.width, state.height);
		var src = state.ctx.getImageData(0, 0, state.width, state.height).data;

		var index = state.writeIndex;
		var dst = state.bufferPtr[index];
		var heap = Module.HEAPU8;
		var count = src.length;
		for (var i = 0; i < count; i += 4) {
			heap[dst + i]     = src[i + 2]; // B
			heap[dst + i + 1] = src[i + 1]; // G
			heap[dst + i + 2] = src[i];     // R
			heap[dst + i + 3] = src[i + 3]; // A
		}

		Module._luanti_video_texture_frame(index, state.width, state.height);
		state.writeIndex = index ^ 1;
	}

	function scheduleNext() {
		if (!state.active)
			return;

		if (state.usingVideoFrameCallback) {
			state.vfcHandle = state.video.requestVideoFrameCallback(function () {
				captureFrame();
				scheduleNext();
			});
			return;
		}

		// Fallback for browsers without requestVideoFrameCallback: poll on
		// rAF, throttled to the requested fps.
		state.rafHandle = requestAnimationFrame(function (nowMs) {
			if (nowMs - state.lastFrameTimeMs >= state.frameIntervalMs) {
				state.lastFrameTimeMs = nowMs;
				captureFrame();
			}
			scheduleNext();
		});
	}

	function start(options) {
		options = options || {};
		var clip = String(options.clip || "");
		if (!SAFE_CLIP.test(clip) || clip.indexOf("..") !== -1)
			return false;
		if (typeof Module === "undefined" || !Module.HEAPU8)
			return false;

		stop();

		state.width = options.width | 0;
		state.height = options.height | 0;
		state.fps = (options.fps | 0) || 24;
		state.bufferPtr = [options.bufferPtr0 | 0, options.bufferPtr1 | 0];
		state.bufferSize = options.bufferSize | 0;
		if (state.width <= 0 || state.height <= 0 || state.bufferSize <= 0)
			return false;
		if (state.width * state.height * 4 > state.bufferSize)
			return false;

		if (!state.video) {
			state.video = document.createElement("video");
			state.video.playsInline = true;
			state.video.setAttribute("playsinline", "");
			// No audio path in the spike (see issue #29 non-goals); muted
			// also sidesteps the autoplay-permission prompt entirely.
			state.video.muted = true;
			state.video.loop = true;
		}
		if (!state.canvas)
			state.canvas = document.createElement("canvas");
		state.canvas.width = state.width;
		state.canvas.height = state.height;
		state.ctx = state.canvas.getContext("2d", { willReadFrequently: true });
		if (!state.ctx)
			return false;

		state.usingVideoFrameCallback =
			typeof state.video.requestVideoFrameCallback === "function";
		state.frameIntervalMs = 1000 / state.fps;
		state.lastFrameTimeMs = 0;
		state.writeIndex = 0;
		state.active = true;

		state.video.src = MEDIA_DIR + clip;
		var promise = state.video.play();
		if (promise && typeof promise.catch === "function") {
			promise.catch(function () {
				// Autoplay refusal or a codec the browser refuses. Nothing
				// else drives this texture, so the node keeps its last frame
				// (typically its Tier A tile).
				state.active = false;
			});
		}
		scheduleNext();
		return true;
	}

	if (typeof Module === "undefined")
		window.Module = {};
	Module["luantiVideoTexture"] = {
		"start": start,
		"stop": stop
	};
})();
