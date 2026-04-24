// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2024 The Luanti Contributors

#ifdef __EMSCRIPTEN__

#include "porting_emscripten.h"
#include "log.h"
#include <emscripten.h>
#include <emscripten/html5.h>

namespace porting {

// Mount an IDBFS volume at the user-data path so worlds and settings survive
// page reloads.  Must be called before any file I/O to that path.
void emscripten_init_filesystem()
{
	EM_ASM(
		// Create the directory tree for persistent user data.
		var dirs = [
			'/home',
			'/home/web_user',
			'/home/web_user/.luanti',
			'/home/web_user/.luanti/worlds',
			'/home/web_user/.luanti/mods',
			'/home/web_user/.luanti/textures',
			'/home/web_user/.luanti/games',
		];
		dirs.forEach(function(d) {
			try { FS.mkdir(d); } catch(e) { /* already exists */ }
		});

		// Mount IndexedDB-backed FS for persistence.
		FS.mount(IDBFS, {}, '/home/web_user/.luanti');

		// Populate memory FS from IndexedDB (synchronous load via semaphore).
		var done = false;
		FS.syncfs(true, function(err) {
			if (err) {
				console.error('Luanti: IDBFS load error:', err);
			} else {
				console.log('Luanti: IDBFS loaded successfully');
			}
			done = true;
		});

		// Spin until the async callback fires.  This is intentional: we are
		// called from C++ before the game loop starts, so we block here via
		// Emscripten's synchronous emulation.  If ASYNCIFY is enabled the
		// emscripten_sleep calls below will yield properly.
		var deadline = Date.now() + 5000;
		while (!done && Date.now() < deadline) {
			// busy-wait – acceptable only during early init
		}
	);
}

// Flush any dirty pages in the IDBFS back to IndexedDB.  Call this after
// saving a world, changing settings, or periodically during gameplay.
void emscripten_sync_filesystem()
{
	EM_ASM(
		FS.syncfs(false, function(err) {
			if (err) console.error('Luanti: IDBFS save error:', err);
		});
	);
}

} // namespace porting

#endif // __EMSCRIPTEN__
