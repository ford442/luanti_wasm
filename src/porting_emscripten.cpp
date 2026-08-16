// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2024-2026 The Luanti Contributors

#ifdef __EMSCRIPTEN__

#include "porting_emscripten.h"

#include "porting.h"

#include <atomic>
#include <cstdlib>
#include <cstdint>
#include <emscripten.h>
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
std::uint64_t last_ordinary_start_ms = 0;

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

} // namespace

extern "C" {

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
}

void emscripten_service_browser_frame()
{
	emscripten_service_persistence();
}

void emscripten_prepare_canvas_present()
{
	// Intentionally empty. Re-showing the loading shell every frame fought
	// frame presentation and left the UI stuck on "World ready". Commit happens
	// in CIrrDeviceSDL::SwapWindow via emscripten_webgl_commit_frame().
}

void emscripten_finish_canvas_present()
{
	MAIN_THREAD_EM_ASM({
		var launcher = Module["luantiLauncher"];
		if (launcher && typeof launcher["notifyFramePresented"] === "function")
			launcher["notifyFramePresented"]();
	});
}

void emscripten_report_status(const std::string &message, int percent,
		const char *phase)
{
	static std::string last_message;
	static std::string last_phase;
	static int last_percent = -2;
	const std::string phase_string = phase ? phase : "";
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

} // namespace porting

#endif // __EMSCRIPTEN__
