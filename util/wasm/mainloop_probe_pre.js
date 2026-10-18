// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 The Luanti Contributors

// Browser-main-thread heartbeat for the focused worker-main smoke test.
(function() {
	"use strict";
	if (typeof window === "undefined")
		return;

	var probe = window["luantiMainLoopProbe"] = {
		"browserTicks": 0,
		"ticksAtReady": 0,
		"ticksAtDone": 0,
		"ready": false,
		"done": false,
		"crossOriginIsolated": !!window.crossOriginIsolated,
		"workerMain": false,
		"webgl": false,
		"mouseCallbacks": 0,
		"pointerLock": false
	};

	setInterval(function() {
		probe["browserTicks"]++;
	}, 20);
})();
