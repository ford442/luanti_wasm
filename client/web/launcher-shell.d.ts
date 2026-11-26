// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 The Luanti Contributors

// The contract between the launcher scripts themselves (launcher*.js).
//
// emscripten-module.d.ts is the contract with the engine and the --pre-js
// files: everything C++ or an embedder may reach through `Module`. This file
// is the other half. The launcher is several classic scripts loaded from
// shell.html in a fixed order (see doc/compiling/wasm-embedding.md); the first
// one, launcher.js, creates `window.luantiShell` and each later script adds the
// piece it owns. Nothing here is reachable from C++, so nothing here belongs
// on `Module`.

/** A validated launch request (launcher-start.js). */
interface LuantiSession {
	mode: "local" | "remote";
	address: string;
	port: number;
	name: string;
	game: string;
	/** The singleplayer world to open; null for a remote server. */
	world: string | null;
	/** View-distance preset: "60", "100" or "160". */
	view: string;
	language: string;
}

/**
 * The launcher markup is fixed (client/web/shell.html), so every element is
 * looked up once, by id, in launcher.js and typed here.
 */
interface LuantiLauncherUi {
	launcher: HTMLElement;
	gameShell: HTMLElement;
	form: HTMLFormElement;
	localTab: HTMLButtonElement;
	remoteTab: HTMLButtonElement;
	localPanel: HTMLElement;
	remotePanel: HTMLElement;
	address: HTMLInputElement;
	port: HTMLInputElement;
	name: HTMLInputElement;
	game: HTMLSelectElement;
	quality: HTMLSelectElement;
	language: HTMLSelectElement;
	proxyRegion: HTMLSelectElement;
	customProxyRow: HTMLElement;
	proxyUrl: HTMLInputElement;
	proxyNotice: HTMLElement;
	proxySummary: HTMLElement;
	proxyAlert: HTMLElement;
	proxyAlertText: HTMLElement;
	proxyAlertReload: HTMLButtonElement;
	play: HTMLButtonElement;
	playLabel: HTMLElement;
	error: HTMLElement;
	serverListButton: HTMLButtonElement;
	serverList: HTMLElement;
	mobileWarning: HTMLElement;
	loading: HTMLElement;
	loadingPhase: HTMLElement;
	loadingStatus: HTMLElement;
	loadingProgress: HTMLElement;
	share: HTMLButtonElement;
	fullscreen: HTMLButtonElement;
	consoleButton: HTMLButtonElement;
	consolePanel: HTMLDetailsElement;
	consoleOutput: HTMLElement;
	consoleClear: HTMLButtonElement;
	resume: HTMLElement;
	resumeButton: HTMLButtonElement;
	glLost: HTMLElement;
	glLostText: HTMLElement;
	glLostReload: HTMLButtonElement;
	update: HTMLElement;
	updateReload: HTMLButtonElement;
	worldList: HTMLElement;
	newWorld: HTMLButtonElement;
	importWorld: HTMLButtonElement;
	importFile: HTMLInputElement;
	libraryStatus: HTMLElement;
	storageNote: HTMLElement;
	dialog: HTMLDialogElement;
	dialogForm: HTMLFormElement;
	dialogTitle: HTMLElement;
	dialogBody: HTMLElement;
	dialogError: HTMLElement;
	dialogCancel: HTMLButtonElement;
	dialogConfirm: HTMLButtonElement;
}

/** The launcher's session state. Owned by launcher.js; the other scripts read it. */
interface LuantiLauncherState {
	/** The engine runtime exists (`onRuntimeInitialized` ran). */
	runtimeReady: boolean;
	/** The eager `core` asset package is mounted. */
	coreReady: boolean;
	/** `callMain` has been called: the engine owns the canvas and the open world. */
	started: boolean;
	launchInFlight: boolean;
	backgroundStarted: boolean;
	/** Embedder pause request; kept so one made before the runtime exists still applies. */
	enginePaused: boolean;
	activeMode: "local" | "remote";
	/** assets, storage, engine, menu, loading or playing (the engine may report others). */
	activePhase: string;
	currentSession: LuantiSession | null;
	loadingShellDismissed: boolean;
	/** Set when startup.js ended luanti.js before the engine existed. */
	startupFailure: { code?: string; message?: string } | null;
}

/** Moments launcher.js announces to the scripts that load after it. */
type LuantiLauncherEvent = "playing" | "framepresented";

/** The world-library panel (launcher-library.js), which renders `Module.luantiWorlds`. */
interface LuantiLauncherLibrary {
	/** Re-read the saved worlds and redraw the list. */
	refresh(): Promise<void>;
	/** The selected world's name, or null for the game's default world. */
	selectedWorld(): string | null;
	/** Create the session's world if it does not exist yet, and mark it played. */
	prepareWorld(session: LuantiSession): Promise<void>;
}

/** The multiplayer connection panel (launcher-connect.js). */
interface LuantiLauncherConnect {
	/** Apply the chosen proxy to `Module.luantiNetwork`; throws a player-facing Error. */
	validateProxy(remote: boolean): string;
	/**
	 * Start the join clock and dial the chosen proxy once, before the engine is
	 * started. Resolves when a join can go ahead; rejects with a player-facing
	 * Error carrying the proxy's own reason.
	 */
	preflight(): Promise<LuantiNetworkProbeResult | null>;
	/** Why joining a server is not possible with the current choices, or "". */
	blocker(): string;
}

/** Pointer, touch, audio and canvas-size handling (launcher-input.js). */
interface LuantiLauncherInput {
	unlockAudio(): void;
	/** Match the canvas backing store to its CSS box (a no-op once the engine runs). */
	syncCanvasBackingStore(): void;
	/** What the engine reads once, before `callMain` (`Module.luantiInput`). */
	probe(): NonNullable<LuantiModule["luantiInput"]>;
}

/** `window.luantiShell`: created by launcher.js, extended by each launcher script after it. */
interface LuantiLauncherShell {
	config: Partial<LuantiWebConfig>;
	query: URLSearchParams;
	ui: LuantiLauncherUi;
	state: LuantiLauncherState;

	appendLog(kind: string, values: ArrayLike<unknown>): void;
	/** Show (or, with an empty message, hide) the launch-form error line. */
	showError(message: string): void;
	/** `percent` is null or undefined when unknown. */
	reportStatus(message: string | null, percent?: number | null, phase?: string | null): void;
	safeStorageGet(key: string): string;
	safeStorageSet(key: string, value: string): void;
	on(event: LuantiLauncherEvent, handler: () => void): void;
	/**
	 * Whether the engine should keep calling `notifyFramePresented` after the
	 * loading shell is dismissed. launcher-library.js replaces this while it
	 * waits to capture a world thumbnail.
	 */
	frameHookWanted(): boolean;

	library?: LuantiLauncherLibrary;
	connect?: LuantiLauncherConnect;
	input?: LuantiLauncherInput;
}

interface Window {
	luantiShell?: LuantiLauncherShell;
}
