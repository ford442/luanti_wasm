// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 The Luanti Contributors

// The `Module` surface shared between the browser scripts in client/web and
// the C++ engine (`MAIN_THREAD_EM_ASM` / `EM_JS` in src/porting_emscripten.cpp,
// src/network/socket.cpp, irr/src/CIrrDeviceSDL.cpp and a few more). This is
// the review surface for that boundary: a new `Module.luanti*` field is
// declared here in the same change as the C++ call and the JS implementation.
//
//   - `LuantiModule` has no index signature on purpose. A script that reads an
//     undeclared member fails `npm run typecheck`, and
//     util/wasm/check_module_contract.mjs (run by it) fails when C++ reads a
//     `Module` member that is not declared below.
//   - What the launcher scripts share among themselves is not part of this
//     contract; see launcher-shell.d.ts.
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
	/** Why the link failed or ended: a refusal or a plain "could not connect". */
	error: string | null;
	/**
	 * The tag the proxy closed the link with (origin, per_ip_limit,
	 * global_limit, target_denied, rate_limited, handshake_timeout, idle, ...),
	 * or null when it said nothing (unreachable, or a clean close).
	 */
	reason: string | null;
	/** WebSocket close code of the last close, e.g. 1006 for "never connected". */
	closeCode: number | null;
}

/**
 * What the TCP hop to the proxy cost during one join, in milliseconds after
 * the join began (the launcher's markJoin, else the first datagram sent).
 * Marks are null until the moment happens. See util/wasm/proxy/README.md,
 * "Measuring the TCP hop".
 */
interface LuantiNetworkTimings {
	/** Whether the join began at the launcher's markJoin (else at the first datagram). */
	joinMarked: boolean;
	/** How long the pre-join probe needed to reach PROXY OK (TLS included). */
	probeMs: number | null;
	proxyOpenMs: number | null;
	proxyReadyMs: number | null;
	firstSendMs: number | null;
	firstReceiveMs: number | null;
	/** The first TOSERVER_PLAYERPOS the engine sent: the player is in the world. */
	firstPlayerPosMs: number | null;
	receivedDatagrams: number;
	gapsOver100Ms: number;
	gapsOver250Ms: number;
	gapsOver1000Ms: number;
	longestGapMs: number;
	/** A pause of 250 ms or more that ended with three datagrams within 20 ms. */
	stalls: number;
	longestStallMs: number;
	/** PING/PONG round trips over the proxy link, sampled every five seconds. */
	rtt: { samples: number; minMs: number | null; maxMs: number | null; meanMs: number | null };
}

/** What `Module.luantiNetwork.probe` learned from dialling a proxy once. */
interface LuantiNetworkProbeResult {
	/** The proxy accepted this page's origin and protocol version 1. */
	ok: boolean;
	url: string;
	/** A sentence for the player; empty when `ok`. */
	message: string;
	/** The proxy's close tag (origin, global_limit, ...), "timeout" or "protocol", or null. */
	reason: string | null;
	closeCode: number | null;
	handshakeMs: number | null;
	rttMs: number | null;
}

/**
 * WebSocket-proxy transport (client/web/network.js, a --pre-js file).
 * Methods starting with `_` are called from C++ (src/network/socket.cpp).
 */
interface LuantiNetwork {
	setProxyUrl(value: string): unknown;
	getState(): LuantiNetworkState;
	/** Start the clock for a join; the launcher calls it when the player presses Join. */
	markJoin(): void;
	getTimings(): LuantiNetworkTimings;
	/**
	 * Dial the proxy once, send no datagram, and report whether a join can work:
	 * certificate, origin, protocol. The game server is checked later, by the
	 * proxy, on the first datagram.
	 */
	probe(value: string, timeoutMs?: number): Promise<LuantiNetworkProbeResult>;
	_createSocket(handle: number, port: number): unknown;
	_destroySocket(handle: number): unknown;
	/** `address` is the dotted-quad IPv4 string (socket.cpp passes UTF8ToString). */
	_registerHostname(address: string, hostname: string): unknown;
	/** `pointer`/`length` locate the datagram on the heap; `address` is a dotted-quad string. */
	_send(handle: number, pointer: number, length: number, address: string, port: number): unknown;
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
	/** World library (client/web/worlds.js); also Module.luantiWorlds. */
	library?: LuantiWorldLibrary;
}

interface LuantiWorld {
	name: string;
	path: string;
	game: string;
	creative: boolean;
	damage: boolean;
	size: number;
	files: number;
	created: number | null;
	lastPlayed: number | null;
	modified: number | null;
	hasThumbnail: boolean;
}

/** What importing an archive would do; nothing is written until importArchive. */
interface LuantiWorldArchivePlan {
	name: string;
	game: string;
	gameTitle: string;
	gameAvailable: boolean;
	engine: string | null;
	exported: string | null;
	content: Array<{ type: string; name: string; bundled?: boolean }>;
	archiveBytes: number;
	uncompressedBytes: number;
	files: number;
	warnings: string[];
}

/**
 * Errors are Error objects with name "LuantiWorldError" and a `code`:
 * name, exists, missing, game, invalid, unsafe-path, too-large, missing-game,
 * quota, unsupported, invalid-url, download, storage.
 */
interface LuantiWorldLibrary {
	ready(): Promise<void>;
	limits(): { archiveBytes: number; uncompressedBytes: number; entries: number; pathDepth: number; nameBytes: number };
	list(): Promise<LuantiWorld[]>;
	get(name: string): Promise<LuantiWorld>;
	games(): Promise<Array<{ id: string; title: string; source: "bundled" | "installed" }>>;
	validateName(name: string): string;
	suggestName(base: string): Promise<string>;
	pathFor(name: string): string;
	create(options: { name: string; game: string; seed?: string; creative?: boolean; damage?: boolean }): Promise<LuantiWorld>;
	rename(from: string, to: string): Promise<LuantiWorld>;
	duplicate(from: string, to?: string): Promise<LuantiWorld>;
	remove(name: string): Promise<unknown>;
	markPlayed(name: string): Promise<void>;
	thumbnail(name: string): Promise<Blob | null>;
	saveThumbnail(name: string, image: Blob): Promise<unknown>;
	/** Resolves to a Blob, or to null after writing to options.writable. */
	exportWorld(name: string, options?: {
		writable?: WritableStream | FileSystemWritableFileStream;
		onProgress?: (done: number, total: number) => void;
		store?: boolean;
	}): Promise<Blob | null>;
	inspectArchive(archive: Blob, options?: { fileName?: string }): Promise<LuantiWorldArchivePlan>;
	importArchive(archive: Blob, options?: {
		name?: string;
		fileName?: string;
		source?: string;
		onProgress?: (done: number, total: number) => void;
	}): Promise<LuantiWorld>;
	/** Downloads (HTTPS or same-origin only) and inspects; never imports. */
	fetchShared(url: string, options?: { signal?: AbortSignal; onProgress?: (done: number, total: number) => void }):
		Promise<{ blob: Blob; url: string; host: string; fileName: string; plan: LuantiWorldArchivePlan }>;
	storage(): Promise<{ usage: number | null; quota: number | null; persisted: boolean | null }>;
	requestPersistence(): Promise<boolean>;
	[key: string]: any;
}

/** One entry of asset-manifest.json (written by util/wasm/build_packages.py). */
interface LuantiAssetPackage {
	url: string;
	bytes: number;
	sha256: string;
	files: number;
	label: string;
	eager: boolean;
}

interface LuantiAssetManifest {
	schema: number;
	buildId: string;
	packages: Record<string, LuantiAssetPackage>;
	games: Record<string, { packages: string[]; background?: string[] }>;
	/** Runtime media sets by `<set>/<id>` (songs), fetched by runtime_media.js. */
	media?: Record<string, LuantiMediaSet>;
	shell: Record<string, { bytes: number; sha256: string; verify: boolean }>;
}

interface LuantiMediaSet {
	/** Virtual-filesystem directory the files are written to. */
	dest: string;
	bytes: number;
	files: { name: string; url: string; bytes: number; sha256: string }[];
}

type LuantiMediaState = "ready" | "loading" | "busy" | "missing" | "failed" | "invalid";

/** Runtime media (client/web/runtime_media.js, a --pre-js file). */
interface LuantiRuntimeMedia {
	/** Starts the download if none is running; otherwise answers without queueing. */
	request(id: string): LuantiMediaState;
	/** `"idle"` for an id nobody asked for. */
	state(id: string): LuantiMediaState | "idle";
	/** Delete a ready set's files from the virtual filesystem. */
	release(id: string): boolean;
	requestCode(id: string): number;
	releaseCode(id: string): number;
	status(): { inFlight: string | null; resident: string[]; sets: Record<string, string> };
}

/** Streamed asset packages (client/web/packages.js, a --pre-js file). */
interface LuantiPackages {
	manifest(): Promise<LuantiAssetManifest>;
	/** Download, verify and mount the named packages; progress is summed bytes. */
	load(names: string[], onProgress?: (loaded: number, total: number) => void): Promise<unknown>;
	loadCore(onProgress?: (loaded: number, total: number) => void): Promise<unknown>;
	loadGame(game: string, onProgress?: (loaded: number, total: number) => void): Promise<unknown>;
	/** The game's optional `background` packages, one at a time (none today). */
	loadBackground(game: string): Promise<unknown>;
	/** Resolves when the eager `core` packages are mounted. */
	core: Promise<unknown>;
	getStates(): Record<string, { state: string; loaded: number; total: number }>;
}

/**
 * Launcher hooks the engine calls back into. launcher.js creates the object;
 * the context-loss members are added by launcher-glloss.js.
 */
interface LuantiLauncher {
	/** Called by network.js on every proxy-link state change. */
	reportProxyStatus(detail: LuantiNetworkState): void;
	/** `percent` is -1 or null when unknown; `phase` is null when unset. */
	reportEngineStatus(message: string, percent: number | null, phase: string | null): void;
	prepareCompositor(percent: number): void;
	notifyFramePresented(): void;
	/**
	 * Stand the engine's frame loop still (true) or resume it (false). Safe at
	 * any time, including before `callMain`: a request made before the runtime
	 * exists is applied once it does. An integrated server thread keeps running.
	 * Returns the requested state.
	 */
	setPaused(paused: boolean): boolean;
	isPaused(): boolean;
	/** Measured frame clock of the engine loop; null until the runtime exists. */
	getFrameClock(): { frames: number; lastDtimeMs: number; paused: boolean } | null;
	/** launcher-glloss.js: WebGL context-loss counters since page load. */
	getGLState?(): { lost: number; restored: number; recovered: number; restoreFailed: number; overlay: boolean };
	/** launcher-glloss.js: called by the engine when its offscreen (worker-owned) context is lost. */
	notifyContextLost?(): void;
	notifyContextRestoring?(): void;
	notifyContextRestored?(): void;
	notifyContextRestoreFailed?(): void;
	/** launcher-glloss.js, test hook: lose the engine's context; false if the browser cannot. */
	debugLoseContext?(): boolean;
	getState(): {
		runtimeReady: boolean;
		started: boolean;
		phase: string;
		mode: string;
		loadingDismissed: boolean;
		/** Ask the engine to keep calling notifyFramePresented (thumbnail capture). */
		frameHookWanted: boolean;
		/** The singleplayer world being played, if any. */
		world: string | null;
		coreReady: boolean;
		packages: Record<string, { state: string; loaded: number; total: number }>;
		/**
		 * The proxy link as network.js last reported it. `message` is the
		 * player-facing sentence for a refusal or failure and stays until the
		 * link is ready again or the proxy choice changes.
		 */
		proxy: { state: string; url: string | null; message: string; reason: string | null; closeCode: number | null };
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
	/** The SDL2 audio state Emscripten keeps on Module (launcher-input.js resumes its context). */
	SDL2?: { audioContext?: AudioContext };

	// C exports (EMSCRIPTEN_KEEPALIVE in src/ and irr/src/), present once the
	// runtime exists. Called from the page; the engine never calls them itself.
	/** videotexture.js: a decoded frame is ready. */
	_luanti_video_texture_frame?: (bufferIndex: number, width: number, height: number) => void;
	/** persistence.js: a sync failed / completed for this engine-side generation. */
	_luanti_persistence_sync_failed?: (generation: number) => void;
	_luanti_persistence_sync_completed?: (generation: number) => void;
	/** launcher.js: the embedder pause flag (an atomic in shared memory). */
	_luanti_set_paused?: (paused: number) => void;
	_luanti_is_paused?: () => number;
	/** launcher.js: frames counted by the engine loop and its latest dtime, in ms. */
	_luanti_frame_clock_count?: () => number;
	_luanti_frame_clock_last_dtime_ms?: () => number;
	/** launcher-glloss.js, tests: lose the WebGL context owned by the engine worker. */
	_luanti_debug_lose_webgl_context?: () => void;
	/** network.js: deliver a datagram to the engine's UDP socket `handle`. */
	_luanti_websocket_proxy_receive?: (handle: number, pointer: number, length: number, address: number, port: number) => void;
	/** perf.js: address of the frame-statistics ring in shared memory. */
	_luanti_perf_ring?: () => number;
	/** startup.js: the allocator's sbrk break, in bytes. */
	_luanti_heap_break?: () => number;

	// Luanti services; each is installed by the script named above it.
	luantiNetwork?: LuantiNetwork;
	luantiPersistence?: LuantiPersistence;
	/** worlds.js: the same object as luantiPersistence.library. */
	luantiWorlds?: LuantiWorldLibrary;
	/** worlds.js: lower the import caps (tests, embedders). */
	luantiWorldLimits?: Partial<Record<"archiveBytes" | "uncompressedBytes" | "entries" | "pathDepth" | "nameBytes", number>>;
	_luanti_engine_version?: () => number;
	luantiLauncher?: LuantiLauncher;
	/** Pointer probe set by the launcher before callMain; read once by the engine. */
	luantiInput?: { maxTouchPoints: number; coarsePointer: boolean };
	luantiPackages?: LuantiPackages;
	/** Override for the asset manifest location (default: asset-manifest.json). */
	luantiAssetManifestUrl?: string;
	luantiTheater?: LuantiTheater;
	luantiVideoTexture?: LuantiVideoTexture;
	/** audio_unlock.js: resume suspended OpenAL contexts; returns how many. */
	luantiResumeAudio?: (reason?: string) => number;
	/** audio_unlock.js: comma-separated AudioContext states, or "none". */
	luantiAudioState?: () => string;
	/** audio_unlock.js: suspend every OpenAL context and hold it there (embedder pause). */
	luantiSuspendAudio?: (reason?: string) => number;
	/** audio_unlock.js: release the hold and resume every stopped context. */
	luantiUnpauseAudio?: (reason?: string) => number;
	/** runtime_media.js: fetch media sets on demand for mods (core.web_media_request). */
	luantiRuntimeMedia?: LuantiRuntimeMedia;
	/** Render overrides read by CIrrDeviceSDL.cpp (`?webgl=`, `?render=`, `?swapsleep=`, `?glrestore=`). */
	luantiWebGL?: {
		major?: 1 | 2;
		render?: "proxy" | "offscreen" | "auto";
		swapSleepMs?: number;
		/** Context-loss response: rebuild GL resources (default), reload only, or force a failed rebuild. */
		restore?: "off" | "fail";
	};
	/** Written by CIrrDeviceSDL.cpp: the attributes of the context actually created. */
	luantiWebGLInfo?: {
		version: number;
		/** Thread that owns the context: the browser main thread or the engine worker. */
		render: "proxy" | "offscreen";
		attempt: number;
		explicitSwap: boolean;
		alpha: boolean;
		depth: boolean;
		stencil: boolean;
		antialias: boolean;
		powerPreference: number;
	};
	/** Generated by CMake (build-info.js.in): the choices this build was configured with. */
	luantiBuild?: {
		type: string;
		simd: boolean;
		lto: boolean;
		/** "default" unless configured with -DWASM_MALLOC=. */
		malloc: string;
		/** Bytes: the -sINITIAL_MEMORY / -sMAXIMUM_MEMORY the binary was linked with. */
		initialMemory: number;
		maximumMemory: number;
	};
	/** The shared memory the engine runs in; startup.js creates it, or an embedder supplies it. */
	wasmMemory?: WebAssembly.Memory;
	/** startup.js: the checks that run before the engine allocates anything. */
	luantiStartup?: {
		build: LuantiModule["luantiBuild"] | null;
		simd: { required: boolean; supported: boolean | null };
		memory: {
			state: "skipped" | "provided" | "reserved" | "failed";
			initial?: number;
			buildMaximum?: number;
			/** Ceiling of the memory in use (0 when none could be reserved). */
			maximum?: number;
			/** True when the build's own maximum was refused and a smaller ceiling is in use. */
			reduced?: boolean;
			attempts?: Array<{ maximum: number; ok: boolean; ms: number; error?: string }>;
		};
		fatal: { code: string; message: string } | null;
		/** Committed heap size now, in bytes. */
		heapBytes(): number;
		/** The allocator's sbrk break in bytes (0 before the engine runs): how much heap is carved up. */
		heapBreakBytes(): number;
	};
	/** perf.js: frame statistics the engine records in shared memory. */
	luantiPerf?: {
		available(): boolean;
		cursor(): number;
		samples(since?: number): { first: number; next: number; frames: Array<Record<string, number>> };
		summary(opts?: { seconds?: number; since?: number }): Record<string, any>;
	};
	/** webgl_compat.js: copies made for resizable-heap views (this thread only). */
	luantiWebGLCompat?: { stats(): Record<string, number> };
	/** present.js: shows a frame posted by the engine worker (offscreen mode). */
	luantiPresentFrame?: (bitmap: ImageBitmap, ackPtr: number) => void;
	luantiPresentStats?: () => { shown: number; dropped: number };
	/** Optional `?proxy=` override read by network.js before the launcher runs. */
	luantiProxyUrl?: string;
	/** Test hook: tweaks persistence timing (util/wasm/test_persistence_browser.py). */
	luantiPersistenceTestOptions?: Record<string, unknown>;
	/** Set and read by CIrrDeviceSDL.cpp alone: the page-state publisher it installs on the main thread. */
	luantiPublishPageState?: () => void;
}

interface LuantiWebConfig {
	serverListUrl: string;
	defaultProxy: string;
	/**
	 * Hosted proxy regions. `expires` (an ISO date or timestamp) is the deployment
	 * owner's own end date for a proxy: from then on the launcher stops offering
	 * it, instead of letting a join hang against a proxy nobody maintains.
	 */
	proxies: Array<{ id: string; label: string; url: string; expires?: string }>;
}

declare var Module: LuantiModule;
declare var FS: any;
declare var IDBFS: any;
declare var AL: any;
declare var HEAPU8: Uint8Array;
declare function _malloc(size: number): number;
declare function _free(pointer: number): void;
declare function addRunDependency(id: string): void;
declare function UTF8ToString(pointer: number): string;
declare function removeRunDependency(id: string): void;

/** The `detail` of the `luanti:persistence` event (persistence.js, plus worlds.js with `library`). */
interface LuantiPersistenceEvent {
	state: string;
	reason?: string | null;
	pending?: boolean;
	fatal?: boolean;
	error?: string | null;
	/** Present when the event reports a world-library operation (create, rename, ...). */
	library?: { operation: string; [key: string]: unknown };
}

/** The `detail` of the `luanti:package` event (packages.js). */
interface LuantiPackageEvent {
	name: string;
	state: string;
	loaded: number;
	total: number;
	error: string | null;
}

/** Page events fired by the --pre-js files (`window.dispatchEvent`). */
interface WindowEventMap {
	"luanti:persistence": CustomEvent<LuantiPersistenceEvent>;
	"luanti:package": CustomEvent<LuantiPackageEvent>;
	"luanti:network": CustomEvent<LuantiNetworkState>;
	/** startup.js ended luanti.js before the engine existed; `detail` is `Module.luantiStartup.fatal`. */
	"luanti:startup-error": CustomEvent<{ code: string; message: string }>;
}

interface Window {
	Module: LuantiModule;
	LUANTI_WEB_CONFIG?: LuantiWebConfig;
	AL?: any;
	webkitAudioContext?: typeof AudioContext;
	/** Test hook (launcher-glloss.js): keeps the WEBGL_lose_context extension of the context it lost. */
	luantiLoseContextExt?: WEBGL_lose_context;
}
