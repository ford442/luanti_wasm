# Luanti – Copilot Instructions

Luanti (formerly Minetest) is a C++17 voxel game engine with embedded Lua/LuaJIT scripting, built with CMake. The engine has a strict client/server split with a custom network protocol.

## Build & Test

### Build
```bash
cmake -B build -DCMAKE_BUILD_TYPE=Debug -DRUN_IN_PLACE=TRUE -DBUILD_SERVER=TRUE
cmake --build build --parallel $(nproc)
```
CMake presets (`Debug`, `Release`, `RelWithDebInfo`, `MinSizeRel`) are available via `--preset`.

Key optional flags:
- `-DBUILD_CLIENT=TRUE/FALSE` (default TRUE)
- `-DBUILD_SERVER=TRUE/FALSE` (default FALSE)
- `-DBUILD_UNITTESTS=TRUE` (default TRUE)
- `-DBUILD_BENCHMARKS=TRUE`

### Run all unit tests
```bash
./bin/luanti --run-unittests         # client build
./bin/luantiserver --run-unittests   # server-only build
```

### Run a single test module
Unit tests live in `src/unittest/test_*.cpp`. Each is a `TestBase` subclass auto-registered at startup. There is no direct per-file test runner; build with `BUILD_UNITTESTS=TRUE` and run the binary.

### Lua tests
```bash
# requires luarocks + busted + luacheck installed
luacheck builtin
busted builtin
luacheck --config=games/devtest/.luacheckrc games/devtest
```

### C++ lint (clang-tidy)
```bash
cmake -B build -DCMAKE_BUILD_TYPE=Debug -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
      -DRUN_IN_PLACE=TRUE -DENABLE_GETTEXT=FALSE -DBUILD_SERVER=TRUE
cmake --build build --target GenerateVersion
./util/ci/run-clang-tidy.py -clang-tidy-binary=clang-tidy-15 -p build \
      -quiet -config="$(cat .clang-tidy)" 'src/.*'
```
Enabled checks: `modernize-use-emplace`, `modernize-avoid-bind`, `misc-throw-by-value-catch-by-reference`, `performance-*` (minus `performance-avoid-endl`).

## Architecture

```
src/
  server.cpp/h          – Server class (main server logic)
  client/               – Client-only code (game loop, rendering, HUD, sound)
  server/               – Server-only helpers (SAOs, bans, client interface, mods)
  network/              – Connection, packet handling, protocol definitions
  mapgen/               – Map generation (v5, v6, v7, carpathian, valleys, …)
  script/
    cpp_api/            – C++ side of the scripting bridge (s_*.cpp/h)
    lua_api/            – Lua-callable API modules (l_*.cpp/h)
    scripting_server.h  – ServerScripting (composes all cpp_api modules)
    scripting_client.h  – ClientScripting
  unittest/             – C++ unit tests (test_*.cpp)
  util/                 – Shared utilities (string, threading, serialization, …)
irr/                    – Embedded IrrlichtMt fork (rendering, input, scene graph)
lib/                    – Bundled third-party libraries
builtin/                – Lua built-in code loaded by the engine
games/devtest/          – Development test game (used in integration tests)
client/shaders/         – GLSL shaders
```

The `IGameDef` interface (`src/gamedef.h`) is the primary game context object passed throughout both client and server code to access node definitions, item definitions, and craft definitions without coupling to `Server` or `Client` directly.

### Scripting layer
- **`src/script/cpp_api/s_*.cpp/h`** – Each file bridges one domain (entities, environment, inventory, …). These classes use virtual multiple inheritance to compose `ServerScripting` / `ClientScripting`.
- **`src/script/lua_api/l_*.cpp/h`** – Each file exposes one API module to Lua as a `ModApiXxx : ModApiBase` class with static `l_*` methods.
- `BUILTIN_MOD_NAME` is `"*builtin*"` — an intentionally invalid mod name used for security checks.

### Network
Protocol constants and opcode tables are in `src/network/networkprotocol.h`, `clientopcodes.cpp`, and `serveropcodes.cpp`. The MTP (Minetest Transport Protocol) is in `src/network/mtp/`.

## Key Conventions

### File headers
Every `.cpp` and `.h` file begins with:
```cpp
// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) <year> <author>
```

### Header guards
Use `#pragma once` — never `#ifndef` guards.

### Client/server guards
Client-only headers contain:
```cpp
#if !IS_CLIENT_BUILD
#error Do not include in server builds
#endif
```
Server-only headers use the equivalent `IS_SERVER_BUILD` guard.

### Indentation
Tabs (width 4) for C++, Lua, GLSL, and CMake. Spaces for Markdown. Configured in `.editorconfig`.

### Macros for class semantics
```cpp
DISABLE_CLASS_COPY(ClassName)   // deletes copy ctor and copy-assign
ALLOW_CLASS_MOVE(ClassName)     // adds default move ctor and move-assign
```

### Logging
Use the thread-local log streams (never `std::cout` / `std::cerr` in engine code):
```cpp
infostream    << "normal info" << std::endl;
verbosestream << "detailed debug" << std::endl;
warningstream << "something odd" << std::endl;
errorstream   << "error message" << std::endl;
dstream       // raw debug stream (goes to stderr in debug builds)
```

### Unit test macros
```cpp
UASSERT(condition)
UTEST(condition, fmt, ...)
UASSERTEQ(T, actual, expected)
UASSERTCMP(T, CMP, actual, expected)
EXCEPTION_CHECK(ExcType, code)
TEST(fn, ...)   // register a sub-test
```

### Commit messages
- Present tense, capital first letter, no trailing full stop.
- First line ≤ 70 characters; second line blank; subsequent lines describe details.
- One logical change per branch (not `master`).

## What Not to Touch Manually
- `minetest.conf.example` and `settings_translation_file.cpp` — regenerated pre-release.
- `po/*.po` / `luanti.pot` — updated with `util/updatepo.sh` pre-release.
- `VERSION_MAJOR/MINOR/PATCH` in `CMakeLists.txt` — use `util/bump_version.sh`.

## Style Guidelines
- C/C++: https://docs.luanti.org/for-engine-devs/code-style-guidelines/
- Lua: https://docs.luanti.org/for-engine-devs/lua-code-style-guidelines/
- Lua API reference: `doc/lua_api.md`

---

## WASM/Emscripten Porting (This Repository)

This fork targets WebAssembly (WASM) compilation via Emscripten to run Luanti in browsers. **Key differences from the upstream native build:**

### WASM-Specific Architecture
- **Browser Platform**: Runs in web workers and main thread via Emscripten's execution model
- **Networking**: UDP is replaced with a WebSocket proxy layer over emsocket + encapsulation (see `02-websocket-proxy-networking.md`)
- **File System**: Native file I/O replaced with IDBFS (IndexedDB-backed file system) for persistence across reloads
- **Main Loop**: Blocking `while` loops must yield control to browser via `emscripten_set_main_loop()` or async/await patterns (see `03-async-main-loop.md`)
- **Graphics**: IrrlichtMt already has Emscripten support (GLES2, SDL2 backend, EGL stubs)

### Build for WASM
```bash
# (Requires Emscripten SDK installed: emsdk)
# Build client with WASM toolchain (CMake cross-compile)
cmake -B build_wasm \
  -DCMAKE_TOOLCHAIN_FILE=$EMSDK/upstream/emscripten/cmake/Modules/Platform/Emscripten.cmake \
  -DCMAKE_BUILD_TYPE=Debug \
  -DBUILD_CLIENT=TRUE \
  -DBUILD_SERVER=FALSE \
  -DENABLE_SOUND=FALSE \
  -DENABLE_CURL=FALSE
cmake --build build_wasm --parallel $(nproc)
# Output: `build_wasm/bin/luanti.js` + `luanti.wasm`
```

### WASM-Specific Code Locations
- `wasm_porting.md` — Master technical porting guide (read first)
- `docs/wasm-issues/` — Modular issue breakdowns (MVP roadmap, persistence, networking, async loop, CI)
- `docs/wasm-investigation-paradust.md` — Analysis of prior art (paradust7/minetest WASM fork)
- IrrlichtMt Emscripten code: `irr/src/CIrrDeviceSDL.cpp`, `irr/src/os.cpp`, `irr/src/CEGLManager.cpp`

### Critical WASM Blockers
1. **Networking** — Browser cannot do UDP. Use WebSocket proxy (design in `02-websocket-proxy-networking.md`)
2. **Main Loop** — Blocking loops freeze the browser. Use `emscripten_set_main_loop()` with frame stepping (design in `03-async-main-loop.md`)
3. **Persistence** — Data must survive tab reload. Use IDBFS + automatic sync (design in `01-persistence-mvp.md`)
4. **Shared Library Linking** — Some native dependencies may not have WASM builds; static linking and conditional disable strategy required

### Platform Guards for WASM
Use `#ifdef __EMSCRIPTEN__` / `#if defined(__EMSCRIPTEN__)` to isolate browser-only code. Key modules:
- `src/network/` — Custom socket layer for WebSocket proxy
- `src/threading/` — May need adjustments for Emscripten's single-threaded model
- `src/client/clientlauncher.cpp` — Main loop integration

### Testing WASM Builds
```bash
# Run in Node.js (headless validation)
node build_wasm/bin/luanti.js --version

# Or in a browser (requires HTTP server; WebGL context needed)
python3 -m http.server 8000
# Then visit http://localhost:8000 with index.html that loads luanti.js/wasm
```

### MVP Roadmap (from `docs/wasm-issues/`)
1. **Persistence MVP** — Save/restore worlds via IDBFS (unblocks real play)
2. **Async Main Loop** — Non-blocking frame stepping (unblocks responsive UI)
3. **Proxy Networking** — WebSocket-bridged client-to-server (unlocks multiplayer)
4. **Build/CI + Public Demo** — Reproducible builds & testable artifacts
5. **Launcher & Embedding** — Web UX layer for sharing & integration

### Upstream Compatibility
- Stay on clean upstream Luanti `master` branch (do not fork)
- Minimal guarded platform layer (`#ifdef __EMSCRIPTEN__` only for real differences)
- Reuse proven patterns from paradust7's prior WASM work (emsocket design, WASMFS, etc.)
- Avoid divergence; periodic rebases on Luanti releases
