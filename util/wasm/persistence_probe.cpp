// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 The Luanti Contributors

#include <emscripten.h>
#include <emscripten/threading.h>

int main()
{
	const bool worker_main = !emscripten_is_main_browser_thread();
	MAIN_THREAD_EM_ASM({
		var persistence = Module["luantiPersistence"];
		var state = persistence ? persistence["getState"]() : null;
		var probe = {};
		probe["mainStarted"] = true;
		probe["workerMain"] = !!$0;
		probe["storageStateAtMain"] = state ? state["state"] : null;
		Module["luantiPersistenceProbe"] = probe;
	}, worker_main);
	return 0;
}
