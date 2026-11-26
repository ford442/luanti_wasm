// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 The Luanti Contributors

import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import vm from "node:vm";

const source = await readFile(new URL("../../client/web/persistence.js", import.meta.url), "utf8");

const tick = () => new Promise(resolve => setTimeout(resolve, 0));

function createHarness(store = new Map(), options = {}) {
	const directories = new Set(["/", "/home", "/home/web_user"]);
	const files = new Map();
	const saveCallbacks = [];
	const events = [];
	const windowListeners = new Map();
	const consoleErrors = [];
	const dependencies = new Set();
	let mainStarted = false;
	let saveCount = 0;
	let activeSaves = 0;
	let maxActiveSaves = 0;

	const FS = {
		mkdir(path) {
			if (directories.has(path))
				throw new Error("EEXIST: " + path);
			const parent = path.slice(0, path.lastIndexOf("/")) || "/";
			if (!directories.has(parent))
				throw new Error("ENOENT: " + parent);
			directories.add(path);
		},
		analyzePath(path) {
			return {exists: directories.has(path) || files.has(path)};
		},
		mount() {
			if (options.mountError)
				throw options.mountError;
		},
		writeFile(path, value) {
			files.set(path, String(value));
		},
		readFile(path) {
			if (!files.has(path))
				throw new Error("ENOENT: " + path);
			return files.get(path);
		},
		syncfs(populate, callback) {
			if (populate) {
				queueMicrotask(() => {
					if (options.hydrationError) {
						callback(options.hydrationError);
						return;
					}
					for (const [path, value] of store)
						files.set(path, value);
					callback(null);
				});
				return;
			}

			saveCount++;
			activeSaves++;
			maxActiveSaves = Math.max(maxActiveSaves, activeSaves);
			const finish = error => {
				activeSaves--;
				if (!error) {
					store.clear();
					for (const entry of files)
						store.set(...entry);
				}
				callback(error || null);
			};

			if (options.manualSaves)
				saveCallbacks.push(finish);
			else {
				const error = options.saveErrors?.shift() || null;
				queueMicrotask(() => finish(error));
			}
		}
	};

	const Module = {
		luantiPersistenceTestOptions: {retryDelays: options.retryDelays || [5, 5, 5]}
	};
	const context = vm.createContext({
		Module,
		FS,
		IDBFS: {},
		Promise,
		Error,
		Number,
		String,
		Array,
		Math,
		console: {
			log: console.log,
			warn: console.warn,
			error(...args) { consoleErrors.push(args); }
		},
		queueMicrotask,
		setTimeout,
		clearTimeout,
		window: {
			addEventListener(name, callback) {
				const callbacks = windowListeners.get(name) || [];
				callbacks.push(callback);
				windowListeners.set(name, callbacks);
			},
			dispatchEvent(event) { events.push(event); }
		},
		CustomEvent: class {
			constructor(type, init) {
				this.type = type;
				this.detail = init.detail;
			}
		},
		addRunDependency(name) { dependencies.add(name); },
		removeRunDependency(name) {
			dependencies.delete(name);
			mainStarted = true;
		}
	});
	vm.runInContext(source, context, {filename: "persistence.js"});

	return {
		Module,
		FS,
		store,
		events,
		consoleErrors,
		dependencies,
		get mainStarted() { return mainStarted; },
		get saveCount() { return saveCount; },
		get maxActiveSaves() { return maxActiveSaves; },
		async preRun() {
			for (const callback of Module.preRun)
				callback();
			await tick();
		},
		finishSave(error = null) {
			assert.ok(saveCallbacks.length > 0, "expected a pending save");
			saveCallbacks.shift()(error);
		},
		dispatchWindow(name) {
			for (const callback of windowListeners.get(name) || [])
				callback();
		}
	};
}

async function testHydrationPrecedesMainAndSurvivesReload() {
	const store = new Map();
	const first = createHarness(store);
	await first.preRun();
	assert.equal(first.mainStarted, true);
	assert.equal(first.Module.luantiPersistence.getState().state, "ready");

	const sentinel = "/home/web_user/.luanti/worlds/persistence-sentinel";
	first.FS.writeFile(sentinel, "still here");
	await first.Module.luantiPersistence.requestSync({reason: "external", urgent: true});

	const reloaded = createHarness(store);
	await reloaded.preRun();
	assert.equal(reloaded.FS.readFile(sentinel), "still here");
}

async function testBurstIsSingleFlightWithOneFollowUp() {
	const harness = createHarness(new Map(), {manualSaves: true});
	await harness.preRun();

	const first = harness.Module.luantiPersistence.requestSync({reason: "periodic"});
	const second = harness.Module.luantiPersistence.requestSync({reason: "settings"});
	const third = harness.Module.luantiPersistence.requestSync({reason: "periodic"});
	assert.equal(harness.saveCount, 1);
	harness.finishSave();
	await tick();
	assert.equal(harness.saveCount, 2);
	harness.finishSave();
	await Promise.all([first, second, third]);
	assert.equal(harness.saveCount, 2);
	assert.equal(harness.maxActiveSaves, 1);
}

async function testHydrationFailureGatesMain() {
	const failure = new Error("IndexedDB denied");
	const harness = createHarness(new Map(), {hydrationError: failure});
	await harness.preRun();
	const state = harness.Module.luantiPersistence.getState();
	assert.equal(harness.mainStarted, false);
	assert.equal(harness.dependencies.has("luanti-idbfs-hydration"), true);
	assert.deepEqual(
		{state: state.state, fatal: state.fatal, pending: state.pending},
		{state: "error", fatal: true, pending: true});
	assert.equal(harness.consoleErrors.length, 1);
}

async function testBeforeUnloadRequestsBestEffortSave() {
	const harness = createHarness(new Map(), {manualSaves: true});
	await harness.preRun();
	harness.dispatchWindow("beforeunload");
	assert.equal(harness.saveCount, 1);
	assert.deepEqual(
		{state: harness.Module.luantiPersistence.getState().state,
			reason: harness.Module.luantiPersistence.getState().reason},
		{state: "saving", reason: "pagehide"});
	harness.finishSave();
	await tick();
}

async function testRuntimeFailureRejectsAndRetriesDirtyState() {
	const quota = new Error("storage quota exceeded");
	quota.name = "QuotaExceededError";
	const harness = createHarness(new Map(), {
		saveErrors: [quota, null],
		retryDelays: [5, 5, 5]
	});
	await harness.preRun();

	await assert.rejects(
		harness.Module.luantiPersistence.requestSync({reason: "settings"}),
		/price|quota/i);
	let state = harness.Module.luantiPersistence.getState();
	assert.equal(state.state, "error");
	assert.equal(state.pending, true);
	assert.match(state.error, /QuotaExceededError/);
	assert.equal(harness.consoleErrors.length, 1);

	await new Promise(resolve => setTimeout(resolve, 15));
	state = harness.Module.luantiPersistence.getState();
	assert.equal(harness.saveCount, 2);
	assert.equal(state.state, "saved");
	assert.equal(state.pending, false);
	assert.equal(state.error, null);
}

await testHydrationPrecedesMainAndSurvivesReload();
await testBurstIsSingleFlightWithOneFollowUp();
await testHydrationFailureGatesMain();
await testBeforeUnloadRequestsBestEffortSave();
await testRuntimeFailureRejectsAndRetriesDirtyState();
console.log("Luanti persistence smoke: PASS");
