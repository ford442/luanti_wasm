// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 The Luanti Contributors

#pragma once

#ifdef __EMSCRIPTEN__

// Emscripten's resolver assigns synthetic IPv4 addresses to host names.
// Register the association with the browser transport so the proxy can perform
// the real DNS lookup without changing Luanti's Address interface.
void websocket_proxy_register_hostname(const char *address, const char *hostname);

#else

inline void websocket_proxy_register_hostname(const char *, const char *)
{
}

#endif
