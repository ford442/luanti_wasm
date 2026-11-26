// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2024-2026 The Luanti Contributors

#ifdef __EMSCRIPTEN__

#include "porting_emscripten.h"

#include "porting.h"
#include "log.h"
#include "util/numeric.h"
#include "version.h"
#include "filesys.h"
#include "database/sqlite3_opfs_vfs.h"

#include <string>

#include <atomic>
#include <cstdlib>
#include <cstdint>
#include <mutex>
#include <emscripten.h>
#include <emscripten/heap.h>
#include <emscripten/threading.h>

namespace {

constexpr std::uint64_t ORDINARY_SYNC_INTERVAL_MS = 10'000;

std::atomic<std::uint64_t> dirty_generation{0};
std::atomic<std::uint64_t> submitted_generation{0};
std::atomic<std::uint64_t> saved_generation{0};
std::atomic<porting::EmscriptenPersistenceReason> pending_reason{
	porting::EmscriptenPersistenceReason::Periodic};
std::atomic<bool> pending_urgent{false};
std::atomic<bool> sync_error{false};
std::atomic<bool> world_save_requested{false};
std::uint64_t last_ordinary_start_ms = 0;

// Frame clock and pause state, shared with the page through the exports below.
std::atomic<int> g_engine_paused{0};
std::atomic<std::uint64_t> g_frame_clock_count{0};
std::atomic<float> g_frame_clock_last_dtime{0.0f};

const char *reason_name(porting::EmscriptenPersistenceReason reason)
{
	switch (reason) {
	case porting::EmscriptenPersistenceReason::Settings:
		return "settings";
	case porting::EmscriptenPersistenceReason::Disconnect:
		return "disconnect";
	case porting::EmscriptenPersistenceReason::Shutdown:
		return "shutdown";
	case porting::EmscriptenPersistenceReason::Periodic:
	default:
		return "periodic";
	}
}

// A clip name has to be a bare file name that the launcher can append to its
// own media/ directory. Rejecting everything else here means a mod cannot aim
// the page's <video> element at another origin, and cannot escape the media
// directory with "../". The browser's own COOP/COEP rules would already block
// a cross-origin fetch, but a mod should not be able to make the attempt.
bool is_safe_clip_name(const std::string &clip)
{
	if (clip.empty() || clip.size() > 128)
		return false;
	if (clip.front() == '.' || clip.front() == '-')
		return false;
	for (char c : clip) {
		const bool ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
			|| (c >= '0' && c <= '9') || c == '.' || c == '_' || c == '-';
		if (!ok)
			return false;
	}
	return clip.find("..") == std::string::npos;
}

// A runtime media id is "<set>/<id>" in lowercase letters, digits and
// underscores (see util/wasm/build_packages.py). The page checks it again.
bool is_safe_media_id(const std::string &id)
{
	const auto slash = id.find('/');
	if (slash == std::string::npos || slash == 0 || id.size() - slash - 1 < 1
			|| id.size() - slash - 1 > 64 || slash > 64)
		return false;
	for (std::size_t i = 0; i < id.size(); i++) {
		const char c = id[i];
		const bool ok = (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')
			|| c == '_' || (c == '/' && i == slash);
		if (!ok)
			return false;
	}
	return true;
}

// Theater Tier C spike state. The browser main thread decodes frames and
// writes them straight into these buffers (shared Wasm memory, see
// emscripten_start_video_texture()); the application worker is the only
// reader, via emscripten_poll_video_texture_frame(). Double-buffered so a
// frame currently being decoded never overwrites the one still being read.
constexpr std::size_t VIDEO_FRAME_BUFFER_BYTES =
	static_cast<std::size_t>(porting::VIDEO_TEXTURE_SPIKE_MAX_WIDTH) *
	porting::VIDEO_TEXTURE_SPIKE_MAX_HEIGHT * 4;

alignas(4) std::uint8_t video_frame_buffer[2][VIDEO_FRAME_BUFFER_BYTES];
std::atomic<std::uint64_t> video_frame_generation{0};
std::uint64_t video_frame_consumed = 0; // application worker only
std::atomic<int> video_frame_ready_index{-1};
std::atomic<int> video_frame_width{0};
std::atomic<int> video_frame_height{0};
// Written only by emscripten_start_video_texture()/emscripten_stop_video_texture(),
// both of which run on the application worker; read on that same thread.
std::string video_texture_name;

// Frame statistics ring (Module.luantiPerf). Layout is read by
// client/web/perf.js; bump PERF_RING_VERSION when it changes. The application
// worker is the only writer: it fills frames[written % capacity] and then
// publishes it by storing written + 1 with release order. Readers on the
// browser main thread load `written` with Atomics.load and copy what they
// need; at one record per frame the ring holds a little over two minutes at
// 60 fps, far longer than any reader needs between reads.
constexpr std::uint32_t PERF_RING_VERSION = 1;
constexpr std::uint32_t PERF_RING_CAPACITY = 8192;

struct PerfFrame {
	float frame_ms;
	float draw_ms;
	float swap_ms;
	std::uint32_t drawcalls;
	std::uint32_t primitives;
	std::uint32_t mesh_queue;
};
static_assert(sizeof(PerfFrame) == 24, "perf.js reads 6 words per frame");

struct PerfRing {
	std::uint32_t version;
	std::uint32_t capacity;
	std::uint32_t words_per_frame;
	std::atomic<std::uint32_t> written;
	PerfFrame frames[PERF_RING_CAPACITY];
};
static_assert(sizeof(std::atomic<std::uint32_t>) == 4, "lock-free 32-bit atomic");

alignas(16) PerfRing perf_ring = {PERF_RING_VERSION, PERF_RING_CAPACITY,
	sizeof(PerfFrame) / 4, {0}, {}};
double perf_last_frame_ms = 0.0; // application worker only

} // namespace

extern "C" {

// Address of the frame statistics ring, for client/web/perf.js. The ring is a
// static in shared memory, so the address is the same on every thread.
EMSCRIPTEN_KEEPALIVE std::uintptr_t luanti_perf_ring()
{
	return reinterpret_cast<std::uintptr_t>(&perf_ring);
}

// How far the allocator has carved up the heap so far: the sbrk break, in
// bytes from address 0. dlmalloc takes its memory from sbrk and mimalloc sits
// on emmalloc, which does too, so this is the number to compare when judging
// an allocator. The committed WebAssembly.Memory is not: it only grows in
// steps from the 256 MiB initial size, so it reads the same for any engine
// that stays below it. Read from client/web/startup.js (heapBreakBytes).
EMSCRIPTEN_KEEPALIVE std::uintptr_t luanti_heap_break()
{
	return *emscripten_get_sbrk_ptr();
}

// Called by client/web/videotexture.js after it has written a decoded frame
// into video_frame_buffer[buffer_index]. Runs on the browser main thread's
// own module instance, touching only shared memory -- same pattern as the
// persistence completion callbacks below.
EMSCRIPTEN_KEEPALIVE void luanti_video_texture_frame(int buffer_index, int width, int height)
{
	if (buffer_index != 0 && buffer_index != 1)
		return;
	if (width <= 0 || height <= 0 ||
			width > porting::VIDEO_TEXTURE_SPIKE_MAX_WIDTH ||
			height > porting::VIDEO_TEXTURE_SPIKE_MAX_HEIGHT)
		return;

	video_frame_width.store(width, std::memory_order_relaxed);
	video_frame_height.store(height, std::memory_order_relaxed);
	video_frame_ready_index.store(buffer_index, std::memory_order_release);
	video_frame_generation.fetch_add(1, std::memory_order_release);
}

// Frame clock and pause, shared with the page (client/web/launcher.js).
// Atomics only: the page reads and writes them from the browser main thread
// while the application worker runs the frame loop, so no call has to be
// proxied and none can race callMain.
EMSCRIPTEN_KEEPALIVE void luanti_set_paused(int paused)
{
	g_engine_paused.store(paused ? 1 : 0, std::memory_order_release);
}

EMSCRIPTEN_KEEPALIVE int luanti_is_paused()
{
	return g_engine_paused.load(std::memory_order_acquire);
}

// Measured frames so far (every FpsControl::limit() call).
EMSCRIPTEN_KEEPALIVE double luanti_frame_clock_count()
{
	return static_cast<double>(g_frame_clock_count.load(std::memory_order_acquire));
}

// The most recent measured dtime, in milliseconds.
EMSCRIPTEN_KEEPALIVE double luanti_frame_clock_last_dtime_ms()
{
	return g_frame_clock_last_dtime.load(std::memory_order_relaxed) * 1000.0;
}

// Engine version for client/web/worlds.js, recorded in exported worlds so an
// import can warn about a world written by a different engine.
EMSCRIPTEN_KEEPALIVE const char *luanti_engine_version()
{
	return g_version_string;
}

// Called by client/web/persistence.js when the page is hidden. Only sets a
// flag: the server thread does the save on its next step.
EMSCRIPTEN_KEEPALIVE void luanti_request_world_save()
{
	world_save_requested.store(true, std::memory_order_release);
}

EMSCRIPTEN_KEEPALIVE void luanti_persistence_sync_completed(double generation)
{
	auto completed = static_cast<std::uint64_t>(generation);
	auto current = saved_generation.load(std::memory_order_relaxed);
	while (current < completed && !saved_generation.compare_exchange_weak(
			current, completed, std::memory_order_release,
			std::memory_order_relaxed)) {
	}
	sync_error.store(false, std::memory_order_release);
}

EMSCRIPTEN_KEEPALIVE void luanti_persistence_sync_failed(double generation)
{
	(void)generation;
	sync_error.store(true, std::memory_order_release);
}

} // extern "C"

namespace porting {

void emscripten_validate_main_loop()
{
	if (emscripten_is_main_browser_thread()) {
		emscripten_log(EM_LOG_ERROR,
				"Luanti: browser main-loop contract violated; "
				"build with -sPROXY_TO_PTHREAD=1");
		std::abort();
	}

	emscripten_log(EM_LOG_CONSOLE,
			"Luanti: synchronous engine loop running on an application worker");
	emscripten_log(EM_LOG_CONSOLE,
			"Luanti: clock=emscripten_get_now t_ms=%.3f getTimeMs=%llu",
			emscripten_get_now(),
			(unsigned long long)porting::getTimeMs());
}

void emscripten_service_browser_frame()
{
	emscripten_service_persistence();
}

void emscripten_frame_clock_record(float dtime)
{
	g_frame_clock_last_dtime.store(dtime, std::memory_order_relaxed);
	g_frame_clock_count.fetch_add(1, std::memory_order_release);
}

bool emscripten_engine_paused()
{
	return g_engine_paused.load(std::memory_order_acquire) != 0;
}

void emscripten_report_status(const std::string &message, int percent,
		const char *phase)
{
	// Called from both the client and the server init path, which are not
	// guaranteed to be the same thread, so the de-duplication state is locked.
	static std::mutex lock;
	static std::string last_message;
	static std::string last_phase;
	static int last_percent = -2;
	const std::string phase_string = phase ? phase : "";
	std::lock_guard<std::mutex> guard(lock);
	if (message == last_message && phase_string == last_phase &&
			percent == last_percent)
		return;
	last_message = message;
	last_phase = phase_string;
	last_percent = percent;

	MAIN_THREAD_EM_ASM({
		var launcher = Module["luantiLauncher"];
		if (launcher && typeof launcher["reportEngineStatus"] === "function") {
			launcher["reportEngineStatus"](
				UTF8ToString($0), $1, $2 ? UTF8ToString($2) : null);
		}
	}, message.c_str(), percent,
			phase_string.empty() ? nullptr : phase_string.c_str());
}

bool emscripten_take_world_save_request()
{
	return world_save_requested.exchange(false, std::memory_order_acq_rel);
}

static void publish_storage_state(const char *state)
{
	MAIN_THREAD_EM_ASM({
		var storage = Module["luantiStorage"];
		if (storage)
			storage["engineState"] = UTF8ToString($0);
	}, state);
}

static void publish_migration(const std::string &world, const char *result,
		const std::string &error)
{
	MAIN_THREAD_EM_ASM({
		var storage = Module["luantiStorage"];
		if (!storage)
			return;
		(storage["migrations"] = storage["migrations"] || []).push({
			"world": UTF8ToString($0),
			"result": UTF8ToString($1),
			"error": UTF8ToString($2) || null
		});
	}, world.c_str(), result, error.c_str());
}

void emscripten_init_world_storage()
{
	// storage.js decides before callMain (it can run a probe worker; the
	// engine cannot wait for one here) and the VFS confirms on its thread.
	const bool wanted = MAIN_THREAD_EM_ASM_INT({
		var storage = Module["luantiStorage"];
		return storage && storage["backend"] === "opfs" ? 1 : 0;
	}) != 0;

	sqlite_opfs::Config config;
	config.worlds_dir = porting::path_user + DIR_DELIM + "worlds";
	config.enabled = wanted;
	config.log = [](int level, const std::string &message) {
		if (level >= 2)
			errorstream << message << std::endl;
		else if (level == 1)
			warningstream << message << std::endl;
		else
			infostream << message << std::endl;
	};
	config.small_files_changed = [] {
		emscripten_mark_persistence_dirty(EmscriptenPersistenceReason::Periodic, true);
	};
	const sqlite_opfs::State state = sqlite_opfs::init(config);
	publish_storage_state(sqlite_opfs::state_name(state));
	if (wanted && state != sqlite_opfs::State::Ready)
		warningstream << "World storage: OPFS is " << sqlite_opfs::state_name(state)
			<< "; new worlds are kept in IndexedDB" << std::endl;
	if (state != sqlite_opfs::State::Ready)
		return;

	std::vector<std::string> worlds;
	for (const fs::DirListNode &node : fs::GetDirListing(config.worlds_dir)) {
		if (node.dir && !node.name.empty() && node.name[0] != '.')
			worlds.push_back(node.name);
	}
	for (const std::string &world : worlds) {
		std::string error;
		const auto result = sqlite_opfs::migrate_world(
			config.worlds_dir + DIR_DELIM + world,
			[](const sqlite_opfs::MigrationProgress &progress) {
				emscripten_report_status("Moving " + progress.world +
					" to faster storage… " +
					std::to_string(static_cast<int>(progress.fraction * 100)) +
					"%", 2, "loading");
			}, &error);
		if (result == sqlite_opfs::MigrationResult::Migrated)
			publish_migration(world, "migrated", "");
		else if (result == sqlite_opfs::MigrationResult::Failed)
			publish_migration(world, "failed", error);
	}
	// Push the removal of the old copies to IndexedDB right away.
	emscripten_service_persistence();
}

void emscripten_mark_persistence_dirty(EmscriptenPersistenceReason reason,
		bool urgent)
{
	pending_reason.store(reason, std::memory_order_relaxed);
	if (urgent)
		pending_urgent.store(true, std::memory_order_release);
	dirty_generation.fetch_add(1, std::memory_order_release);
}

void emscripten_service_persistence()
{
	auto generation = dirty_generation.load(std::memory_order_acquire);
	if (generation <= submitted_generation.load(std::memory_order_acquire))
		return;

	const bool urgent = pending_urgent.load(std::memory_order_acquire);
	const auto now = porting::getTimeMs();
	if (!urgent && last_ordinary_start_ms != 0 &&
			now - last_ordinary_start_ms < ORDINARY_SYNC_INTERVAL_MS)
		return;

	// Exchange only after the request is eligible. An urgent worker request
	// racing after this exchange remains set for the next service point.
	const bool submitted_urgent = pending_urgent.exchange(false,
		std::memory_order_acq_rel);
	const auto reason = pending_reason.load(std::memory_order_relaxed);

	if (!submitted_urgent)
		last_ordinary_start_ms = now;
	submitted_generation.store(generation, std::memory_order_release);

	MAIN_THREAD_EM_ASM({
		var persistence = Module["luantiPersistence"];
		if (!persistence || !persistence["_requestGeneration"]) {
			console.error("Luanti persistence service is unavailable");
			var failed = Module["_luanti_persistence_sync_failed"];
			if (typeof failed === "function")
				failed($0);
		} else {
			persistence["_requestGeneration"]({
				"generation": $0,
				"reason": UTF8ToString($1),
				"urgent": !!$2
			});
		}
	}, static_cast<double>(generation), reason_name(reason), submitted_urgent);
}

bool emscripten_persistence_pending()
{
	return saved_generation.load(std::memory_order_acquire) <
		dirty_generation.load(std::memory_order_acquire);
}

bool emscripten_persistence_error()
{
	return sync_error.load(std::memory_order_acquire);
}

void emscripten_wait_for_persistence()
{
	while (emscripten_persistence_pending()) {
		emscripten_service_persistence();
		// main() runs on the application worker. Sleeping it leaves the browser
		// main thread free to complete syncfs callbacks and display errors.
		emscripten_thread_sleep(16);
	}
}

void emscripten_record_frame(float draw_ms, float swap_ms,
		std::uint32_t drawcalls, std::uint32_t primitives,
		std::uint32_t mesh_queue)
{
	const double now = emscripten_get_now();
	const double last = perf_last_frame_ms;
	perf_last_frame_ms = now;
	// The first call only starts the clock; a frame time needs two ends.
	if (last == 0.0)
		return;
	const std::uint32_t n = perf_ring.written.load(std::memory_order_relaxed);
	PerfFrame &f = perf_ring.frames[n % PERF_RING_CAPACITY];
	f.frame_ms = static_cast<float>(now - last);
	f.draw_ms = draw_ms;
	f.swap_ms = swap_ms;
	f.drawcalls = drawcalls;
	f.primitives = primitives;
	f.mesh_queue = mesh_queue;
	perf_ring.written.store(n + 1, std::memory_order_release);
}

bool emscripten_show_video_overlay(const std::string &clip,
		const std::string &title, bool loop, bool muted)
{
	if (!is_safe_clip_name(clip)) {
		errorstream << "Refusing to play web video clip with unusable name: "
			<< clip << std::endl;
		return false;
	}

	// The launcher may have no overlay (an embedder replaced the shell) or no
	// clip on disk. Either way Tier A keeps playing, so a false return is a
	// normal outcome rather than an error.
	return MAIN_THREAD_EM_ASM_INT({
		var theater = Module["luantiTheater"];
		if (!theater || typeof theater["show"] !== "function")
			return 0;
		return theater["show"]({
			"clip": UTF8ToString($0),
			"title": UTF8ToString($1),
			"loop": !!$2,
			"muted": !!$3
		}) ? 1 : 0;
	}, clip.c_str(), title.c_str(), loop, muted) != 0;
}

WebMediaState emscripten_web_media_request(const std::string &id)
{
	if (!is_safe_media_id(id)) {
		errorstream << "Refusing web media request with unusable id: " << id << std::endl;
		return WebMediaState::Invalid;
	}
	// Synchronous hop to the main thread: the page starts (or looks up) the
	// download and answers at once; the transfer itself is asynchronous.
	const int code = MAIN_THREAD_EM_ASM_INT({
		var media = Module["luantiRuntimeMedia"];
		if (!media || typeof media["requestCode"] !== "function")
			return 0;
		return media["requestCode"](UTF8ToString($0));
	}, id.c_str());
	switch (code) {
	case 1: return WebMediaState::Ready;
	case 2: return WebMediaState::Loading;
	case 3: return WebMediaState::Busy;
	case 4: return WebMediaState::Missing;
	case 5: return WebMediaState::Failed;
	case 6: return WebMediaState::Invalid;
	default: return WebMediaState::Unavailable;
	}
}

bool emscripten_web_media_release(const std::string &id)
{
	if (!is_safe_media_id(id))
		return false;
	return MAIN_THREAD_EM_ASM_INT({
		var media = Module["luantiRuntimeMedia"];
		if (!media || typeof media["releaseCode"] !== "function")
			return 0;
		return media["releaseCode"](UTF8ToString($0));
	}, id.c_str()) != 0;
}

void emscripten_hide_video_overlay()
{
	MAIN_THREAD_EM_ASM({
		var theater = Module["luantiTheater"];
		if (theater && typeof theater["hide"] === "function")
			theater["hide"]();
	});
}

bool emscripten_start_video_texture(const std::string &clip,
		const std::string &texture_name, int width, int height, int fps)
{
	if (!is_safe_clip_name(clip)) {
		errorstream << "Refusing to start web video texture with unusable "
			"clip name: " << clip << std::endl;
		return false;
	}
	if (texture_name.empty() || texture_name.size() > 128) {
		errorstream << "Refusing to start web video texture with unusable "
			"texture name" << std::endl;
		return false;
	}

	width = rangelim(width, 1, VIDEO_TEXTURE_SPIKE_MAX_WIDTH);
	height = rangelim(height, 1, VIDEO_TEXTURE_SPIKE_MAX_HEIGHT);
	fps = rangelim(fps, 1, VIDEO_TEXTURE_SPIKE_MAX_FPS);

	video_texture_name = texture_name;
	video_frame_ready_index.store(-1, std::memory_order_relaxed);
	video_frame_generation.store(0, std::memory_order_relaxed);
	video_frame_consumed = 0;

	// Anything the launcher does not implement (no decoder shell, browser
	// refuses the codec) is a normal "stay on Tier A/B" outcome, not an error.
	return MAIN_THREAD_EM_ASM_INT({
		var texturer = Module["luantiVideoTexture"];
		if (!texturer || typeof texturer["start"] !== "function")
			return 0;
		return texturer["start"]({
			"clip": UTF8ToString($0),
			"width": $1,
			"height": $2,
			"fps": $3,
			"bufferPtr0": $4,
			"bufferPtr1": $5,
			"bufferSize": $6
		}) ? 1 : 0;
	}, clip.c_str(), width, height, fps,
			(int)(std::uintptr_t)video_frame_buffer[0],
			(int)(std::uintptr_t)video_frame_buffer[1],
			(int)VIDEO_FRAME_BUFFER_BYTES) != 0;
}

void emscripten_stop_video_texture()
{
	video_texture_name.clear();
	video_frame_ready_index.store(-1, std::memory_order_relaxed);

	MAIN_THREAD_EM_ASM({
		var texturer = Module["luantiVideoTexture"];
		if (texturer && typeof texturer["stop"] === "function")
			texturer["stop"]();
	});
}

bool emscripten_poll_video_texture_frame(std::string *out_texture_name,
		const std::uint8_t **out_pixels, int *out_width, int *out_height)
{
	if (video_texture_name.empty())
		return false;

	const auto generation = video_frame_generation.load(std::memory_order_acquire);
	if (generation == 0 || generation == video_frame_consumed)
		return false;

	const int index = video_frame_ready_index.load(std::memory_order_acquire);
	if (index != 0 && index != 1)
		return false;

	video_frame_consumed = generation;
	*out_texture_name = video_texture_name;
	*out_pixels = video_frame_buffer[index];
	*out_width = video_frame_width.load(std::memory_order_relaxed);
	*out_height = video_frame_height.load(std::memory_order_relaxed);
	return true;
}

const EmscriptenInputProbe &emscripten_input_probe()
{
	// Function-local static: thread-safe one-time initialisation. The probe is
	// fixed by the launcher before callMain, so it never needs refreshing.
	static const EmscriptenInputProbe probe = [] {
		EmscriptenInputProbe p;
		// bit 0: coarse pointer; remaining bits: maxTouchPoints (clamped)
		int packed = MAIN_THREAD_EM_ASM_INT({
			var input = Module["luantiInput"];
			if (!input)
				return 0;
			var points = Math.max(0, Math.min(255, input["maxTouchPoints"] | 0));
			return (points << 1) | (input["coarsePointer"] ? 1 : 0);
		});
		p.coarse_pointer = (packed & 1) != 0;
		p.max_touch_points = packed >> 1;
		return p;
	}();
	return probe;
}

} // namespace porting

#endif // __EMSCRIPTEN__
