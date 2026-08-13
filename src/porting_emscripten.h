// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2024-2026 The Luanti Contributors

#pragma once

#include <cstdint>

namespace porting {

enum class EmscriptenPersistenceReason : std::uint8_t {
	Periodic,
	Settings,
	Disconnect,
	Shutdown,
};

#ifdef __EMSCRIPTEN__

// PROXY_TO_PTHREAD must place the synchronous launcher/game stack on an
// application worker. Fail early if the browser build contract regresses.
void emscripten_validate_main_loop();
void emscripten_service_browser_frame();

// Save paths on any engine thread only record committed work. The application
// worker calls emscripten_service_persistence() while pumping frames and the
// service forwards eligible generations to the browser main thread.
void emscripten_mark_persistence_dirty(EmscriptenPersistenceReason reason,
		bool urgent = false);
void emscripten_service_persistence();

// Runtime state used by the graceful-shutdown driver. A failed sync remains
// pending because the JavaScript service retries it in the background.
bool emscripten_persistence_pending();
bool emscripten_persistence_error();
void emscripten_wait_for_persistence();

#else

inline void emscripten_validate_main_loop()
{
}

inline void emscripten_service_browser_frame()
{
}

inline void emscripten_mark_persistence_dirty(
		EmscriptenPersistenceReason, bool = false)
{
}

inline void emscripten_service_persistence()
{
}

inline bool emscripten_persistence_pending()
{
	return false;
}

inline bool emscripten_persistence_error()
{
	return false;
}

inline void emscripten_wait_for_persistence()
{
}

#endif

} // namespace porting
