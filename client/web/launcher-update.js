// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 The Luanti Contributors

// @ts-check

// Service-worker registration and the "new version available" toast.
//
// Narrow, versioned service worker (service-worker.js): precaches this build
// as one verified set, caches content-addressed asset packages forever, and
// never serves a mixed or stale engine. A new build waits until the user
// accepts it here.
//
// Loads after launcher.js; it has no dependency on the other launcher scripts.

(function() {
	"use strict";

	var shell = window.luantiShell;
	if (!shell)
		throw new Error("launcher-update.js must load after launcher.js");
	var ui = shell.ui;

	if ("serviceWorker" in navigator && (location.protocol === "https:" || location.hostname === "localhost" || location.hostname === "127.0.0.1")) {
		var reloadingForUpdate = false;

		/** @param {() => void} apply */
		var offerUpdate = function(apply) {
			ui.update.hidden = false;
			ui.updateReload.onclick = function() {
				ui.updateReload.disabled = true;
				apply();
			};
		};

		// A worker that installed while this page was already controlled is a
		// new build of this same deployment; it activates when told to.
		/** @param {ServiceWorker} worker */
		var offerWorker = function(worker) {
			offerUpdate(function() { worker.postMessage({type: "SKIP_WAITING"}); });
		};

		window.addEventListener("load", function() {
			var hadController = !!navigator.serviceWorker.controller;
			navigator.serviceWorker.addEventListener("controllerchange", function() {
				// First install claims the page; only an update needs a reload.
				if (!hadController || reloadingForUpdate)
					return;
				reloadingForUpdate = true;
				location.reload();
			});
			navigator.serviceWorker.register("service-worker.js", {scope: "./"}).then(function(registration) {
				if (registration.waiting && navigator.serviceWorker.controller)
					offerWorker(registration.waiting);
				registration.addEventListener("updatefound", function() {
					var installing = registration.installing;
					if (!installing)
						return;
					installing.addEventListener("statechange", function() {
						if (installing.state === "installed" && navigator.serviceWorker.controller)
							offerWorker(installing);
					});
				});
				registration.update().catch(function() {});
			}).catch(function(error) {
				shell.appendLog("service-worker", [error]);
			});
		});
	}

	// Versioned deployments (package_demo.py) serve every build from
	// releases/<version>/, each with its own service-worker scope, so a worker
	// update never arrives. Compare with the site's current version instead.
	var release = /\/releases\/([^/]+)\/[^/]*$/.exec(location.pathname);
	if (release && location.protocol !== "file:") {
		fetch(new URL("../../version.json", location.href), {cache: "no-store"}).then(function(response) {
			return response.ok ? response.json() : null;
		}).then(function(site) {
			if (!site || !site.entrypoint || site.version === release[1])
				return;
			ui.update.hidden = false;
			ui.updateReload.onclick = function() {
				location.assign(new URL("../../" + site.entrypoint, location.href).href + location.search);
			};
		}).catch(function() {});
	}
})();
