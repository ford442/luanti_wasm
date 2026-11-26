// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 The Luanti Contributors

#ifdef __EMSCRIPTEN__

#include "sqlite3_opfs_vfs.h"

#include <sqlite3.h>

#include <emscripten.h>
#include <emscripten/eventloop.h>
#include <emscripten/proxying.h>
#include <emscripten/threading.h>

#include <algorithm>
#include <atomic>
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <dirent.h>
#include <mutex>
#include <pthread.h>
#include <sys/stat.h>
#include <unistd.h>
#include <unordered_map>
#include <vector>

namespace sqlite_opfs {
namespace {

// ---------------------------------------------------------------- OPFS thread
//
// One request to the OPFS thread. The layout is read by opfs_js_op below; keep
// the offsets in sync with the static_asserts.
struct Op {
	std::int32_t kind = 0;
	std::int32_t handle = 0;
	std::uint32_t ptr = 0;
	std::int32_t len = 0;
	double offset = 0;
	const char *path = nullptr;
	std::int32_t flags = 0;
	std::int32_t result = 0;
	std::int32_t pad = 0;
	double value = 0;
};
static_assert(offsetof(Op, kind) == 0, "opfs_js_op layout");
static_assert(offsetof(Op, handle) == 4, "opfs_js_op layout");
static_assert(offsetof(Op, ptr) == 8, "opfs_js_op layout");
static_assert(offsetof(Op, len) == 12, "opfs_js_op layout");
static_assert(offsetof(Op, offset) == 16, "opfs_js_op layout");
static_assert(offsetof(Op, path) == 24, "opfs_js_op layout");
static_assert(offsetof(Op, flags) == 28, "opfs_js_op layout");
static_assert(offsetof(Op, result) == 32, "opfs_js_op layout");
static_assert(offsetof(Op, value) == 40, "opfs_js_op layout");

enum OpKind : std::int32_t {
	OP_INIT = 1,
	OP_OPEN = 2,     // path, flags bit 0 = create -> handle
	OP_CLOSE = 3,    // handle
	OP_READ = 4,     // handle, ptr, len, offset -> bytes
	OP_WRITE = 5,    // handle, ptr, len, offset -> bytes
	OP_SIZE = 6,     // handle -> value
	OP_TRUNCATE = 7, // handle, offset
	OP_FLUSH = 8,    // handle
	OP_DELETE = 9,   // path
	OP_EXISTS = 10,  // path -> 0/1
	OP_REMOVE_TREE = 11, // path (directory)
};

// Results below zero.
constexpr int ERR_NOT_FOUND = -1;
constexpr int ERR_LOCKED = -2;    // another tab (or this one) holds the file
constexpr int ERR_IO = -3;
constexpr int ERR_QUOTA = -4;
constexpr int ERR_NO_THREAD = -5; // called from the browser main thread

} // namespace
} // namespace sqlite_opfs

extern "C" EMSCRIPTEN_KEEPALIVE void luanti_opfs_finish(em_proxying_ctx *ctx)
{
	emscripten_proxy_finish(ctx);
}

// Runs on the OPFS thread. Synchronous access handle calls finish at once;
// anything that needs a promise (opening, deleting, looking a file up) is
// chained so that two opens of the same file never race for its one handle.
// Only this thread touches the OPFS tree while the engine runs, so file
// existence is cached.
EM_JS(void, opfs_js_op, (em_proxying_ctx *ctx, void *op), {
	var S = globalThis["__luantiOpfs"];
	if (!S) {
		S = globalThis["__luantiOpfs"] = {
			root: null, dirs: new Map(), files: new Map(), handles: new Map(),
			known: new Map(), next: 1, chain: Promise.resolve()
		};
	}
	var kind = HEAP32[op >> 2];
	var handle = HEAP32[(op + 4) >> 2];
	var ptr = HEAPU32[(op + 8) >> 2];
	var len = HEAP32[(op + 12) >> 2];
	var offset = HEAPF64[(op + 16) >> 3];
	var pathPtr = HEAPU32[(op + 24) >> 2];
	var path = pathPtr ? UTF8ToString(pathPtr) : "";
	var flags = HEAP32[(op + 28) >> 2];

	function done(result, value) {
		HEAP32[(op + 32) >> 2] = result;
		if (value !== undefined)
			HEAPF64[(op + 40) >> 3] = value;
		_luanti_opfs_finish(ctx);
	}
	function code(error) {
		var name = error && error.name;
		if (name === "NotFoundError" || name === "TypeMismatchError")
			return -1;
		if (name === "NoModificationAllowedError" || name === "InvalidStateError")
			return -2;
		if (name === "QuotaExceededError")
			return -4;
		return -3;
	}
	function report(what, error) {
		console.warn("Luanti OPFS: " + what + " failed: " +
			(error && error.name) + ": " + (error && error.message));
	}
	function serial(task) {
		var next = S.chain.then(task);
		S.chain = next.catch(function() {});
		return next;
	}
	async function directory(parts, create) {
		var current = S.root;
		var key = "";
		for (var i = 0; i < parts.length; i++) {
			key += "/" + parts[i];
			var cached = S.dirs.get(key);
			if (!cached) {
				cached = await current.getDirectoryHandle(parts[i], {"create": create});
				S.dirs.set(key, cached);
			}
			current = cached;
		}
		return current;
	}
	function split(full) {
		var parts = full.split("/");
		var name = parts.pop();
		return {parts: parts, name: name};
	}
	function forget(prefix) {
		S.dirs.forEach(function(_, key) {
			if (key === "/" + prefix || key.indexOf("/" + prefix + "/") === 0)
				S.dirs.delete(key);
		});
		S.known.forEach(function(_, key) {
			if (key.indexOf(prefix + "/") === 0)
				S.known.delete(key);
		});
	}

	var entry = handle ? S.handles.get(handle) : null;
	switch (kind) {
	case 1: // init
		serial(async function() {
			if (typeof FileSystemFileHandle === "undefined" ||
					typeof FileSystemFileHandle.prototype.createSyncAccessHandle !== "function" ||
					typeof navigator === "undefined" || !navigator.storage ||
					typeof navigator.storage.getDirectory !== "function")
				return 2;
			S.root = await navigator.storage.getDirectory();
			var base = await directory([path], true);
			var probe = await base.getFileHandle(".luanti-probe", {"create": true});
			var access = await probe.createSyncAccessHandle();
			access.close();
			await base.removeEntry(".luanti-probe");
			return 1;
		}).then(function(result) { done(result); },
			function(error) { report("init", error); done(3); });
		return;
	case 2: // open
		serial(async function() {
			var file = S.files.get(path);
			if (!file) {
				if (!(flags & 1) && S.known.get(path) === false)
					return -1;
				var where = split(path);
				var dir = await directory(where.parts, !!(flags & 1));
				var fileHandle = await dir.getFileHandle(where.name, {"create": !!(flags & 1)});
				file = {access: await fileHandle.createSyncAccessHandle(), refs: 0, path: path};
				S.files.set(path, file);
				S.known.set(path, true);
			}
			file.refs++;
			var id = S.next++;
			S.handles.set(id, file);
			return id;
		}).then(function(result) { done(result); }, function(error) {
			var result = code(error);
			if (result === -1)
				S.known.set(path, false);
			else
				report("open " + path, error);
			done(result);
		});
		return;
	case 3: // close
		if (entry) {
			S.handles.delete(handle);
			if (--entry.refs === 0) {
				S.files.delete(entry.path);
				try {
					entry.access.close();
				} catch (error) {
					report("close " + entry.path, error);
				}
			}
		}
		done(0);
		return;
	case 4: // read
	case 5: // write
		if (!entry) {
			done(-3);
			return;
		}
		try {
			var view = HEAPU8.subarray(ptr, ptr + len);
			done(kind === 4 ? entry.access.read(view, {"at": offset}) :
				entry.access.write(view, {"at": offset}));
		} catch (error) {
			report((kind === 4 ? "read " : "write ") + entry.path, error);
			done(code(error));
		}
		return;
	case 6: // size
	case 7: // truncate
	case 8: // flush
		if (!entry) {
			done(-3);
			return;
		}
		try {
			if (kind === 6) {
				done(0, entry.access.getSize());
				return;
			}
			if (kind === 7)
				entry.access.truncate(offset);
			else
				entry.access.flush();
			done(0);
		} catch (error) {
			report((kind === 7 ? "truncate " : "flush ") + entry.path, error);
			done(code(error));
		}
		return;
	case 9: // delete
		serial(async function() {
			if (S.files.has(path))
				return -2;
			if (S.known.get(path) === false)
				return -1;
			var where = split(path);
			var dir = await directory(where.parts, false);
			await dir.removeEntry(where.name);
			S.known.set(path, false);
			return 0;
		}).then(function(result) { done(result); }, function(error) {
			var result = code(error);
			if (result === -1)
				S.known.set(path, false);
			else
				report("delete " + path, error);
			done(result);
		});
		return;
	case 10: // exists
		serial(async function() {
			if (S.files.has(path))
				return 1;
			var known = S.known.get(path);
			if (known !== undefined)
				return known ? 1 : 0;
			var where = split(path);
			try {
				var dir = await directory(where.parts, false);
				await dir.getFileHandle(where.name);
				S.known.set(path, true);
				return 1;
			} catch (error) {
				if (code(error) !== -1)
					throw error;
				S.known.set(path, false);
				return 0;
			}
		}).then(function(result) { done(result); }, function(error) {
			report("access " + path, error);
			done(code(error));
		});
		return;
	case 11: // remove a directory tree
		serial(async function() {
			var open = false;
			S.files.forEach(function(_, key) {
				if (key.indexOf(path + "/") === 0)
					open = true;
			});
			if (open)
				return -2;
			var where = split(path);
			var dir = await directory(where.parts, false);
			await dir.removeEntry(where.name, {"recursive": true});
			forget(path);
			return 0;
		}).then(function(result) { done(result); }, function(error) {
			forget(path);
			var result = code(error);
			if (result !== -1)
				report("remove " + path, error);
			done(result);
		});
		return;
	default:
		done(-3);
	}
});

namespace sqlite_opfs {
namespace {

Config g_config;
std::atomic<State> g_state{State::NotStarted};
std::mutex g_init_mutex;
em_proxying_queue *g_queue = nullptr;
pthread_t g_thread;
sqlite3_vfs *g_base = nullptr;
sqlite3_vfs g_vfs;

std::mutex g_thread_mutex;
std::condition_variable g_thread_cv;
bool g_thread_started = false;

void log(int level, const std::string &message)
{
	if (g_config.log)
		g_config.log(level, message);
	else
		emscripten_log(level >= 2 ? EM_LOG_ERROR : EM_LOG_CONSOLE, "%s",
				message.c_str());
}

void *thread_main(void *)
{
	// Return to the worker's event loop instead of exiting: every request is
	// proxied here and promise-based ones finish on a later turn.
	emscripten_runtime_keepalive_push();
	{
		std::lock_guard<std::mutex> lock(g_thread_mutex);
		g_thread_started = true;
	}
	g_thread_cv.notify_all();
	return nullptr;
}

void run_op(em_proxying_ctx *ctx, void *arg)
{
	opfs_js_op(ctx, arg);
}

int call(Op &op)
{
	// Blocking the browser main thread on the OPFS thread is not allowed (and
	// the launcher never opens a database there).
	if (emscripten_is_main_browser_thread())
		return ERR_NO_THREAD;
	if (!emscripten_proxy_sync_with_ctx(g_queue, g_thread, run_op, &op))
		return ERR_IO;
	return op.result;
}

// ------------------------------------------------------------------ routing

bool is_hex_id(const std::string &id)
{
	if (id.size() != 32)
		return false;
	return std::all_of(id.begin(), id.end(), [](char c) {
		return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f');
	});
}

std::string new_id()
{
	unsigned char bytes[16];
	if (getentropy(bytes, sizeof(bytes)) != 0) {
		// getentropy uses crypto.getRandomValues and does not fail in a
		// browser; fall back to the clock so an id is still produced.
		double now = emscripten_get_now();
		std::memcpy(bytes, &now, sizeof(now));
		std::memcpy(bytes + 8, &now, sizeof(now));
	}
	static const char digits[] = "0123456789abcdef";
	std::string id;
	for (unsigned char byte : bytes) {
		id += digits[byte >> 4];
		id += digits[byte & 15];
	}
	return id;
}

bool js_fs_exists(const std::string &path)
{
	struct stat info;
	return stat(path.c_str(), &info) == 0;
}

std::string read_marker(const std::string &world_dir)
{
	std::FILE *file = std::fopen((world_dir + "/" + MARKER_FILE).c_str(), "rb");
	if (!file)
		return "";
	char buffer[80] = {};
	size_t read = std::fread(buffer, 1, sizeof(buffer) - 1, file);
	std::fclose(file);
	std::string id(buffer, read);
	while (!id.empty() && (id.back() == '\n' || id.back() == '\r' || id.back() == ' '))
		id.pop_back();
	return is_hex_id(id) ? id : "";
}

bool write_marker(const std::string &world_dir, const std::string &id)
{
	const std::string path = world_dir + "/" + MARKER_FILE;
	const std::string temp = path + ".tmp";
	std::FILE *file = std::fopen(temp.c_str(), "wb");
	if (!file)
		return false;
	const std::string line = id + "\n";
	bool ok = std::fwrite(line.data(), 1, line.size(), file) == line.size();
	ok = std::fclose(file) == 0 && ok;
	if (!ok || std::rename(temp.c_str(), path.c_str()) != 0) {
		std::remove(temp.c_str());
		return false;
	}
	if (g_config.small_files_changed)
		g_config.small_files_changed();
	return true;
}

// A world database path is <worlds_dir>/<world>/<name>.sqlite[suffix], where
// suffix is one of SQLite's own companion files. Anything else (temporary
// files, client mod storage, nested directories) stays on the base VFS.
struct WorldPath {
	std::string world_dir;
	std::string file;    // as asked for, e.g. map.sqlite-journal
	std::string main;    // full path of the main database, e.g. .../map.sqlite
};

bool parse_world_path(const char *raw, WorldPath *out)
{
	if (!raw || g_config.worlds_dir.empty())
		return false;
	const std::string path(raw);
	const std::string prefix = g_config.worlds_dir + "/";
	if (path.compare(0, prefix.size(), prefix) != 0)
		return false;
	const std::string rest = path.substr(prefix.size());
	const auto slash = rest.find('/');
	if (slash == std::string::npos || slash == 0 ||
			rest.find('/', slash + 1) != std::string::npos)
		return false;
	const std::string world = rest.substr(0, slash);
	const std::string file = rest.substr(slash + 1);
	if (world[0] == '.' || file.empty())
		return false;
	const auto ext = file.find(".sqlite");
	if (ext == std::string::npos || ext == 0)
		return false;
	const std::string suffix = file.substr(ext + 7);
	if (!(suffix.empty() || suffix == "-journal" || suffix == "-wal" ||
			suffix == "-shm" || suffix.compare(0, 3, "-mj") == 0))
		return false;
	out->world_dir = g_config.worlds_dir + "/" + world;
	out->file = file;
	out->main = out->world_dir + "/" + file.substr(0, ext + 7);
	return true;
}

enum class Route { Base, Opfs, Unavailable };

struct Resolved {
	Route route = Route::Base;
	std::string key;  // OPFS path, OPFS_ROOT/<id>/<file>
	std::string main; // main database path (for the open-database table)
	std::string id;
};

std::mutex g_route_mutex;
// Main databases currently open on OPFS, so their journals resolve without
// reading the marker again (SQLite looks for a hot journal on every read
// transaction).
struct OpenDb {
	std::string id;
	int refs = 0;
};
std::unordered_map<std::string, OpenDb> g_open;
// World directories being migrated: their marker is not written yet.
std::unordered_map<std::string, std::string> g_pending;
std::mutex g_create_mutex;

Resolved resolve(const char *raw, bool create_main)
{
	Resolved out;
	WorldPath where;
	if (!parse_world_path(raw, &where))
		return out;
	out.main = where.main;
	const State state = g_state.load(std::memory_order_acquire);

	std::string id;
	{
		std::lock_guard<std::mutex> lock(g_route_mutex);
		auto open = g_open.find(where.main);
		if (open != g_open.end())
			id = open->second.id;
		auto pending = g_pending.find(where.world_dir);
		if (id.empty() && pending != g_pending.end())
			id = pending->second;
	}
	// Journals of a database on the old backend never consult the marker
	// unless OPFS is usable; that keeps their hot-journal checks as cheap as
	// they were.
	if (id.empty() && (state == State::Ready || create_main))
		id = read_marker(where.world_dir);

	if (id.empty() && state == State::Ready && create_main &&
			!js_fs_exists(where.main)) {
		std::lock_guard<std::mutex> lock(g_create_mutex);
		id = read_marker(where.world_dir);
		if (id.empty()) {
			id = new_id();
			if (!write_marker(where.world_dir, id)) {
				log(2, "OPFS: could not write " + where.world_dir + "/" +
						MARKER_FILE + "; using the old backend");
				return out;
			}
			log(0, "OPFS: new world storage " + id + " for " + where.world_dir);
		}
	}

	if (id.empty())
		return out;
	out.id = id;
	out.key = std::string(OPFS_ROOT) + "/" + id + "/" + where.file;
	out.route = state == State::Ready ? Route::Opfs : Route::Unavailable;
	return out;
}

// --------------------------------------------------------------- file locks
//
// The same rules os_unix.c applies per inode, for connections in this page.
// Another tab cannot open the file at all: an OPFS sync access handle is
// exclusive.
struct FileImpl;

struct LockState {
	int shared = 0;
	FileImpl *reserved = nullptr;
	FileImpl *pending = nullptr;
	FileImpl *exclusive = nullptr;
	int refs = 0;
};

std::mutex g_lock_mutex;
std::unordered_map<std::string, LockState> g_locks;

struct FileImpl {
	int handle = 0;
	int lock = SQLITE_LOCK_NONE;
	bool delete_on_close = false;
	bool main_db = false;
	std::string key;
	std::string main;
	LockState *locks = nullptr;
};

struct OpfsFile {
	sqlite3_file base;
	FileImpl *impl;
};

FileImpl *impl_of(sqlite3_file *file)
{
	return reinterpret_cast<OpfsFile *>(file)->impl;
}

int io_unlock(sqlite3_file *file, int level);

int io_close(sqlite3_file *file)
{
	FileImpl *impl = impl_of(file);
	io_unlock(file, SQLITE_LOCK_NONE);
	Op op;
	op.kind = OP_CLOSE;
	op.handle = impl->handle;
	call(op);
	int rc = SQLITE_OK;
	if (impl->delete_on_close) {
		Op del;
		del.kind = OP_DELETE;
		del.path = impl->key.c_str();
		if (call(del) < 0 && del.result != ERR_NOT_FOUND)
			rc = SQLITE_IOERR_DELETE;
	}
	{
		std::lock_guard<std::mutex> lock(g_lock_mutex);
		auto it = g_locks.find(impl->key);
		if (it != g_locks.end() && --it->second.refs == 0)
			g_locks.erase(it);
	}
	if (impl->main_db) {
		std::lock_guard<std::mutex> lock(g_route_mutex);
		auto it = g_open.find(impl->main);
		if (it != g_open.end() && --it->second.refs <= 0)
			g_open.erase(it);
	}
	delete impl;
	reinterpret_cast<OpfsFile *>(file)->impl = nullptr;
	return rc;
}

int io_read(sqlite3_file *file, void *buffer, int amount, sqlite3_int64 offset)
{
	Op op;
	op.kind = OP_READ;
	op.handle = impl_of(file)->handle;
	op.ptr = static_cast<std::uint32_t>(reinterpret_cast<std::uintptr_t>(buffer));
	op.len = amount;
	op.offset = static_cast<double>(offset);
	const int read = call(op);
	if (read < 0)
		return SQLITE_IOERR_READ;
	if (read < amount) {
		std::memset(static_cast<char *>(buffer) + read, 0, amount - read);
		return SQLITE_IOERR_SHORT_READ;
	}
	return SQLITE_OK;
}

int io_write(sqlite3_file *file, const void *buffer, int amount,
		sqlite3_int64 offset)
{
	Op op;
	op.kind = OP_WRITE;
	op.handle = impl_of(file)->handle;
	op.ptr = static_cast<std::uint32_t>(reinterpret_cast<std::uintptr_t>(buffer));
	op.len = amount;
	op.offset = static_cast<double>(offset);
	const int written = call(op);
	if (written == ERR_QUOTA)
		return SQLITE_FULL;
	return written == amount ? SQLITE_OK : SQLITE_IOERR_WRITE;
}

int io_truncate(sqlite3_file *file, sqlite3_int64 size)
{
	Op op;
	op.kind = OP_TRUNCATE;
	op.handle = impl_of(file)->handle;
	op.offset = static_cast<double>(size);
	return call(op) == 0 ? SQLITE_OK : SQLITE_IOERR_TRUNCATE;
}

int io_sync(sqlite3_file *file, int)
{
	Op op;
	op.kind = OP_FLUSH;
	op.handle = impl_of(file)->handle;
	return call(op) == 0 ? SQLITE_OK : SQLITE_IOERR_FSYNC;
}

int io_file_size(sqlite3_file *file, sqlite3_int64 *size)
{
	Op op;
	op.kind = OP_SIZE;
	op.handle = impl_of(file)->handle;
	if (call(op) != 0)
		return SQLITE_IOERR_FSTAT;
	*size = static_cast<sqlite3_int64>(op.value);
	return SQLITE_OK;
}

int io_lock(sqlite3_file *file, int level)
{
	FileImpl *impl = impl_of(file);
	if (impl->lock >= level)
		return SQLITE_OK;
	std::lock_guard<std::mutex> lock(g_lock_mutex);
	LockState &state = *impl->locks;
	if (level == SQLITE_LOCK_SHARED) {
		if (state.pending || state.exclusive)
			return SQLITE_BUSY;
		state.shared++;
		impl->lock = SQLITE_LOCK_SHARED;
		return SQLITE_OK;
	}
	if (level == SQLITE_LOCK_RESERVED) {
		if (state.reserved && state.reserved != impl)
			return SQLITE_BUSY;
		state.reserved = impl;
		impl->lock = SQLITE_LOCK_RESERVED;
		return SQLITE_OK;
	}
	// EXCLUSIVE, by way of PENDING: once pending, no new SHARED lock is
	// granted, and the lock is exclusive when this is the only reader left.
	if ((state.pending && state.pending != impl) ||
			(state.reserved && state.reserved != impl))
		return SQLITE_BUSY;
	state.pending = impl;
	impl->lock = SQLITE_LOCK_PENDING;
	if (state.shared > 1)
		return SQLITE_BUSY;
	state.exclusive = impl;
	impl->lock = SQLITE_LOCK_EXCLUSIVE;
	return SQLITE_OK;
}

int io_unlock(sqlite3_file *file, int level)
{
	FileImpl *impl = impl_of(file);
	if (impl->lock <= level)
		return SQLITE_OK;
	std::lock_guard<std::mutex> lock(g_lock_mutex);
	LockState &state = *impl->locks;
	if (impl->lock > SQLITE_LOCK_SHARED) {
		if (state.reserved == impl)
			state.reserved = nullptr;
		if (state.pending == impl)
			state.pending = nullptr;
		if (state.exclusive == impl)
			state.exclusive = nullptr;
	}
	if (level == SQLITE_LOCK_NONE && impl->lock >= SQLITE_LOCK_SHARED)
		state.shared--;
	impl->lock = level;
	return SQLITE_OK;
}

int io_check_reserved(sqlite3_file *file, int *out)
{
	FileImpl *impl = impl_of(file);
	std::lock_guard<std::mutex> lock(g_lock_mutex);
	const LockState &state = *impl->locks;
	*out = (state.reserved || state.pending || state.exclusive) ? 1 : 0;
	return SQLITE_OK;
}

int io_file_control(sqlite3_file *, int, void *)
{
	return SQLITE_NOTFOUND;
}

int io_sector_size(sqlite3_file *)
{
	return 4096;
}

int io_device_characteristics(sqlite3_file *)
{
	return 0;
}

const sqlite3_io_methods g_io = {
	1,
	io_close,
	io_read,
	io_write,
	io_truncate,
	io_sync,
	io_file_size,
	io_lock,
	io_unlock,
	io_check_reserved,
	io_file_control,
	io_sector_size,
	io_device_characteristics,
	nullptr, nullptr, nullptr, nullptr, nullptr, nullptr,
};

// ----------------------------------------------------------------- the VFS

int vfs_open(sqlite3_vfs *, const char *name, sqlite3_file *file, int flags,
		int *out_flags)
{
	file->pMethods = nullptr;
	const bool main_db = (flags & SQLITE_OPEN_MAIN_DB) != 0;
	Resolved where = resolve(name,
			main_db && (flags & SQLITE_OPEN_CREATE) != 0);
	if (where.route == Route::Base)
		return g_base->xOpen(g_base, name, file, flags, out_flags);
	if (where.route == Route::Unavailable) {
		log(2, std::string("OPFS: ") + name + " is stored in OPFS, which is "
				"not available in this browser session (" +
				state_name(g_state.load()) + ")");
		return SQLITE_CANTOPEN;
	}

	Op op;
	op.kind = OP_OPEN;
	op.path = where.key.c_str();
	op.flags = (flags & SQLITE_OPEN_CREATE) ? 1 : 0;
	const int handle = call(op);
	if (handle <= 0) {
		if (handle == ERR_LOCKED)
			log(2, std::string("OPFS: ") + name + " is in use, probably by "
					"another tab of this page");
		else if (handle != ERR_NOT_FOUND)
			log(2, std::string("OPFS: could not open ") + name);
		return SQLITE_CANTOPEN;
	}

	FileImpl *impl = new FileImpl();
	impl->handle = handle;
	impl->delete_on_close = (flags & SQLITE_OPEN_DELETEONCLOSE) != 0;
	impl->main_db = main_db;
	impl->key = where.key;
	impl->main = where.main;
	{
		std::lock_guard<std::mutex> lock(g_lock_mutex);
		LockState &state = g_locks[where.key];
		state.refs++;
		impl->locks = &state;
	}
	if (main_db) {
		std::lock_guard<std::mutex> lock(g_route_mutex);
		OpenDb &open = g_open[where.main];
		open.id = where.id;
		open.refs++;
	}
	reinterpret_cast<OpfsFile *>(file)->impl = impl;
	file->pMethods = &g_io;
	if (out_flags)
		*out_flags = flags;
	return SQLITE_OK;
}

int vfs_delete(sqlite3_vfs *, const char *name, int sync_dir)
{
	Resolved where = resolve(name, false);
	if (where.route == Route::Base)
		return g_base->xDelete(g_base, name, sync_dir);
	if (where.route == Route::Unavailable)
		return SQLITE_IOERR_DELETE;
	Op op;
	op.kind = OP_DELETE;
	op.path = where.key.c_str();
	const int result = call(op);
	if (result == 0)
		return SQLITE_OK;
	return result == ERR_NOT_FOUND ? SQLITE_IOERR_DELETE_NOENT : SQLITE_IOERR_DELETE;
}

int vfs_access(sqlite3_vfs *, const char *name, int flags, int *out)
{
	Resolved where = resolve(name, false);
	if (where.route == Route::Base)
		return g_base->xAccess(g_base, name, flags, out);
	*out = 0;
	if (where.route == Route::Unavailable)
		return SQLITE_IOERR_ACCESS;
	Op op;
	op.kind = OP_EXISTS;
	op.path = where.key.c_str();
	const int result = call(op);
	if (result < 0)
		return SQLITE_IOERR_ACCESS;
	*out = result;
	return SQLITE_OK;
}

int vfs_full_pathname(sqlite3_vfs *, const char *name, int size, char *out)
{
	return g_base->xFullPathname(g_base, name, size, out);
}

int vfs_randomness(sqlite3_vfs *, int size, char *out)
{
	return g_base->xRandomness(g_base, size, out);
}

int vfs_sleep(sqlite3_vfs *, int microseconds)
{
	return g_base->xSleep(g_base, microseconds);
}

int vfs_current_time(sqlite3_vfs *, double *out)
{
	return g_base->xCurrentTime(g_base, out);
}

int vfs_last_error(sqlite3_vfs *, int size, char *out)
{
	return g_base->xGetLastError ? g_base->xGetLastError(g_base, size, out) : 0;
}

int vfs_current_time_int64(sqlite3_vfs *, sqlite3_int64 *out)
{
	if (g_base->iVersion >= 2 && g_base->xCurrentTimeInt64)
		return g_base->xCurrentTimeInt64(g_base, out);
	double now = 0;
	int rc = g_base->xCurrentTime(g_base, &now);
	*out = static_cast<sqlite3_int64>(now * 86400000.0);
	return rc;
}

State start_thread()
{
	g_queue = em_proxying_queue_create();
	if (!g_queue)
		return State::Failed;
	pthread_attr_t attr;
	pthread_attr_init(&attr);
	pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
	const int rc = pthread_create(&g_thread, &attr, thread_main, nullptr);
	pthread_attr_destroy(&attr);
	if (rc != 0) {
		log(2, "OPFS: could not start the storage thread");
		return State::Failed;
	}
	{
		std::unique_lock<std::mutex> lock(g_thread_mutex);
		g_thread_cv.wait(lock, [] { return g_thread_started; });
	}
	Op op;
	op.kind = OP_INIT;
	op.path = OPFS_ROOT;
	switch (call(op)) {
	case 1:
		return State::Ready;
	case 2:
		return State::Unsupported;
	default:
		return State::Failed;
	}
}

std::vector<std::string> list_databases(const std::string &dir)
{
	std::vector<std::string> out;
	DIR *handle = opendir(dir.c_str());
	if (!handle)
		return out;
	while (dirent *entry = readdir(handle)) {
		const std::string name = entry->d_name;
		if (name.size() > 7 && name.compare(name.size() - 7, 7, ".sqlite") == 0)
			out.push_back(name);
	}
	closedir(handle);
	std::sort(out.begin(), out.end());
	return out;
}

bool remove_opfs_tree(const std::string &id)
{
	const std::string path = std::string(OPFS_ROOT) + "/" + id;
	Op op;
	op.kind = OP_REMOVE_TREE;
	op.path = path.c_str();
	const int result = call(op);
	return result == 0 || result == ERR_NOT_FOUND;
}

int check_rows(void *arg, int columns, char **values, char **)
{
	auto *rows = static_cast<std::vector<std::string> *>(arg);
	if (columns > 0)
		rows->push_back(values[0] ? values[0] : "");
	return rows->size() > 20 ? 1 : 0;
}

// Copies one database into OPFS and checks the copy.
bool migrate_file(const std::string &world, const std::string &path,
		const std::string &file,
		const std::function<void(const MigrationProgress &)> &progress,
		std::string *error)
{
	sqlite3 *source = nullptr;
	sqlite3 *target = nullptr;
	bool ok = false;
	do {
		// Read-write, so that SQLite rolls back a hot journal left by a tab
		// closed in the middle of a save before the pages are copied.
		if (sqlite3_open_v2(path.c_str(), &source, SQLITE_OPEN_READWRITE,
				g_base->zName) != SQLITE_OK) {
			*error = "cannot open " + file + ": " + sqlite3_errmsg(source);
			break;
		}
		if (sqlite3_open_v2(path.c_str(), &target,
				SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, VFS_NAME) != SQLITE_OK) {
			*error = "cannot create " + file + " in OPFS: " + sqlite3_errmsg(target);
			break;
		}
		sqlite3_backup *backup = sqlite3_backup_init(target, "main", source, "main");
		if (!backup) {
			*error = "cannot copy " + file + ": " + sqlite3_errmsg(target);
			break;
		}
		int rc;
		int busy = 0;
		do {
			rc = sqlite3_backup_step(backup, 1024);
			if (progress) {
				const int total = sqlite3_backup_pagecount(backup);
				const int left = sqlite3_backup_remaining(backup);
				progress({world, file, total > 0 ? 1.0 - double(left) / total : 1.0});
			}
			if (rc == SQLITE_BUSY || rc == SQLITE_LOCKED) {
				if (++busy > 500)
					break;
				sqlite3_sleep(10);
			}
		} while (rc == SQLITE_OK || rc == SQLITE_BUSY || rc == SQLITE_LOCKED);
		if (sqlite3_backup_finish(backup) != SQLITE_OK || rc != SQLITE_DONE) {
			*error = "copying " + file + " failed: " + sqlite3_errmsg(target);
			break;
		}
		std::vector<std::string> rows;
		char *message = nullptr;
		if (sqlite3_exec(target, "PRAGMA integrity_check", check_rows, &rows,
				&message) != SQLITE_OK) {
			*error = "integrity check of " + file + " failed: " +
				(message ? message : sqlite3_errmsg(target));
			sqlite3_free(message);
			break;
		}
		if (rows.size() != 1 || rows[0] != "ok") {
			*error = "integrity check of the copied " + file + " reported: " +
				(rows.empty() ? std::string("nothing") : rows[0]);
			break;
		}
		ok = true;
	} while (false);
	if (target)
		sqlite3_close(target);
	if (source)
		sqlite3_close(source);
	return ok;
}

} // namespace

const char *state_name(State state)
{
	switch (state) {
	case State::NotStarted: return "not started";
	case State::Disabled: return "disabled";
	case State::Unsupported: return "unsupported";
	case State::Failed: return "failed";
	case State::Ready: return "ready";
	}
	return "unknown";
}

State init(const Config &config)
{
	std::lock_guard<std::mutex> lock(g_init_mutex);
	if (g_state.load() != State::NotStarted)
		return g_state.load();
	g_config = config;
	while (!g_config.worlds_dir.empty() && g_config.worlds_dir.back() == '/')
		g_config.worlds_dir.pop_back();

	if (sqlite3_initialize() != SQLITE_OK) {
		g_state.store(State::Failed);
		return State::Failed;
	}
	g_base = sqlite3_vfs_find(nullptr);
	if (!g_base) {
		g_state.store(State::Failed);
		return State::Failed;
	}

	State state = State::Disabled;
	if (emscripten_is_main_browser_thread()) {
		log(2, "OPFS: storage must be started from a worker");
		state = State::Failed;
	} else if (config.enabled) {
		state = start_thread();
	}

	// The VFS is registered even when OPFS cannot be used, so a world whose
	// databases are in OPFS fails to open instead of starting over empty.
	std::memset(&g_vfs, 0, sizeof(g_vfs));
	g_vfs.iVersion = 2;
	g_vfs.szOsFile = std::max<int>(sizeof(OpfsFile), g_base->szOsFile);
	g_vfs.mxPathname = g_base->mxPathname;
	g_vfs.zName = VFS_NAME;
	g_vfs.xOpen = vfs_open;
	g_vfs.xDelete = vfs_delete;
	g_vfs.xAccess = vfs_access;
	g_vfs.xFullPathname = vfs_full_pathname;
	g_vfs.xDlOpen = g_base->xDlOpen;
	g_vfs.xDlError = g_base->xDlError;
	g_vfs.xDlSym = g_base->xDlSym;
	g_vfs.xDlClose = g_base->xDlClose;
	g_vfs.xRandomness = vfs_randomness;
	g_vfs.xSleep = vfs_sleep;
	g_vfs.xCurrentTime = vfs_current_time;
	g_vfs.xGetLastError = vfs_last_error;
	g_vfs.xCurrentTimeInt64 = vfs_current_time_int64;
	g_state.store(state, std::memory_order_release);
	if (sqlite3_vfs_register(&g_vfs, 1) != SQLITE_OK) {
		log(2, "OPFS: could not register the SQLite VFS");
		g_state.store(State::Failed);
		return State::Failed;
	}
	log(state == State::Ready || state == State::Disabled ? 0 : 1,
			std::string("OPFS world storage: ") + state_name(state));
	return state;
}

State state()
{
	return g_state.load(std::memory_order_acquire);
}

bool file_exists(const std::string &path)
{
	if (g_state.load() == State::NotStarted)
		return js_fs_exists(path);
	int out = 0;
	if (vfs_access(&g_vfs, path.c_str(), SQLITE_ACCESS_EXISTS, &out) != SQLITE_OK)
		return false;
	return out != 0;
}

bool world_uses_opfs(const std::string &world_dir)
{
	return !read_marker(world_dir).empty();
}

MigrationResult migrate_world(const std::string &raw_dir,
		const std::function<void(const MigrationProgress &)> &progress,
		std::string *error)
{
	std::string world_dir = raw_dir;
	while (!world_dir.empty() && world_dir.back() == '/')
		world_dir.pop_back();
	const std::string world = world_dir.substr(world_dir.rfind('/') + 1);
	const std::vector<std::string> files = list_databases(world_dir);

	if (world_uses_opfs(world_dir)) {
		// The marker is only written after every copy passed its check, so
		// copies still in the JavaScript filesystem are leftovers of a page
		// closed before the small-file sync removed them.
		bool removed = false;
		for (const std::string &file : files) {
			const std::string path = world_dir + "/" + file;
			removed |= std::remove(path.c_str()) == 0;
			std::remove((path + "-journal").c_str());
		}
		if (removed) {
			log(0, "OPFS: removed old copies of " + world);
			if (g_config.small_files_changed)
				g_config.small_files_changed();
		}
		return MigrationResult::NothingToDo;
	}
	if (files.empty() || g_state.load() != State::Ready)
		return MigrationResult::NothingToDo;

	const std::string id = new_id();
	{
		std::lock_guard<std::mutex> lock(g_route_mutex);
		g_pending[world_dir] = id;
	}
	std::string failure;
	bool ok = true;
	for (const std::string &file : files) {
		if (!migrate_file(world, world_dir + "/" + file, file, progress, &failure)) {
			ok = false;
			break;
		}
	}
	if (ok && !write_marker(world_dir, id)) {
		ok = false;
		failure = std::string("cannot write ") + MARKER_FILE;
	}
	{
		std::lock_guard<std::mutex> lock(g_route_mutex);
		g_pending.erase(world_dir);
	}
	if (!ok) {
		remove_opfs_tree(id);
		if (error)
			*error = failure;
		log(2, "OPFS: " + world + " stays on the old storage: " + failure);
		return MigrationResult::Failed;
	}
	for (const std::string &file : files) {
		const std::string path = world_dir + "/" + file;
		std::remove(path.c_str());
		std::remove((path + "-journal").c_str());
	}
	if (g_config.small_files_changed)
		g_config.small_files_changed();
	log(0, "OPFS: moved " + world + " to storage " + id);
	return MigrationResult::Migrated;
}

} // namespace sqlite_opfs

#endif // __EMSCRIPTEN__
