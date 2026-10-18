// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 The Luanti Contributors

#include <SDL.h>
#include <emscripten.h>
#include <emscripten/html5.h>
#include <emscripten/threading.h>

#include <atomic>

namespace {

std::atomic<unsigned int> mouse_callbacks{0};

EM_BOOL on_mouse_down(int, const EmscriptenMouseEvent *, void *)
{
	mouse_callbacks.fetch_add(1, std::memory_order_relaxed);
	emscripten_request_pointerlock("#canvas", true);
	return EM_TRUE;
}

} // namespace

int main()
{
	const bool worker_main = !emscripten_is_main_browser_thread();
	if (SDL_Init(SDL_INIT_VIDEO) != 0)
		return 1;

	SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 2);
	SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 0);
	SDL_Window *window = SDL_CreateWindow("Luanti worker-main probe",
			SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, 320, 200,
			SDL_WINDOW_OPENGL | SDL_WINDOW_SHOWN);
	SDL_GLContext context = window ? SDL_GL_CreateContext(window) : nullptr;
	const bool webgl = context != nullptr;

	emscripten_set_mousedown_callback("#canvas", nullptr, true, on_mouse_down);
	MAIN_THREAD_EM_ASM({
		var probe = window["luantiMainLoopProbe"];
		probe["ticksAtReady"] = probe["browserTicks"];
		probe["ready"] = true;
		probe["workerMain"] = !!$0;
		probe["webgl"] = !!$1;
	}, worker_main, webgl);

	// Deliberately keep the native call stack blocked. With
	// PROXY_TO_PTHREAD, the browser heartbeat and input callbacks continue.
	const double deadline = emscripten_get_now() + 1500.0;
	while (emscripten_get_now() < deadline) {
		SDL_Event event;
		while (SDL_PollEvent(&event)) {
		}
		SDL_GL_SwapWindow(window);
		emscripten_thread_sleep(16);
	}

	EmscriptenPointerlockChangeEvent pointerlock{};
	const bool locked = emscripten_get_pointerlock_status(&pointerlock) ==
			EMSCRIPTEN_RESULT_SUCCESS && pointerlock.isActive;
	MAIN_THREAD_EM_ASM({
		var probe = window["luantiMainLoopProbe"];
		probe["mouseCallbacks"] = $0;
		probe["pointerLock"] = !!$1;
		probe["ticksAtDone"] = probe["browserTicks"];
		probe["done"] = true;
	}, mouse_callbacks.load(std::memory_order_relaxed), locked);

	if (context)
		SDL_GL_DeleteContext(context);
	if (window)
		SDL_DestroyWindow(window);
	SDL_Quit();
	return worker_main && webgl ? 0 : 2;
}
