// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 The Luanti Contributors

// Storage spike for the OPFS world backend (util/wasm/bench_storage_spike.py).
//
// Runs one SQLite workload shaped like Luanti's map database (a `blocks` table
// of 1.5-2.5 KiB incompressible blobs keyed by position) against one of three
// stores, picked at build and run time:
//
//   idbfs   Emscripten's JS filesystem (MEMFS) mounted with IDBFS, durable
//           after FS.syncfs(false). This is what the engine shipped with.
//   wasmfs  -sWASMFS with wasmfs_create_opfs_backend() mounted at /opfs
//           (build with -DSPIKE_WASMFS).
//   vfs     The JS filesystem plus src/database/sqlite3_opfs_vfs.cpp, the
//           SQLite VFS on OPFS sync access handles.
//
// main() runs on a worker (PROXY_TO_PTHREAD), like the engine's server
// thread. Module.spikeOptions = {backend, action, sizeMB, seconds} selects the
// work; the result is published as Module.spikeResult (JSON), progress as
// Module.spikeProgress, and the kill test's last committed generation as
// Module.spikeCommitted.

#include <emscripten.h>
#include <emscripten/heap.h>
#include <emscripten/threading.h>
#include <sqlite3.h>

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <random>
#include <string>
#include <sys/stat.h>
#include <vector>

#ifdef SPIKE_WASMFS
#include <emscripten/wasmfs.h>
#else
#include "database/sqlite3_opfs_vfs.h"
#endif

namespace {

std::string g_backend;
std::string g_action;
int g_size_mb = 500;
double g_seconds = 3;
std::mt19937_64 g_rng(12345);

std::string option(const char *name)
{
	char *value = (char *)MAIN_THREAD_EM_ASM_PTR({
		var options = Module["spikeOptions"] || {};
		var value = options[UTF8ToString($0)];
		return value === undefined ? 0 : stringToNewUTF8(String(value));
	}, name);
	std::string out = value ? value : "";
	free(value);
	return out;
}

void publish(const char *key, const std::string &json)
{
	MAIN_THREAD_EM_ASM({
		Module[UTF8ToString($0)] = JSON.parse(UTF8ToString($1));
	}, key, json.c_str());
}

void progress(const std::string &text)
{
	publish("spikeProgress", "\"" + text + "\"");
}

double now()
{
	return emscripten_get_now();
}

[[noreturn]] void fail(const std::string &what, sqlite3 *db)
{
	std::string message = what + (db ? std::string(": ") + sqlite3_errmsg(db) : "");
	for (char &c : message)
		if (c == '"' || c == '\\')
			c = '\'';
	publish("spikeResult", "{\"error\":\"" + message + "\"}");
	emscripten_force_exit(1);
	__builtin_unreachable();
}

void exec(sqlite3 *db, const char *sql)
{
	char *error = nullptr;
	if (sqlite3_exec(db, sql, nullptr, nullptr, &error) != SQLITE_OK)
		fail(std::string(sql) + " -> " + (error ? error : "?"), db);
}

// ----------------------------------------------------------- the stores

std::string g_path;

#ifndef SPIKE_WASMFS
// FS.syncfs(false) on the browser main thread; the worker waits for it.
double idbfs_sync()
{
	const double start = now();
	static volatile int done;
	done = 0;
	MAIN_THREAD_ASYNC_EM_ASM({
		FS.syncfs(false, function(error) {
			if (error)
				console.error("spike syncfs", error);
			Atomics.store(HEAP32, $0 >> 2, error ? 2 : 1);
		});
	}, &done);
	while (__atomic_load_n(&done, __ATOMIC_ACQUIRE) == 0)
		emscripten_thread_sleep(1);
	if (done != 1)
		fail("syncfs failed", nullptr);
	return now() - start;
}
#endif

void open_store()
{
#ifdef SPIKE_WASMFS
	backend_t backend = wasmfs_create_opfs_backend();
	if (wasmfs_create_directory("/opfs", 0777, backend) != 0) {
		struct stat info;
		if (stat("/opfs", &info) != 0)
			fail("cannot mount the WASMFS OPFS backend", nullptr);
	}
	g_path = "/opfs/spike-map.sqlite";
#else
	if (g_backend == "vfs") {
		mkdir("/w", 0777);
		mkdir("/w/spike", 0777);
		// The spike keeps one fixed storage id so a reload finds the database.
		FILE *marker = fopen("/w/spike/web_opfs_id.txt", "w");
		fputs("00000000000000000000000000005b1e\n", marker);
		fclose(marker);
		sqlite_opfs::Config config;
		config.worlds_dir = "/w";
		auto state = sqlite_opfs::init(config);
		if (state != sqlite_opfs::State::Ready)
			fail(std::string("OPFS VFS ") + sqlite_opfs::state_name(state), nullptr);
		g_path = "/w/spike/map.sqlite";
	} else {
		g_path = "/idb/map.sqlite";
	}
#endif
}

bool durable_sync_needed()
{
	return g_backend == "idbfs";
}

double make_durable()
{
#ifndef SPIKE_WASMFS
	if (durable_sync_needed())
		return idbfs_sync();
#endif
	return 0;
}

sqlite3 *open_db()
{
	sqlite3 *db = nullptr;
	if (sqlite3_open_v2(g_path.c_str(), &db,
			SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nullptr) != SQLITE_OK)
		fail("open " + g_path, db);
	// Luanti's defaults: rollback journal, synchronous = FULL (2).
	exec(db, "PRAGMA synchronous = 2");
	exec(db, "CREATE TABLE IF NOT EXISTS blocks (pos INTEGER PRIMARY KEY, data BLOB NOT NULL)");
	exec(db, "CREATE TABLE IF NOT EXISTS meta (k TEXT PRIMARY KEY, v INTEGER)");
	exec(db, "INSERT OR IGNORE INTO meta VALUES ('generation', 0)");
	return db;
}

std::int64_t scalar(sqlite3 *db, const char *sql)
{
	sqlite3_stmt *stmt = nullptr;
	if (sqlite3_prepare_v2(db, sql, -1, &stmt, nullptr) != SQLITE_OK)
		fail(sql, db);
	std::int64_t value = -1;
	if (sqlite3_step(stmt) == SQLITE_ROW)
		value = sqlite3_column_int64(stmt, 0);
	sqlite3_finalize(stmt);
	return value;
}

std::vector<unsigned char> blob()
{
	std::vector<unsigned char> data(1536 + g_rng() % 1024);
	for (auto &byte : data)
		byte = static_cast<unsigned char>(g_rng());
	return data;
}

void write_rows(sqlite3 *db, sqlite3_stmt *stmt, std::int64_t first, int count,
		std::int64_t range, std::int64_t *bytes)
{
	for (int i = 0; i < count; i++) {
		const std::int64_t pos = range > 0 ? std::int64_t(g_rng() % range) : first + i;
		auto data = blob();
		sqlite3_bind_int64(stmt, 1, pos);
		sqlite3_bind_blob(stmt, 2, data.data(), (int)data.size(), SQLITE_TRANSIENT);
		if (sqlite3_step(stmt) != SQLITE_DONE)
			fail("write block", db);
		sqlite3_reset(stmt);
		if (bytes)
			*bytes += data.size();
	}
}

std::string heap_json()
{
	const double memory = (double)emscripten_get_heap_size();
	const double brk = (double)(std::uintptr_t)*emscripten_get_sbrk_ptr();
	return "\"wasmMemoryBytes\":" + std::to_string((long long)memory) +
		",\"heapBreakBytes\":" + std::to_string((long long)brk);
}

std::string percentiles(std::vector<double> values, const char *name)
{
	std::sort(values.begin(), values.end());
	auto at = [&](double q) {
		return values.empty() ? 0.0 : values[std::min(values.size() - 1,
				(size_t)(q * (values.size() - 1) + 0.5))];
	};
	char buffer[256];
	std::snprintf(buffer, sizeof(buffer),
			"\"%s\":{\"p50\":%.2f,\"p95\":%.2f,\"max\":%.2f,\"n\":%zu}",
			name, at(0.5), at(0.95), values.empty() ? 0.0 : values.back(), values.size());
	return buffer;
}

// Random point reads for `seconds`, as the emerge thread does.
double read_rate(sqlite3 *db, std::int64_t rows, double seconds)
{
	sqlite3_stmt *stmt = nullptr;
	sqlite3_prepare_v2(db, "SELECT data FROM blocks WHERE pos = ?", -1, &stmt, nullptr);
	const double start = now();
	long count = 0;
	while (now() - start < seconds * 1000) {
		sqlite3_bind_int64(stmt, 1, std::int64_t(g_rng() % rows));
		if (sqlite3_step(stmt) != SQLITE_ROW)
			fail("read block", db);
		sqlite3_reset(stmt);
		count++;
	}
	sqlite3_finalize(stmt);
	return count / ((now() - start) / 1000);
}

void set_main_busy(bool busy)
{
	// Stands in for proxied WebGL: the browser main thread is busy 14 ms of
	// every 16 ms frame.
	MAIN_THREAD_EM_ASM({
		if ($0) {
			Module["spikeBusy"] = setInterval(function() {
				var end = performance.now() + 14;
				while (performance.now() < end) {}
			}, 16);
		} else {
			clearInterval(Module["spikeBusy"]);
		}
	}, busy);
}

void populate(sqlite3 *db)
{
	const std::int64_t target = std::int64_t(g_size_mb) * 1024 * 1024;
	std::int64_t bytes = 0;
	std::int64_t rows = scalar(db, "SELECT count(*) FROM blocks");
	if (rows > 0)
		fail("populate expects an empty database", nullptr);
	sqlite3_stmt *stmt = nullptr;
	sqlite3_prepare_v2(db, "INSERT INTO blocks VALUES (?, ?)", -1, &stmt, nullptr);
	const double start = now();
	while (bytes < target) {
		exec(db, "BEGIN");
		write_rows(db, stmt, rows, 2000, 0, &bytes);
		exec(db, "COMMIT");
		rows += 2000;
		progress("populate " + std::to_string(bytes >> 20) + " MiB");
	}
	sqlite3_finalize(stmt);
	const double insert_ms = now() - start;
	const double sync_ms = make_durable();
	char buffer[256];
	std::snprintf(buffer, sizeof(buffer),
			"{\"rows\":%lld,\"bytes\":%lld,\"insertMs\":%.0f,\"syncMs\":%.0f,",
			(long long)rows, (long long)bytes, insert_ms, sync_ms);
	publish("spikeResult", buffer + heap_json() + "}");
}

void bench(sqlite3 *db)
{
	const double open_start = now();
	const std::int64_t rows = scalar(db, "SELECT count(*) FROM blocks");
	const double count_ms = now() - open_start;
	if (rows <= 0)
		fail("bench expects a populated database", nullptr);
	sqlite3_stmt *stmt = nullptr;
	sqlite3_prepare_v2(db, "REPLACE INTO blocks VALUES (?, ?)", -1, &stmt, nullptr);

	// A map save: 200 changed blocks in one transaction, then durable.
	std::vector<double> commit_ms, durable_ms;
	for (int round = 0; round < 30; round++) {
		const double start = now();
		exec(db, "BEGIN");
		write_rows(db, stmt, 0, 200, rows, nullptr);
		exec(db, "COMMIT");
		const double committed = now();
		make_durable();
		commit_ms.push_back(committed - start);
		durable_ms.push_back(now() - start);
		progress("save " + std::to_string(round));
	}
	sqlite3_finalize(stmt);

	progress("reads, main thread idle");
	const double idle = read_rate(db, rows, g_seconds);
	progress("reads, main thread busy");
	set_main_busy(true);
	const double busy = read_rate(db, rows, g_seconds);
	set_main_busy(false);

	const double check_start = now();
	sqlite3_stmt *check = nullptr;
	sqlite3_prepare_v2(db, "PRAGMA integrity_check", -1, &check, nullptr);
	std::string verdict = "?";
	if (sqlite3_step(check) == SQLITE_ROW)
		verdict = (const char *)sqlite3_column_text(check, 0);
	sqlite3_finalize(check);
	const double check_ms = now() - check_start;

	char buffer[512];
	std::snprintf(buffer, sizeof(buffer),
			"{\"rows\":%lld,\"countMs\":%.0f,\"readsPerSecIdle\":%.0f,"
			"\"readsPerSecBusy\":%.0f,\"integrity\":\"%s\",\"integrityMs\":%.0f,",
			(long long)rows, count_ms, idle, busy, verdict.c_str(), check_ms);
	publish("spikeResult", buffer + percentiles(commit_ms, "commitMs") + "," +
			percentiles(durable_ms, "durableMs") + "," + heap_json() + "}");
}

// Commits forever; the driver kills the browser at some point.
void kill_writer(sqlite3 *db)
{
	const std::int64_t rows = scalar(db, "SELECT count(*) FROM blocks");
	sqlite3_stmt *stmt = nullptr;
	sqlite3_prepare_v2(db, "REPLACE INTO blocks VALUES (?, ?)", -1, &stmt, nullptr);
	for (;;) {
		exec(db, "BEGIN");
		// Large enough that a kill usually lands inside the transaction.
		write_rows(db, stmt, 0, 2000, rows, nullptr);
		exec(db, "UPDATE meta SET v = v + 1 WHERE k = 'generation'");
		exec(db, "COMMIT");
		make_durable();
		publish("spikeCommitted",
				std::to_string(scalar(db, "SELECT v FROM meta WHERE k = 'generation'")));
	}
}

void verify(sqlite3 *db)
{
	sqlite3_stmt *check = nullptr;
	sqlite3_prepare_v2(db, "PRAGMA integrity_check", -1, &check, nullptr);
	std::string verdict = "?";
	if (sqlite3_step(check) == SQLITE_ROW)
		verdict = (const char *)sqlite3_column_text(check, 0);
	sqlite3_finalize(check);
	const std::int64_t generation = scalar(db, "SELECT v FROM meta WHERE k = 'generation'");
	publish("spikeResult", "{\"integrity\":\"" + verdict + "\",\"generation\":" +
			std::to_string(generation) + "}");
}

} // namespace

int main()
{
	g_backend = option("backend");
	g_action = option("action");
	if (!option("sizeMB").empty())
		g_size_mb = std::stoi(option("sizeMB"));
	if (!option("seconds").empty())
		g_seconds = std::stod(option("seconds"));
	open_store();
	sqlite3 *db = open_db();
	if (g_action == "populate")
		populate(db);
	else if (g_action == "bench")
		bench(db);
	else if (g_action == "kill-writer")
		kill_writer(db);
	else
		verify(db);
	sqlite3_close(db);
	return 0;
}
