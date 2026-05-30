# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**luanti_wasm** is a downstream fork of [Luanti](https://github.com/luanti-org/luanti) (formerly Minetest), a C++17 voxel game engine, being ported to WebAssembly via Emscripten to run in web browsers. The primary goal is a playable singleplayer experience (main menu → create/load world → place/break blocks) that persists across page reloads.

WASM-specific code lives in `#ifdef __EMSCRIPTEN__` blocks. Native builds (Linux/Windows/macOS) must remain unchanged.

## Build Commands

### Native Build (Linux)
```bash
cmake -B build -DCMAKE_BUILD_TYPE=Debug -DRUN_IN_PLACE=TRUE -DBUILD_SERVER=TRUE
cmake --build build --parallel $(($(nproc) + 1))
```

### WASM Build (Emscripten)
```bash
# Activate Emscripten first
source /path/to/emsdk/emsdk_env.sh

emcmake cmake --preset Emscripten -B build-wasm
emmake cmake --build build-wasm --parallel $(($(nproc) + 1))
# Output: build-wasm/bin/luanti.{html,js,wasm,data}
```

### Serve WASM Output (required for pthreads/SharedArrayBuffer)
```python
# serve.py
import http.server, socketserver
class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        super().end_headers()
socketserver.TCPServer(("", 8000), Handler).serve_forever()
```
Open `http://localhost:8000/build-wasm/bin/luanti.html`.

### Tests
```bash
# C++ unit tests (native only)
./bin/luanti --run-unittests

# Lua tests
busted builtin
luacheck builtin
luacheck --config=games/devtest/.luacheckrc games/devtest

# Integration tests
./util/test_multiplayer.sh
xvfb-run ./util/test_singleplayer.sh
```

### C++ Lint
```bash
cmake -B build -DCMAKE_BUILD_TYPE=Debug -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
      -DRUN_IN_PLACE=TRUE -DENABLE_GETTEXT=FALSE -DBUILD_SERVER=TRUE
cmake --build build --target GenerateVersion
./util/ci/run-clang-tidy.py -clang-tidy-binary=clang-tidy-15 -p build \
      -quiet -config="$(cat .clang-tidy)" 'src/.*'
```

## Architecture

### Engine Overview
Even in singleplayer, Luanti runs an internal server. The client and server communicate over a UDP-based protocol — stubs in `src/network/socket.cpp` replace the real socket with no-ops under Emscripten so the internal singleplayer path works without real networking.

```
src/
  server.cpp/h          – Server class (main server logic)
  client/               – Client-only (rendering, HUD, sound, input)
  server/               – Server-only (SAOs, bans, client interface, mod loading)
  network/              – Networking protocol; socket.cpp stubbed for WASM
  mapgen/               – Map generation algorithms
  script/cpp_api/       – C++ ↔ Lua bridge (s_*.cpp)
  script/lua_api/       – Lua-callable modules (l_*.cpp)
  database/             – SQLite3/PostgreSQL/LevelDB/Redis backends
  threading/            – pthreads wrappers; setName/bindToProcessor no-op'd for WASM
  util/                 – String, serialization, and other utilities
  porting.cpp/h         – Platform paths & abstractions; WASM returns virtual FS paths
  porting_emscripten.cpp/h  – IDBFS mount + syncfs (WASM-only)
  main.cpp              – Entry point; calls emscripten_init_filesystem() under WASM
  client/clientlauncher.cpp  – The blocking game loop (Phase 3 work target)
  client/game.cpp       – Inner game loop (Phase 3 work target)
irr/                    – IrrlichtMt rendering engine (embedded CMake subproject)
builtin/                – Lua code loaded by the engine at runtime
lib/                    – Bundled third-party libraries (Lua 5.1, sha256, etc.)
games/devtest/          – Development test game
client/shaders/         – GLSL shaders (must be valid GLES2/WebGL)
```

### Key WASM Files
| File | Purpose |
|------|---------|
| `CMakePresets.json` | "Emscripten" preset (toolchain + flags) |
| `src/CMakeLists.txt` | `elseif(EMSCRIPTEN)` branches ~line 327, 512, 774 |
| `src/porting_emscripten.cpp/h` | IDBFS mount, `emscripten_sync_filesystem()` |
| `src/porting.cpp` | Sets `path_share="/"`, `path_user="/home/web_user/.luanti"` under WASM |
| `src/network/socket.cpp` | Full no-op `UDPSocket` under `#ifdef __EMSCRIPTEN__` |
| `src/threading/thread.cpp` | No-op `setName()` / `bindToProcessor()` for Emscripten |

### WASM Phase Plan (from `wasm_porting.md`)
- **Phase 1** ✓ — CMake + compile, socket stubs, threading, porting, FS init
- **Phase 2** — Asset preloading, IDBFS persistence, worlds save across reloads
- **Phase 3** — Async main loop (`emscripten_set_main_loop` or ASYNCIFY)
- **Phase 4** — Multiplayer via WebRTC DataChannels + signaling server
- **Phase 5** — Sound (Emscripten OpenAL port)
- **Phase 6** — Input polish (pointer lock, touch, fullscreen)
- **Phase 7** — Optimization (binary size, memory tuning, CI/CD)

## Code Style

### C++ Conventions
- Every `.cpp`/`.h` starts with:
  ```cpp
  // Luanti
  // SPDX-License-Identifier: LGPL-2.1-or-later
  // Copyright (C) <year> <author>
  ```
- Indentation: **tabs** (width 4). No spaces in C++, CMake, Lua, or GLSL.
- Use `#pragma once` (never `#ifndef` guards).
- Use `DISABLE_CLASS_COPY(ClassName)` / `ALLOW_CLASS_MOVE(ClassName)` macros.
- Logging: `infostream`, `verbosestream`, `warningstream`, `errorstream` — never `std::cout`/`std::cerr`.
- Client-only headers: `#if !IS_CLIENT_BUILD` / `#error` guard. Server-only: `IS_SERVER_BUILD`.

### WASM Change Discipline
- Guard every WASM-specific change with `#ifdef __EMSCRIPTEN__` (C++) or `if(EMSCRIPTEN)` (CMake).
- Keep native builds working — changes to shared code must not break Linux/Windows/macOS.
- Call `emscripten_sync_filesystem()` after any write to `path_user` (world save, settings, player data).

### Commit Messages
- Present tense, capital first letter, ≤70 chars on first line, no trailing period.
- One logical change per branch (not `master`).

## Do Not Modify Manually
- `minetest.conf.example` and `settings_translation_file.cpp` — regenerated pre-release.
- `po/*.po` / `luanti.pot` — update with `util/updatepo.sh`.
- `VERSION_MAJOR/MINOR/PATCH` in `CMakeLists.txt` — use `util/bump_version.sh`.

## Reference Docs
- `wasm_porting.md` — authoritative WASM phase plan, blocker analysis, build flag reference
- `grok.md` — WASM context and current priorities
- `AGENTS.md` — full Luanti contributor rules, directory structure, test strategy
- `doc/lua_api.md` — server Lua API reference
- `doc/protocol.md` — network protocol specification
- `minetest.conf.example` — all configuration options
