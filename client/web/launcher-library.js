// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 The Luanti Contributors

// @ts-check

// The world library panel of the launcher. client/web/worlds.js
// (Module.luantiWorlds) owns every file operation and every storage decision;
// this file only renders what it returns: the world list and its menu, the
// New / Rename / Delete / Import dialogs, export download, drag-and-drop, the
// `?world=` share offer, and the thumbnail the world gets after a few seconds
// of play. Library operations only run before callMain, while no world is
// open.
//
// Loads after launcher.js; launcher-start.js uses `luantiShell.library`.

(function() {
	"use strict";

	var shell = window.luantiShell;
	if (!shell)
		throw new Error("launcher-library.js must load after launcher.js");
	var ui = shell.ui;
	var state = shell.state;
	var query = shell.query;

	/** @type {LuantiWorld[]} */
	var worlds = [];
	/** @type {string | null} a world name, or null: the game's default world */
	var selectedWorld = null;
	var libraryLoaded = false;
	var libraryBusy = false;
	/** @type {string[]} */
	var thumbnailUrls = [];
	var preferredWorld = query.get("worldname");
	/** @type {{pending: boolean, requested: boolean, armedAt: number, attempts: number, timer: ReturnType<typeof setTimeout> | null}} */
	var thumbnail = {pending: false, requested: false, armedAt: 0, attempts: 0, timer: null};

	function library() {
		return Module["luantiWorlds"] || null;
	}

	/** @param {any} error */
	function messageOf(error) {
		return String(error && error.message || error);
	}

	/**
	 * @param {string} tag
	 * @param {Record<string, any>} [attributes]
	 * @param {Array<Node|string>|Node|string} [content]
	 * @returns {any}
	 */
	function make(tag, attributes, content) {
		var node = document.createElement(tag);
		Object.keys(attributes || {}).forEach(function(key) {
			var value = attributes[key];
			if (value === null || value === undefined || value === false)
				return;
			if (key === "text")
				node.textContent = value;
			else if (key === "className")
				node.className = value;
			else
				node.setAttribute(key, value === true ? "" : String(value));
		});
		[].concat(content === undefined ? [] : content).forEach(function(child) {
			node.append(child);
		});
		return node;
	}

	/**
	 * @param {string} text
	 * @param {string} [kind]
	 */
	function setLibraryStatus(text, kind) {
		ui.libraryStatus.textContent = text || "";
		ui.libraryStatus.hidden = !text;
		if (kind)
			ui.libraryStatus.dataset.state = kind;
		else
			delete ui.libraryStatus.dataset.state;
	}

	/** @param {number | null | undefined} bytes */
	function sizeText(bytes) {
		if (bytes === null || bytes === undefined)
			return "";
		if (bytes < 1024 * 1024)
			return Math.max(1, Math.round(bytes / 1024)) + " KB";
		if (bytes < 1024 * 1024 * 1024)
			return (bytes / 1048576).toFixed(bytes < 10485760 ? 1 : 0) + " MB";
		return (bytes / 1073741824).toFixed(1) + " GB";
	}

	/** @param {number} ms */
	function relativeTime(ms) {
		var seconds = (ms - Date.now()) / 1000;
		/** @type {Array<[Intl.RelativeTimeFormatUnit, number]>} */
		var units = [["year", 31536000], ["month", 2592000], ["week", 604800], ["day", 86400],
			["hour", 3600], ["minute", 60]];
		var format = typeof Intl !== "undefined" && Intl.RelativeTimeFormat ?
			new Intl.RelativeTimeFormat(undefined, {numeric: "auto"}) : null;
		for (var i = 0; i < units.length; i++) {
			if (Math.abs(seconds) >= units[i][1] || i === units.length - 1) {
				var value = Math.round(seconds / units[i][1]);
				if (!format)
					return Math.abs(value) + " " + units[i][0] + "(s) ago";
				return format.format(value, units[i][0]);
			}
		}
		return "";
	}

	/** @param {string} id */
	function gameTitle(id) {
		var option = Array.prototype.find.call(ui.game.options, function(/** @type {HTMLOptionElement} */ entry) {
			return entry.value === id;
		});
		return option ? option.textContent : id;
	}

	/** @param {string} game */
	function worldsForGame(game) {
		return worlds.filter(function(world) {
			return world.game === game;
		}).sort(function(a, b) {
			var at = a.lastPlayed || a.modified || a.created || 0;
			var bt = b.lastPlayed || b.modified || b.created || 0;
			return bt - at || a.name.localeCompare(b.name);
		});
	}

	/** @returns {Promise<void>} */
	function refreshWorlds() {
		var lib = library();
		if (!lib)
			return Promise.resolve();
		return lib.list().then(function(list) {
			worlds = list;
			renderWorlds();
			updateStorageNote();
		}, function(error) {
			setLibraryStatus("Could not read saved worlds: " + messageOf(error), "error");
		});
	}

	function updateStorageNote() {
		var lib = library();
		if (!lib)
			return;
		lib.storage().then(function(info) {
			var text = "Worlds are saved in this browser";
			if (info.usage !== null)
				text += " (" + sizeText(info.usage) + " used)";
			text += ". Export one to keep a copy.";
			if (info.persisted === false)
				text += " The browser may clear them if it runs out of space.";
			ui.storageNote.textContent = text;
		});
	}

	/** @param {string | null} name */
	function selectWorld(name) {
		selectedWorld = name;
		Array.prototype.forEach.call(ui.worldList.querySelectorAll(".world-entry"), function(/** @type {HTMLElement} */ row) {
			var match = row.dataset.world === name;
			row.classList.toggle("is-selected", match);
			var radio = row.querySelector("input[type=radio]");
			if (radio instanceof HTMLInputElement)
				radio.checked = match;
		});
	}

	function renderWorlds() {
		var game = ui.game.value;
		var list = worldsForGame(game);
		thumbnailUrls.forEach(function(url) { URL.revokeObjectURL(url); });
		thumbnailUrls = [];
		ui.worldList.replaceChildren();
		ui.worldList.setAttribute("aria-busy", "false");

		var names = list.map(function(world) { return world.name; });
		if (preferredWorld && names.indexOf(preferredWorld) !== -1) {
			selectedWorld = preferredWorld;
			preferredWorld = null;
		} else if (names.indexOf(selectedWorld) === -1) {
			// The game's legacy world (named after the game) first, then the
			// most recently played one.
			selectedWorld = names.indexOf(game) !== -1 ? game : names[0] || null;
		}

		if (!list.length) {
			ui.worldList.append(make("p", {"className": "world-empty"},
				"No worlds for " + gameTitle(game) + " yet. Start world creates one, or use New world to choose a name and seed."));
			return;
		}

		list.forEach(function(world) {
			var details = [];
			if (world.lastPlayed)
				details.push("Played " + relativeTime(world.lastPlayed));
			else if (world.created || world.modified)
				details.push("Created " + relativeTime(world.created || world.modified));
			else
				details.push("Never played");
			details.push(sizeText(world.size));
			var thumb = make("span", {"className": "world-thumb", "aria-hidden": "true"}, "▦");
			var radio = make("input", {"type": "radio", "name": "world", "value": world.name});
			var row = make("div", {"className": "world-entry", "data-world": world.name}, [
				make("label", {"className": "world-pick"}, [
					radio,
					thumb,
					make("span", {"className": "world-text"}, [
						make("strong", {"text": world.name}),
						make("small", {"text": details.join(" · ")})
					])
				]),
				make("details", {"className": "world-menu"}, [
					make("summary", {"aria-label": "Actions for " + world.name, "title": "World actions"}, "•••"),
					make("div", {"className": "world-menu-items"}, [
						make("button", {"type": "button", "data-action": "rename", "data-world": world.name}, "Rename"),
						make("button", {"type": "button", "data-action": "duplicate", "data-world": world.name}, "Duplicate"),
						make("button", {"type": "button", "data-action": "export", "data-world": world.name}, "Export"),
						make("button", {"type": "button", "data-action": "delete", "data-world": world.name,
							"className": "is-danger"}, "Delete")
					])
				])
			]);
			radio.addEventListener("change", function() { selectWorld(world.name); });
			ui.worldList.append(row);
			if (world.hasThumbnail) {
				library().thumbnail(world.name).then(function(blob) {
					if (!blob)
						return;
					var url = URL.createObjectURL(blob);
					thumbnailUrls.push(url);
					thumb.replaceChildren(make("img", {"src": url, "alt": ""}));
				}).catch(function() {});
			}
		});
		selectWorld(selectedWorld);
	}

	ui.game.addEventListener("change", function() {
		selectedWorld = null;
		renderWorlds();
	});

	// Only one world menu open at a time; a click elsewhere closes it.
	document.addEventListener("click", function(event) {
		var target = /** @type {Element} */ (event.target);
		Array.prototype.forEach.call(ui.worldList.querySelectorAll(".world-menu[open]"), function(/** @type {HTMLDetailsElement} */ menu) {
			if (!menu.contains(target))
				menu.open = false;
		});
	});

	ui.worldList.addEventListener("click", function(event) {
		var button = /** @type {Element} */ (event.target).closest("button[data-action]");
		if (!button)
			return;
		var menu = button.closest("details");
		if (menu)
			menu.open = false;
		var name = button.getAttribute("data-world");
		var action = button.getAttribute("data-action");
		if (action === "rename")
			renameWorld(name);
		else if (action === "duplicate")
			duplicateWorld(name);
		else if (action === "export")
			exportWorld(name);
		else if (action === "delete")
			deleteWorld(name);
	});

	// --- dialogs

	/** @param {any} error */
	function showDialogError(error) {
		ui.dialogError.textContent = messageOf(error);
		ui.dialogError.hidden = false;
	}

	/**
	 * Opens the shared modal. `accept` runs on confirm and may return a
	 * promise; a rejection is shown inside the dialog, which stays open.
	 * Resolves with accept's result, or null when cancelled.
	 * @param {{title: string, body: any, confirm?: string|null, cancel?: string, danger?: boolean,
	 *   accept?: () => any}} options
	 * @returns {Promise<any>}
	 */
	function openDialog(options) {
		return new Promise(function(resolve) {
			var working = false;
			ui.dialogTitle.textContent = options.title;
			ui.dialogBody.replaceChildren.apply(ui.dialogBody, [].concat(options.body || []));
			ui.dialogError.hidden = true;
			ui.dialogConfirm.hidden = options.confirm === null;
			ui.dialogConfirm.disabled = false;
			ui.dialogConfirm.textContent = options.confirm || "OK";
			ui.dialogConfirm.classList.toggle("is-danger", !!options.danger);
			ui.dialogCancel.textContent = options.cancel || "Cancel";
			ui.dialogCancel.disabled = false;

			function cleanup() {
				ui.dialogForm.removeEventListener("submit", onSubmit);
				ui.dialogCancel.removeEventListener("click", onCancel);
				ui.dialog.removeEventListener("cancel", onCancel);
			}
			/** @param {any} value */
			function finish(value) {
				cleanup();
				if (ui.dialog.open)
					ui.dialog.close();
				resolve(value);
			}
			/** @param {Event} event */
			function onCancel(event) {
				event.preventDefault();
				if (!working)
					finish(null);
			}
			/** @param {Event} event */
			function onSubmit(event) {
				event.preventDefault();
				if (working)
					return;
				ui.dialogError.hidden = true;
				working = true;
				ui.dialogConfirm.disabled = true;
				ui.dialogCancel.disabled = true;
				Promise.resolve().then(function() {
					return options.accept ? options.accept() : true;
				}).then(finish, function(error) {
					working = false;
					ui.dialogConfirm.disabled = false;
					ui.dialogCancel.disabled = false;
					showDialogError(error);
				});
			}
			ui.dialogForm.addEventListener("submit", onSubmit);
			ui.dialogCancel.addEventListener("click", onCancel);
			ui.dialog.addEventListener("cancel", onCancel);
			ui.dialog.showModal();
			var first = ui.dialogBody.querySelector("input, select");
			(first instanceof HTMLElement ? first : ui.dialogConfirm.hidden ? ui.dialogCancel : ui.dialogConfirm).focus();
			if (first instanceof HTMLInputElement)
				first.select();
		});
	}

	/**
	 * @param {string} label
	 * @param {{id: string}} control
	 */
	function field(label, control) {
		return [make("label", {"for": control.id, "text": label}), control];
	}

	/** @param {string} id */
	function modeSelect(id) {
		return make("select", {"id": id}, [
			make("option", {"value": ""}, "Game default"),
			make("option", {"value": "true"}, "On"),
			make("option", {"value": "false"}, "Off")
		]);
	}

	/**
	 * @param {() => any} task
	 * @returns {Promise<any>}
	 */
	function runLibrary(task) {
		if (libraryBusy)
			return Promise.resolve(null);
		libraryBusy = true;
		shell.showError("");
		return Promise.resolve().then(task).catch(/** @returns {null} */ function(error) {
			setLibraryStatus("");
			shell.showError(messageOf(error));
			return null;
		}).finally(function() {
			libraryBusy = false;
		});
	}

	function newWorld() {
		var lib = library();
		if (!lib || libraryBusy)
			return;
		var name = make("input", {"id": "luanti-new-world-name", "maxlength": "48", "autocomplete": "off",
			"spellcheck": "false"});
		var game = make("select", {"id": "luanti-new-world-game"});
		Array.prototype.forEach.call(ui.game.options, function(/** @type {HTMLOptionElement} */ option) {
			game.append(make("option", {"value": option.value}, option.textContent));
		});
		game.value = ui.game.value;
		var seed = make("input", {"id": "luanti-new-world-seed", "maxlength": "64", "placeholder": "Random",
			"autocomplete": "off", "spellcheck": "false"});
		var creative = modeSelect("luanti-new-world-creative");
		var damage = modeSelect("luanti-new-world-damage");
		var nameEdited = false;
		name.addEventListener("input", function() { nameEdited = true; });
		var suggest = function() {
			if (!nameEdited)
				lib.suggestName(gameTitle(game.value)).then(function(value) { name.value = value; });
		};
		game.addEventListener("change", suggest);
		suggest();
		/**
		 * @param {HTMLSelectElement} select
		 * @returns {boolean | undefined}
		 */
		var mode = function(select) {
			return select.value === "" ? undefined : select.value === "true";
		};
		openDialog({
			"title": "New world",
			"body": [].concat(field("Name", name), field("Game", game), field("Seed (optional)", seed),
				make("div", {"className": "field-grid"}, [
					make("div", {}, field("Creative mode", creative)),
					make("div", {}, field("Damage", damage))
				])),
			"confirm": "Create world",
			"accept": function() {
				return lib.create({"name": name.value, "game": game.value, "seed": seed.value,
					"creative": mode(creative), "damage": mode(damage)});
			}
		}).then(function(world) {
			if (!world)
				return;
			ui.game.value = world.game;
			selectedWorld = world.name;
			return refreshWorlds();
		});
	}

	/** @param {string} from */
	function renameWorld(from) {
		var lib = library();
		var name = make("input", {"id": "luanti-rename-world", "maxlength": "48", "value": from,
			"autocomplete": "off", "spellcheck": "false"});
		openDialog({
			"title": "Rename world",
			"body": field("New name", name),
			"confirm": "Rename",
			"accept": function() { return lib.rename(from, name.value); }
		}).then(function(world) {
			if (!world)
				return;
			selectedWorld = world.name;
			return refreshWorlds();
		});
	}

	/** @param {string} name */
	function duplicateWorld(name) {
		runLibrary(function() {
			setLibraryStatus("Copying " + name + "…");
			return library().duplicate(name).then(function(world) {
				selectedWorld = world.name;
				setLibraryStatus("Copied to " + world.name + ".", "ready");
				return refreshWorlds();
			});
		});
	}

	/** @param {string} name */
	function deleteWorld(name) {
		var lib = library();
		openDialog({
			"title": "Delete " + name + "?",
			"body": make("p", {}, "This removes the world from this browser for good. " +
				"Export it first if you might want it back."),
			"confirm": "Delete world",
			"danger": true,
			"accept": function() { return lib.remove(name); }
		}).then(function(done) {
			if (done === null)
				return;
			if (selectedWorld === name)
				selectedWorld = null;
			setLibraryStatus("Deleted " + name + ".", "ready");
			return refreshWorlds();
		});
	}

	/**
	 * @param {Blob} blob
	 * @param {string} fileName
	 */
	function downloadBlob(blob, fileName) {
		var url = URL.createObjectURL(blob);
		var link = make("a", {"href": url, "download": fileName});
		document.body.append(link);
		link.click();
		link.remove();
		setTimeout(function() { URL.revokeObjectURL(url); }, 60000);
	}

	/** @param {string} name */
	function exportWorld(name) {
		var lib = library();
		var fileName = name + ".luantiworld";
		/**
		 * @param {number} done
		 * @param {number} total
		 */
		var progress = function(done, total) {
			setLibraryStatus("Exporting " + name + "… " + (total ? Math.floor(done / total * 100) : 0) + "%");
		};
		// The save picker needs the click's user activation, so it opens
		// before anything else is awaited.
		var picker = /** @type {any} */ (window)["showSaveFilePicker"];
		var target = typeof picker === "function" ?
			picker({"suggestedName": fileName, "types": [{"description": "Luanti world",
				"accept": {"application/zip": [".luantiworld"]}}]}).then(function(/** @type {any} */ handle) {
				return handle.createWritable();
			}, function(/** @type {any} */ error) {
				if (error && error.name === "AbortError")
					return "cancelled";
				return null; // Picker refused (e.g. in an iframe): fall back to a download.
			}) :
			Promise.resolve(null);
		runLibrary(function() {
			return target.then(function(/** @type {any} */ writable) {
				if (writable === "cancelled")
					return;
				progress(0, 1);
				return lib.exportWorld(name, {"writable": writable || undefined, "onProgress": progress})
					.then(function(blob) {
						if (blob)
							downloadBlob(blob, fileName);
						setLibraryStatus("Exported " + name + " as " + fileName + ".", "ready");
					});
			});
		});
	}

	/**
	 * @param {LuantiWorldArchivePlan} plan
	 * @param {string | null} source
	 */
	function planDetails(plan, source) {
		var rows = [
			["Game", plan.gameTitle + (plan.gameAvailable ? "" : " (not available here)")],
			["Size", sizeText(plan.archiveBytes) + " download, " + sizeText(plan.uncompressedBytes) + " unpacked"],
			["Files", String(plan.files)]
		];
		if (plan.exported)
			rows.push(["Exported", new Date(plan.exported).toLocaleString() +
				(plan.engine ? " · Luanti " + plan.engine : "")]);
		var mods = plan.content.filter(function(item) { return item.type === "mod"; });
		if (mods.length)
			rows.push(["Mods", mods.map(function(item) { return item.name; }).join(", ")]);
		if (source)
			rows.push(["From", source]);
		var list = make("dl");
		rows.forEach(function(row) {
			list.append(make("dt", {"text": row[0]}), make("dd", {"text": row[1]}));
		});
		return list;
	}

	// Shows what an archive contains and imports it only if the player
	// confirms. Resolves with the imported world or null.
	/**
	 * @param {Blob} blob
	 * @param {LuantiWorldArchivePlan} plan
	 * @param {{fileName?: string, source?: string | null, host?: string}} options
	 * @returns {Promise<LuantiWorld | null>}
	 */
	function confirmImport(blob, plan, options) {
		var lib = library();
		return lib.suggestName(plan.name).then(function(suggested) {
			var name = make("input", {"id": "luanti-import-name", "maxlength": "48", "value": suggested,
				"autocomplete": "off", "spellcheck": "false"});
			var body = [
				make("p", {}, options.host ?
					"A link asked to add a shared world to this browser. Nothing is saved unless you import it." :
					"Check the world before adding it to this browser.")
			].concat(field("Save as", name), planDetails(plan, options.host || null));
			if (plan.warnings.length)
				body.push(make("ul", {}, plan.warnings.map(function(text) { return make("li", {"text": text}); })));
			if (!plan.gameAvailable)
				body.push(make("p", {"className": "form-error"},
					"This world needs the game \"" + plan.game + "\", which is not available in this browser."));
			return openDialog({
				"title": options.host ? "Open shared world?" : "Import world?",
				"body": body,
				"confirm": plan.gameAvailable ? "Import world" : null,
				"cancel": plan.gameAvailable ? "Cancel" : "Close",
				"accept": function() {
					return lib.importArchive(blob, {
						"name": name.value,
						"fileName": options.fileName,
						"source": options.source,
						"onProgress": function(done, total) {
							ui.dialogConfirm.textContent = "Importing… " + (total ? Math.floor(done / total * 100) : 0) + "%";
						}
					});
				}
			});
		}).then(function(world) {
			if (!world)
				return null;
			ui.game.value = world.game;
			selectedWorld = world.name;
			setLibraryStatus("Imported " + world.name + ".", "ready");
			return refreshWorlds().then(function() { return world; });
		});
	}

	/** @param {File | undefined} file */
	function importFile(file) {
		var lib = library();
		if (!lib || !file || libraryBusy)
			return;
		runLibrary(function() {
			setLibraryStatus("Reading " + file.name + "…");
			return lib.inspectArchive(file, {"fileName": file.name}).then(function(plan) {
				setLibraryStatus("");
				return confirmImport(file, plan, {"fileName": file.name, "source": null});
			});
		});
	}

	ui.newWorld.addEventListener("click", newWorld);
	ui.importWorld.addEventListener("click", function() { ui.importFile.click(); });
	ui.importFile.addEventListener("change", function() {
		var file = ui.importFile.files && ui.importFile.files[0];
		ui.importFile.value = "";
		importFile(file);
	});

	/** @param {DragEvent} event */
	function hasFiles(event) {
		var types = event.dataTransfer && event.dataTransfer.types;
		return !!types && Array.prototype.indexOf.call(types, "Files") !== -1;
	}
	ui.localPanel.addEventListener("dragover", function(event) {
		if (!hasFiles(event) || state.started)
			return;
		event.preventDefault();
		ui.worldList.classList.add("is-dropping");
	});
	ui.localPanel.addEventListener("dragleave", function(event) {
		if (!ui.localPanel.contains(/** @type {Node} */ (event.relatedTarget)))
			ui.worldList.classList.remove("is-dropping");
	});
	ui.localPanel.addEventListener("drop", function(event) {
		ui.worldList.classList.remove("is-dropping");
		if (!hasFiles(event) || state.started)
			return;
		event.preventDefault();
		importFile(event.dataTransfer.files[0]);
	});

	// ?world=<https url> offers a shared world. It is downloaded for
	// inspection only, and imported once the player confirms.
	function openSharedWorldFromQuery() {
		var url = query.get("world");
		var lib = library();
		if (!url || !lib)
			return;
		var forget = function() {
			var clean = new URL(location.href);
			clean.searchParams.delete("world");
			history.replaceState(history.state, "", clean.href);
		};
		runLibrary(function() {
			setLibraryStatus("Downloading a shared world…");
			return lib.fetchShared(url, {"onProgress": function(done, total) {
				setLibraryStatus("Downloading a shared world… " + sizeText(done) + (total ? " of " + sizeText(total) : ""));
			}}).then(function(shared) {
				setLibraryStatus("");
				return confirmImport(shared.blob, shared.plan,
					{"fileName": shared.fileName, "source": shared.url, "host": shared.host});
			}).catch(function(error) {
				throw new Error("Could not open the shared world: " + messageOf(error));
			}).finally(forget);
		});
	}

	// The saved-worlds list follows the storage service: it is drawn once
	// storage has hydrated, and again after every library operation (worlds.js
	// marks those events with `library`). launcher.js shows the status line.
	window.addEventListener("luanti:persistence", function(event) {
		/** @type {Partial<LuantiPersistenceEvent>} */
		var detail = event.detail || {};
		if (!state.started && !detail.fatal && detail.state !== "loading") {
			if (!libraryLoaded) {
				libraryLoaded = true;
				refreshWorlds().then(openSharedWorldFromQuery);
			} else if (detail.library) {
				refreshWorlds();
			}
		}
		if (state.started && detail.state === "saving" && thumbnail.pending &&
				Date.now() - thumbnail.armedAt > 3000)
			thumbnail.requested = true;
	});

	// Called on Start for a local session: the selected world, or the
	// game's default world (named after the game) created on first use.
	/**
	 * @param {LuantiSession} session
	 * @returns {Promise<void>}
	 */
	function prepareWorld(session) {
		var lib = library();
		if (!lib) {
			session.world = session.world || session.game;
			return Promise.resolve();
		}
		var name = session.world;
		var made = name ? Promise.resolve() :
			lib.create({"name": session.game, "game": session.game}).catch(function(error) {
				// A directory the engine created but never finished (no
				// world.mt) is reused as is; the engine completes it.
				if (error && error.code !== "exists")
					throw error;
			});
		name = name || session.game;
		session.world = name;
		return made.then(function() {
			return lib.markPlayed(name).catch(function() {});
		});
	}

	// --- thumbnails

	// The first save after the player has been in the world for a few
	// seconds (or 20 s, whichever is first) asks for the next presented frame
	// to be kept as the world's thumbnail.
	function armThumbnail() {
		if (thumbnail.armedAt || !state.currentSession || state.currentSession.mode !== "local" || !library())
			return;
		thumbnail.pending = true;
		thumbnail.armedAt = Date.now();
		thumbnail.timer = setTimeout(function() { thumbnail.requested = thumbnail.pending; }, 20000);
	}

	function captureThumbnail() {
		if (!thumbnail.requested || !thumbnail.pending)
			return;
		var source = Module.canvas;
		if (!source || !source.width || !source.height)
			return;
		var out = document.createElement("canvas");
		out.width = 320;
		out.height = 180;
		var context = out.getContext("2d");
		var scale = Math.max(out.width / source.width, out.height / source.height);
		var width = out.width / scale;
		var height = out.height / scale;
		try {
			context.drawImage(source, (source.width - width) / 2, (source.height - height) / 2, width, height,
				0, 0, out.width, out.height);
			// A WebGL drawing buffer that was already presented reads back
			// blank; try again on a later frame rather than keep a black tile.
			var pixels = context.getImageData(0, 0, out.width, out.height).data;
			var low = 255;
			var high = 0;
			for (var i = 0; i < pixels.length; i += 4 * 211) {
				var light = (pixels[i] + pixels[i + 1] + pixels[i + 2]) / 3;
				low = Math.min(low, light);
				high = Math.max(high, light);
			}
			if (high - low < 12) {
				if (++thumbnail.attempts > 600)
					thumbnail.pending = false;
				return;
			}
		} catch (error) {
			thumbnail.pending = false;
			shell.appendLog("library", ["thumbnail capture failed: " + messageOf(error)]);
			return;
		}
		thumbnail.pending = false;
		clearTimeout(thumbnail.timer);
		var world = state.currentSession.world;
		out.toBlob(function(blob) {
			if (blob)
				library().saveThumbnail(world, blob).catch(function(error) {
					shell.appendLog("library", ["thumbnail save failed: " + messageOf(error)]);
				});
		}, "image/jpeg", 0.82);
	}

	shell.on("playing", armThumbnail);
	shell.on("framepresented", captureThumbnail);
	shell.frameHookWanted = function() {
		return thumbnail.pending;
	};

	shell.library = {
		refresh: refreshWorlds,
		selectedWorld: function() { return selectedWorld; },
		prepareWorld: prepareWorld
	};
})();
