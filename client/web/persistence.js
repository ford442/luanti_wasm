// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 The Luanti Contributors

// Browser persistence bootstrap.
// This file is included with --pre-js and intentionally uses quoted Module
// properties so the public integration contract survives Closure optimization.

(function() {
	"use strict";
	// In PROXY_TO_PTHREAD builds the generated program is also evaluated in
	// application workers. IDBFS and its lifecycle UI are browser-main owned.
	if (typeof window === "undefined" && typeof document === "undefined")
		return;

	/**
	 * What an error can look like when it comes from IDBFS or FS: usually an
	 * Error or DOMException, but errorText copes with anything.
	 * @typedef {{name?: string, message?: string}} PersistenceErrorLike
	 */

	/**
	 * The `luanti:persistence` event detail, as LuantiPersistence.getState returns it.
	 * @typedef {ReturnType<LuantiPersistence["getState"]>} PersistenceSnapshot
	 */

	/**
	 * A requestSync caller waiting for a generation to reach storage.
	 * @typedef {Object} PersistenceWaiter
	 * @property {number} generation
	 * @property {() => void} resolve
	 * @property {(error: Error) => void} reject
	 */

	/**
	 * What queueSync reads (`_requestGeneration` passes a `generation` as well).
	 * @typedef {{reason?: string, urgent?: boolean}} PersistenceSyncOptions
	 */

	var mountPath = "/home/web_user/.luanti";
	var dependencyName = "luanti-idbfs-hydration";
	var testOptions = Module["luantiPersistenceTestOptions"] || {};
	var retryDelays = /** @type {number[]} */ (testOptions["retryDelays"] || [1000, 5000, 30000]);
	var requestedGeneration = 0;
	var savedGeneration = 0;
	var latestEngineGeneration = 0;
	/** @type {object|null} */
	var inFlight = null;
	/** @type {ReturnType<typeof setTimeout>|null} */
	var retryTimer = null;
	var retryAttempt = 0;
	var ready = false;
	var fatal = false;
	/** @type {string|null} */
	var lastError = null;
	/** @type {PersistenceWaiter[]} */
	var waiters = [];
	var latestReason = "startup";
	/** @type {PersistenceSnapshot} */
	var snapshot = {
		"state": "loading",
		"reason": "startup",
		"pending": true,
		"fatal": false,
		"error": null
	};

	/**
	 * @param {PersistenceErrorLike|null|undefined} error
	 * @returns {string}
	 */
	function errorText(error) {
		if (!error)
			return "Unknown storage error";
		if (error.name && error.message)
			return error.name + ": " + error.message;
		return String(error.message || error);
	}

	/** @returns {PersistenceSnapshot} */
	function copySnapshot() {
		return {
			"state": snapshot["state"],
			"reason": snapshot["reason"],
			"pending": snapshot["pending"],
			"fatal": snapshot["fatal"],
			"error": snapshot["error"]
		};
	}

	/** @param {PersistenceSnapshot} state */
	function updateShell(state) {
		if (typeof document === "undefined")
			return;
		var status = document.getElementById("luanti-persistence-status");
		var error = document.getElementById("luanti-persistence-error");
		if (status) {
			/** @type {Record<string, string>} */
			var labels = {
				"loading": "Loading saved data…",
				"ready": "Storage ready",
				"saving": "Saving… don’t close this tab",
				"saved": "Saved",
				"error": "Save failed"
			};
			status.textContent = labels[state["state"]] || state["state"];
			status.dataset.state = state["state"];
			status.hidden = state["state"] === "ready";
		}
		if (error && state["error"]) {
			error.textContent = (state["fatal"] ? "Storage unavailable: " :
				"Changes are not saved: ") + state["error"];
			error.hidden = false;
		} else if (error && !state["fatal"]) {
			error.textContent = "";
			error.hidden = true;
		}
		if (state["fatal"]) {
			var canvas = document.getElementById("canvas");
			if (canvas)
				canvas.hidden = true;
		}
	}

	/**
	 * @param {string} state
	 * @param {string|null} reason
	 * @param {boolean} pending
	 * @param {boolean} isFatal
	 * @param {string|null} error
	 */
	function emitState(state, reason, pending, isFatal, error) {
		snapshot = {
			"state": state,
			"reason": reason,
			"pending": pending,
			"fatal": isFatal,
			"error": error
		};
		var detail = copySnapshot();
		updateShell(detail);
		if (typeof window !== "undefined" && window.dispatchEvent) {
			var event;
			if (typeof CustomEvent === "function")
				event = new CustomEvent("luanti:persistence", {"detail": detail});
			else {
				event = document.createEvent("CustomEvent");
				event.initCustomEvent("luanti:persistence", false, false, detail);
			}
			window.dispatchEvent(event);
		}
	}

	/** @param {string} path */
	function ensureDirectory(path) {
		try {
			FS.mkdir(path);
		} catch (error) {
			var exists = FS.analyzePath && FS.analyzePath(path)["exists"];
			if (!exists)
				throw error;
		}
	}

	/** @param {PersistenceErrorLike|null|undefined} error */
	function failStartup(error) {
		fatal = true;
		lastError = errorText(error);
		console.error("Luanti: persistent storage failed during startup", error);
		emitState("error", "startup", true, true, lastError);
		settleWaiters(error instanceof Error ? error : new Error(lastError),
			requestedGeneration);
	}

	/**
	 * @param {"_luanti_persistence_sync_failed"|"_luanti_persistence_sync_completed"} name
	 * @param {number} generation
	 */
	function callEngine(name, generation) {
		var callback = Module[name];
		if (typeof callback === "function")
			callback(generation);
	}

	/**
	 * @param {Error|null} error
	 * @param {number} completedGeneration
	 */
	function settleWaiters(error, completedGeneration) {
		/** @type {PersistenceWaiter[]} */
		var remaining = [];
		waiters.forEach(function(waiter) {
			if (waiter["generation"] <= completedGeneration) {
				if (error)
					waiter["reject"](error);
				else
					waiter["resolve"]();
			} else {
				remaining.push(waiter);
			}
		});
		waiters = remaining;
	}

	function scheduleRetry() {
		if (fatal || retryTimer !== null)
			return;
		var delay = retryDelays[Math.min(retryAttempt, retryDelays.length - 1)];
		retryAttempt++;
		retryTimer = setTimeout(function() {
			retryTimer = null;
			latestReason = "retry";
			startFlush();
		}, delay);
	}

	function startFlush() {
		if (!ready || fatal || inFlight || retryTimer !== null ||
				savedGeneration >= requestedGeneration)
			return;

		var targetGeneration = requestedGeneration;
		var engineGeneration = latestEngineGeneration;
		var reason = latestReason;
		inFlight = {};
		emitState("saving", reason, true, false, lastError);

		// FS is declared any, so the callback's parameter type is given here.
		FS.syncfs(false, /** @param {Error|null} error */ function(error) {
			inFlight = null;
			if (error) {
				lastError = errorText(error);
				console.error("Luanti: persistent storage sync failed", error);
				emitState("error", reason, true, false, lastError);
				settleWaiters(error, targetGeneration);
				callEngine("_luanti_persistence_sync_failed", engineGeneration);
				scheduleRetry();
				return;
			}

			savedGeneration = Math.max(savedGeneration, targetGeneration);
			retryAttempt = 0;
			lastError = null;
			settleWaiters(null, savedGeneration);
			callEngine("_luanti_persistence_sync_completed", engineGeneration);

			if (savedGeneration < requestedGeneration) {
				// Coalesce every write observed during the active sync into one
				// immediately following sync. startFlush itself enforces single-flight.
				startFlush();
			} else {
				emitState("saved", reason, false, false, null);
			}
		});
	}

	/**
	 * @param {PersistenceSyncOptions} [options]
	 * @param {boolean} [withPromise] Whether to return a promise for the sync.
	 * @returns {Promise<void>|undefined}
	 */
	function queueSync(options, withPromise) {
		options = options || {};
		var reason = options["reason"] || "external";
		var urgent = !!options["urgent"];
		requestedGeneration++;
		latestReason = reason;

		/** @type {Promise<void>|undefined} */
		var promise;
		if (withPromise) {
			var generation = requestedGeneration;
			promise = new Promise(function(resolve, reject) {
				waiters.push({
					"generation": generation,
					"resolve": resolve,
					"reject": reject
				});
			});
		}

		if (urgent && retryTimer !== null) {
			clearTimeout(retryTimer);
			retryTimer = null;
		}
		startFlush();
		return promise;
	}

	var api = {
		/** @param {PersistenceSyncOptions} [options] */
		"requestSync": function(options) {
			if (fatal)
				return Promise.reject(new Error(lastError || "Storage unavailable"));
			return queueSync(options, true);
		},
		"getState": function() {
			return copySnapshot();
		},
		/** @param {PersistenceSyncOptions & {generation?: number}} [options] */
		"_requestGeneration": function(options) {
			options = options || {};
			latestEngineGeneration = Math.max(latestEngineGeneration,
				Number(options["generation"]) || 0);
			queueSync(options, false);
		}
	};

	Module["luantiPersistence"] = api;
	// The final async save and retry timers must remain live after C++ main
	// returns. The generated browser shell owns the page lifetime.
	Module["noExitRuntime"] = true;

	/** @param {string} reason */
	function lifecycleSync(reason) {
		if (ready && !fatal)
			queueSync({"reason": reason, "urgent": true}, false);
	}

	if (typeof document !== "undefined" && document.addEventListener) {
		document.addEventListener("visibilitychange", function() {
			if (document.visibilityState === "hidden")
				lifecycleSync("pagehide");
		});
	}
	if (typeof window !== "undefined" && window.addEventListener) {
		window.addEventListener("pagehide", function() {
			lifecycleSync("pagehide");
		});
		window.addEventListener("beforeunload", function() {
			lifecycleSync("pagehide");
		});
	}

	var originalPreRun = Module["preRun"];
	if (!Array.isArray(originalPreRun))
		originalPreRun = originalPreRun ? [originalPreRun] : [];
	Module["preRun"] = originalPreRun;
	Module["preRun"].push(function() {
		addRunDependency(dependencyName);
		try {
			ensureDirectory("/home");
			ensureDirectory("/home/web_user");
			ensureDirectory(mountPath);
			FS.mount(IDBFS, {}, mountPath);
		} catch (error) {
			failStartup(error);
			return;
		}

		try {
			FS.syncfs(true, /** @param {Error|null} error */ function(error) {
				if (error) {
					failStartup(error);
					return;
				}

				try {
					["worlds", "mods", "textures", "games", "clientmods"].forEach(
						function(dir) { ensureDirectory(mountPath + "/" + dir); });
				} catch (directoryError) {
					failStartup(directoryError);
					return;
				}

				ready = true;
				emitState("ready", "startup", false, false, null);
				removeRunDependency(dependencyName);
				startFlush();
			});
		} catch (error) {
			failStartup(error);
		}
	});
})();
