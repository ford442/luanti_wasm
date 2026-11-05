// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 The Luanti Contributors

// The `Module` surface shared between the browser scripts in client/web and
// the C++ engine (`MAIN_THREAD_EM_ASM` / `EM_JS` in src/porting_emscripten.cpp
// and src/network/socket.cpp). This file is documentation first: when you add
// or rename a member on either side, update it here so `npm run typecheck`
// keeps both sides honest.
//
// Property names are always accessed as quoted strings in the scripts so they
// survive Closure/JS minification; the declarations use plain identifiers.

/** Cumulative proxy-link counters exposed by `Module.luantiNetwork`. */
interface LuantiNetworkState {
	state: string;
	url: string | null;
	rttMs: number | null;
	sentPackets: number;
	receivedPackets: number;
	droppedPackets: number;
	error: string | null;
}

/**
 * WebSocket-proxy transport (client/web/network.js, a --pre-js file).
 * Methods starting with `_` are called from C++ (src/network/socket.cpp).
 */
interface LuantiNetwork {
	setProxyUrl(value: string): unknown;
	getState(): LuantiNetworkState;
	_createSocket(handle: number, port: number): unknown;
	_destroySocket(handle: number): unknown;
	_registerHostname(address: number, hostname: string): unknown;
	_send(handle: number, pointer: number, length: number, address: number, port: number): unknown;
	/** Exposed for the unit tests only. */
	_test: { encapsulate: Function; decodeFrame: Function };
}

/** IDBFS persistence service (client/web/persistence.js, a --pre-js file). */
interface LuantiPersistence {
	requestSync(options?: { reason?: string; urgent?: boolean }): Promise<unknown>;
	getState(): {
		state: string;
		reason: string | null;
		pending: boolean;
		fatal: boolean;
		error: string | null;
	};
	/** Called from C++ (emscripten_sync_filesystem) with the dirty generation. */
	_requestGeneration(options: { generation: number; reason: string; urgent: boolean }): void;
}

/** Launcher hooks the engine calls back into (client/web/launcher.js). */
interface LuantiLauncher {
	/** `percent` is -1 or null when unknown; `phase` is null when unset. */
	reportEngineStatus(message: string, percent: number | null, phase: string | null): void;
	prepareCompositor(percent: number): void;
	notifyFramePresented(): void;
	/** WebGL context-loss counters since page load. */
	getGLState(): { lost: number; restored: number };
	getState(): {
		runtimeReady: boolean;
		started: boolean;
		phase: string;
		mode: string;
		loadingDismissed: boolean;
	};
}

/** Showcase theater <video> overlay (Tier B, client/web/theater.js). */
interface LuantiTheater {
	/** Returns false when the overlay or clip is unavailable (not an error). */
	show(options: { clip: string; title: string; loop: boolean; muted: boolean }): boolean;
	hide(): void;
	isVisible(): boolean;
}

/** Video-to-texture decoder (Tier C, client/web/videotexture.js). */
interface LuantiVideoTexture {
	/** Returns false when decoding is unsupported (the game stays on Tier A/B). */
	start(options: {
		clip: string;
		width: number;
		height: number;
		fps: number;
		/** Heap addresses of the two RGBA frame buffers owned by C++. */
		bufferPtr0: number;
		bufferPtr1: number;
		bufferSize: number;
	}): boolean;
	stop(): void;
}

interface LuantiModule {
	// Emscripten-standard hooks and members.
	canvas: HTMLCanvasElement;
	preRun: Array<() => void>;
	noExitRuntime: boolean;
	print: (text: string) => void;
	printErr: (text: string) => void;
	setStatus: (text: string) => void;
	onRuntimeInitialized: () => void;
	callMain(args?: string[]): void;
	HEAPU8: Uint8Array;
	/** C export, called by videotexture.js when a decoded frame is ready. */
	_luanti_video_texture_frame?: (bufferIndex: number, width: number, height: number) => void;
	/** C export, called by the persistence service when a sync fails. */
	_luanti_persistence_sync_failed?: (generation: number) => void;

	// Luanti services; each is installed by the script named above it.
	luantiNetwork?: LuantiNetwork;
	luantiPersistence?: LuantiPersistence;
	luantiLauncher?: LuantiLauncher;
	luantiTheater?: LuantiTheater;
	luantiVideoTexture?: LuantiVideoTexture;
	/** audio_unlock.js: resume suspended OpenAL contexts; returns how many. */
	luantiResumeAudio?: (reason?: string) => number;
	/** audio_unlock.js: comma-separated AudioContext states, or "none". */
	luantiAudioState?: () => string;
	/** Set from `?webgl=1|2`; read by CIrrDeviceSDL.cpp to force a WebGL version. */
	luantiWebGL?: { major: 1 | 2 };
	/** Written by CIrrDeviceSDL.cpp: the attributes of the context actually created. */
	luantiWebGLInfo?: {
		version: number;
		attempt: number;
		explicitSwap: boolean;
		alpha: boolean;
		depth: boolean;
		stencil: boolean;
		antialias: boolean;
		powerPreference: number;
	};
	/** Optional `?proxy=` override read by network.js before the launcher runs. */
	luantiProxyUrl?: string;
	/** Test hook: tweaks persistence timing (util/wasm/test_persistence_browser.py). */
	luantiPersistenceTestOptions?: Record<string, unknown>;

	[key: string]: any;
}

interface LuantiWebConfig {
	serverListUrl: string;
	defaultProxy: string;
	proxies: Array<{ id: string; label: string; url: string }>;
}

declare var Module: LuantiModule;
declare var FS: any;
declare var IDBFS: any;
declare var AL: any;
declare var HEAPU8: Uint8Array;
declare function _malloc(size: number): number;
declare function _free(pointer: number): void;
declare function addRunDependency(id: string): void;
declare function removeRunDependency(id: string): void;

interface Window {
	Module: LuantiModule;
	LUANTI_WEB_CONFIG?: LuantiWebConfig;
	AL?: any;
	webkitAudioContext?: typeof AudioContext;
}
