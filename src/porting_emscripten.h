// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2024 The Luanti Contributors

#pragma once

#ifdef __EMSCRIPTEN__

namespace porting {

// Set up IDBFS mount for persistent user data.  Must be called before the
// engine starts reading or writing to path_user.
void emscripten_init_filesystem();

// Flush in-memory FS changes back to IndexedDB.
void emscripten_sync_filesystem();

} // namespace porting

#endif // __EMSCRIPTEN__
