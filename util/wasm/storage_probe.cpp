// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 The Luanti Contributors

// Probe for util/wasm/test_storage_browser.py: the OPFS world-database VFS
// (src/database/sqlite3_opfs_vfs.cpp) with the real persistence.js and
// storage.js, without the engine. main(action, world, ...) runs on a worker
// like the engine's and publishes Module.luantiStorageProbe.
//
//   write <world> <rows>   create the world's map.sqlite with `rows` rows
//   migrate                migrate_world() every world, as the engine does
//   read <world>           count rows, integrity check, where the file lives
//   kill-writer <world>    commit forever, publishing the generation

#include <emscripten.h>
#include <emscripten/threading.h>
#include <sqlite3.h>

#include <algorithm>
#include <dirent.h>
#include <string>
#include <sys/stat.h>

#include "database/sqlite3_opfs_vfs.h"

namespace {

const std::string WORLDS = "/home/web_user/.luanti/worlds";

void publish(const std::string &json)
{
	MAIN_THREAD_EM_ASM({
		Module["luantiStorageProbe"] = JSON.parse(UTF8ToString($0));
	}, json.c_str());
}

std::string quoted(std::string text)
{
	for (char &c : text)
		if (c == '"' || c == '\\' || c == '\n')
			c = '\'';
	return "\"" + text + "\"";
}

[[noreturn]] void fail(const std::string &what, sqlite3 *db)
{
	publish("{\"error\":" + quoted(what + (db ? std::string(": ") + sqlite3_errmsg(db) : "")) + "}");
	emscripten_force_exit(1);
	__builtin_unreachable();
}

void exec(sqlite3 *db, const std::string &sql)
{
	if (sqlite3_exec(db, sql.c_str(), nullptr, nullptr, nullptr) != SQLITE_OK)
		fail(sql, db);
}

long long scalar(sqlite3 *db, const char *sql)
{
	sqlite3_stmt *stmt = nullptr;
	if (sqlite3_prepare_v2(db, sql, -1, &stmt, nullptr) != SQLITE_OK)
		fail(sql, db);
	long long value = -1;
	if (sqlite3_step(stmt) == SQLITE_ROW)
		value = sqlite3_column_int64(stmt, 0);
	sqlite3_finalize(stmt);
	return value;
}

std::string text(sqlite3 *db, const char *sql)
{
	sqlite3_stmt *stmt = nullptr;
	if (sqlite3_prepare_v2(db, sql, -1, &stmt, nullptr) != SQLITE_OK)
		fail(sql, db);
	std::string value;
	if (sqlite3_step(stmt) == SQLITE_ROW && sqlite3_column_text(stmt, 0))
		value = (const char *)sqlite3_column_text(stmt, 0);
	sqlite3_finalize(stmt);
	return value;
}

sqlite3 *open_world(const std::string &world)
{
	mkdir(WORLDS.c_str(), 0777);
	mkdir((WORLDS + "/" + world).c_str(), 0777);
	sqlite3 *db = nullptr;
	const std::string path = WORLDS + "/" + world + "/map.sqlite";
	if (sqlite3_open_v2(path.c_str(), &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE,
			nullptr) != SQLITE_OK)
		fail("open " + path, db);
	exec(db, "PRAGMA synchronous = 2");
	exec(db, "CREATE TABLE IF NOT EXISTS blocks (pos INTEGER PRIMARY KEY, data BLOB NOT NULL)");
	exec(db, "CREATE TABLE IF NOT EXISTS meta (k TEXT PRIMARY KEY, v INTEGER)");
	exec(db, "INSERT OR IGNORE INTO meta VALUES ('generation', 0)");
	return db;
}

bool js_fs_exists(const std::string &path)
{
	struct stat info;
	return stat(path.c_str(), &info) == 0;
}

} // namespace

int main(int argc, char **argv)
{
	const std::string action = argc > 1 ? argv[1] : "";
	const std::string world = argc > 2 ? argv[2] : "";
	const bool wanted = MAIN_THREAD_EM_ASM_INT({
		var storage = Module["luantiStorage"];
		return storage && storage["backend"] === "opfs" ? 1 : 0;
	}) != 0;
	sqlite_opfs::Config config;
	config.worlds_dir = WORLDS;
	config.enabled = wanted;
	config.small_files_changed = [] {
		MAIN_THREAD_ASYNC_EM_ASM({
			Module["luantiPersistence"]["requestSync"]({"reason": "probe", "urgent": true});
		});
	};
	const auto state = sqlite_opfs::init(config);
	const std::string state_json = "\"state\":" + quoted(sqlite_opfs::state_name(state));

	if (action == "write") {
		sqlite3 *db = open_world(world);
		const int rows = argc > 3 ? std::stoi(argv[3]) : 100;
		exec(db, "BEGIN");
		for (int i = 0; i < rows; i++)
			exec(db, "REPLACE INTO blocks VALUES (" + std::to_string(i) +
					", randomblob(2000))");
		exec(db, "COMMIT");
		const long long count = scalar(db, "SELECT count(*) FROM blocks");
		sqlite3_close(db);
		publish("{" + state_json + ",\"rows\":" + std::to_string(count) + "}");
	} else if (action == "migrate") {
		std::string results;
		DIR *dir = opendir(WORLDS.c_str());
		while (dirent *entry = dir ? readdir(dir) : nullptr) {
			const std::string name = entry->d_name;
			if (name.empty() || name[0] == '.')
				continue;
			std::string error;
			auto result = sqlite_opfs::migrate_world(WORLDS + "/" + name, nullptr, &error);
			const char *label = result == sqlite_opfs::MigrationResult::Migrated ? "migrated" :
				result == sqlite_opfs::MigrationResult::Failed ? "failed" : "nothing";
			if (!results.empty())
				results += ",";
			results += quoted(name) + ":{\"result\":" + quoted(label) +
				",\"error\":" + quoted(error) + "}";
		}
		if (dir)
			closedir(dir);
		publish("{" + state_json + ",\"worlds\":{" + results + "}}");
	} else if (action == "read") {
		const std::string dir = WORLDS + "/" + world;
		const bool js_copy = js_fs_exists(dir + "/map.sqlite");
		const bool on_opfs = sqlite_opfs::world_uses_opfs(dir);
		sqlite3 *db = open_world(world);
		const long long rows = scalar(db, "SELECT count(*) FROM blocks");
		const long long generation = scalar(db, "SELECT v FROM meta WHERE k = 'generation'");
		const std::string integrity = text(db, "PRAGMA integrity_check");
		sqlite3_close(db);
		publish("{" + state_json + ",\"rows\":" + std::to_string(rows) +
				",\"generation\":" + std::to_string(generation) +
				",\"integrity\":" + quoted(integrity) +
				",\"opfs\":" + (on_opfs ? "true" : "false") +
				",\"jsCopy\":" + (js_copy ? "true" : "false") + "}");
	} else if (action == "kill-writer") {
		sqlite3 *db = open_world(world);
		const long long rows = std::max(1LL, scalar(db, "SELECT count(*) FROM blocks"));
		for (;;) {
			exec(db, "BEGIN");
			for (int i = 0; i < 400; i++)
				exec(db, "REPLACE INTO blocks VALUES (" + std::to_string(i % rows) +
						", randomblob(2000))");
			exec(db, "UPDATE meta SET v = v + 1 WHERE k = 'generation'");
			exec(db, "COMMIT");
			publish("{" + state_json + ",\"generation\":" +
					std::to_string(scalar(db, "SELECT v FROM meta WHERE k = 'generation'")) + "}");
		}
	} else {
		publish("{" + state_json + "}");
	}
	return 0;
}
