// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 The Luanti Contributors

#pragma once

// SQLite storage for browser worlds on the Origin Private File System.
//
// Under Emscripten's JavaScript filesystem every read and write a worker makes
// is a synchronous call run on the browser main thread. For SQLite that meant
// the server and emerge threads waited on the thread that also drains WebGL,
// and the whole map.sqlite lived in the Wasm heap and was rewritten into
// IndexedDB on every sync.
//
// This VFS keeps SQLite on its POSIX code path but sends the world databases
// (worlds/<world>/*.sqlite and their journals) to OPFS through
// FileSystemSyncAccessHandle objects owned by one dedicated thread. Callers
// block on that thread, never on the browser main thread. A commit is durable
// when SQLite's own xSync (handle.flush()) returns; nothing is rewritten.
//
// Which store a world uses is recorded in the world directory itself: a world
// whose databases live in OPFS has a small marker file (MARKER_FILE) naming a
// random storage id, and its files are OPFS_ROOT/<id>/<name>. The marker
// travels with the world directory (rename needs no OPFS work) and a deleted
// and re-created world of the same name never picks up the old map. Worlds
// without a marker whose databases are in the JavaScript filesystem keep using
// it until migrate_world() has copied and checked them.
//
// Everything else (settings, world.mt, small files) stays where it was.
//
// The implementation is self-contained (SQLite and Emscripten only) so that
// util/wasm/storage_spike.cpp can build it without the engine.

#ifdef __EMSCRIPTEN__

#include <functional>
#include <string>

namespace sqlite_opfs {

// Directory under the OPFS root that holds one directory per storage id.
// client/web/storage.js uses the same name.
constexpr const char *OPFS_ROOT = "luanti-worlds";
// Marker inside a world directory: one line, the 32 hex digit storage id.
constexpr const char *MARKER_FILE = "web_opfs_id.txt";
// Name the VFS is registered under (it is also made the default VFS).
constexpr const char *VFS_NAME = "luanti-opfs";

enum class State {
	NotStarted,
	Disabled,    // the page asked for the old backend (?storage=idbfs)
	Unsupported, // no FileSystemSyncAccessHandle in workers
	Failed,      // OPFS exists but could not be opened
	Ready,
};

const char *state_name(State state);

struct Config {
	// Absolute path of the worlds directory in the JavaScript filesystem,
	// without a trailing slash, e.g. /home/web_user/.luanti/worlds.
	std::string worlds_dir;
	// false keeps every database where it is (no OPFS thread is started).
	bool enabled = true;
	// level: 0 info, 1 warning, 2 error.
	std::function<void(int level, const std::string &message)> log;
	// Called after a marker file was written or a legacy database removed, so
	// the small-file sync picks the change up.
	std::function<void()> small_files_changed;
};

// Starts the OPFS thread and registers the VFS as SQLite's default. Must run
// on a worker (not the browser main thread) before any database is opened.
// Safe to call once; later calls return the first result.
State init(const Config &config);
State state();

// True if `path` exists, asking the store it would be opened from.
bool file_exists(const std::string &path);

// True if the world directory has a valid marker.
bool world_uses_opfs(const std::string &world_dir);

struct MigrationProgress {
	std::string world;
	std::string file;
	double fraction; // 0..1 within the file
};

enum class MigrationResult {
	NothingToDo,  // already on OPFS, or no database in the JS filesystem
	Migrated,     // copied, checked, marker written, old copy removed
	Failed,       // nothing changed; the world keeps the old backend
};

// Copies every *.sqlite in `world_dir` from the JavaScript filesystem into a
// fresh OPFS storage id with the SQLite backup API, runs PRAGMA
// integrity_check on each copy, and only if every copy passes writes the
// marker and removes the old files. Runs on the calling (worker) thread and
// reports `error` on failure.
MigrationResult migrate_world(const std::string &world_dir,
		const std::function<void(const MigrationProgress &)> &progress,
		std::string *error);

} // namespace sqlite_opfs

#endif // __EMSCRIPTEN__
