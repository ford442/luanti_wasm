// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 The Luanti Contributors

// WebGL2 compatibility shim for resizable WASM heaps.
// This file is included with --pre-js.
//
// With -sMAX_WEBGL_VERSION=2 Emscripten uses the "garbage-free" entry points,
// e.g. GLctx.uniform1iv(location, HEAP32, offset, count), which pass a view of
// the whole heap. With -sALLOW_MEMORY_GROWTH=1 and shared memory, browsers may
// back that view with a resizable/growable buffer, which WebGL2 rejects:
//   TypeError: The provided ArrayBuffer value must not be resizable
// WEBGL_USE_GARBAGE_FREE_APIS is an internal emcc setting and cannot be
// disabled from the command line, so copy the uniform data out of such heaps
// before it reaches WebGL.

(function() {
	"use strict";
	// WebGL calls run on the browser main thread under PROXY_TO_PTHREAD; the
	// application workers have no WebGL2RenderingContext.
	if (typeof WebGL2RenderingContext === "undefined")
		return;

	function isResizable(buffer) {
		return buffer && (buffer.resizable === true || buffer.growable === true);
	}

	// Index of the data argument and whether it is followed by srcOffset and
	// srcLength (always the case for the uniform*v family).
	function patch(name, dataIndex) {
		var proto = WebGL2RenderingContext.prototype;
		var original = proto[name];
		if (typeof original !== "function")
			return;
		proto[name] = function() {
			var data = arguments[dataIndex];
			if (!data || !ArrayBuffer.isView(data) || !isResizable(data.buffer))
				return original.apply(this, arguments);
			var offset = arguments[dataIndex + 1] || 0;
			var length = arguments[dataIndex + 2];
			var end = length ? offset + length : data.length;
			var args = Array.prototype.slice.call(arguments, 0, dataIndex);
			args.push(data.slice(offset, end));
			return original.apply(this, args);
		};
	}

	var vectorTypes = ["1f", "2f", "3f", "4f", "1i", "2i", "3i", "4i",
		"1ui", "2ui", "3ui", "4ui"];
	for (var i = 0; i < vectorTypes.length; i++)
		patch("uniform" + vectorTypes[i] + "v", 1);

	var matrixTypes = ["2fv", "3fv", "4fv", "2x3fv", "2x4fv", "3x2fv",
		"3x4fv", "4x2fv", "4x3fv"];
	for (var j = 0; j < matrixTypes.length; j++)
		patch("uniformMatrix" + matrixTypes[j], 2);

	// Everything else that takes array data. With the garbage-free APIs off
	// (MAXIMUM_MEMORY in src/CMakeLists.txt) Emscripten passes a subarray of
	// the heap with no offset arguments, but that view is still on the
	// growable shared buffer and WebGL rejects it just the same. Inputs are
	// copied; outputs (readPixels, getBufferSubData) are read into a copy and
	// written back.
	var outputs = {readPixels: true, getBufferSubData: true};
	function patchViews(name) {
		var proto = WebGL2RenderingContext.prototype;
		var original = proto[name];
		if (typeof original !== "function")
			return;
		proto[name] = function() {
			var copied = null;
			for (var k = 0; k < arguments.length; k++) {
				var arg = arguments[k];
				if (arg && ArrayBuffer.isView(arg) && isResizable(arg.buffer)) {
					copied = copied || Array.prototype.slice.call(arguments);
					copied[k] = arg.slice();
					if (outputs[name])
						copied.back = [k, arg];
				}
			}
			if (!copied)
				return original.apply(this, arguments);
			var result = original.apply(this, copied);
			if (copied.back)
				copied.back[1].set(copied[copied.back[0]]);
			return result;
		};
	}
	var viewTakers = ["bufferData", "bufferSubData", "texImage2D", "texSubImage2D",
		"texImage3D", "texSubImage3D", "compressedTexImage2D",
		"compressedTexSubImage2D", "compressedTexImage3D", "compressedTexSubImage3D",
		"readPixels", "getBufferSubData", "vertexAttrib1fv", "vertexAttrib2fv",
		"vertexAttrib3fv", "vertexAttrib4fv", "vertexAttribI4iv", "vertexAttribI4uiv",
		"clearBufferfv", "clearBufferiv", "clearBufferuiv", "drawBuffers"];
	for (var v = 0; v < viewTakers.length; v++)
		patchViews(viewTakers[v]);
})();
