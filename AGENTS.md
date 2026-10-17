# Luanti WASM — Agent Development Guide

This file contains essential information for AI coding agents working on the Luanti WASM codebase.

**Luanti** (formerly Minetest) is a free open-source voxel game engine with easy modding and game creation.
**This repository (`luanti_wasm`) is a downstream fork** actively porting Luanti to WebAssembly via Emscripten so it runs in web browsers.

Most engine code is identical to upstream Luanti; WASM-specific code lives in guarded `#ifdef __EMSCRIPTEN__` blocks.

---

## Project Overview

- **Name**: Luanti (CMake project name: `luanti`)
- **Version**: 5.18.0-dev (development build; see `VERSION_*` in `CMakeLists.txt`)
- **License**: LGPL-2.1-or-later
- **Language**: C++17 (minimum GCC 7.5 or Clang 7.0.1)
- **Build System**: CMake (minimum 3.12; 3.20 for Android)
- **Primary Platforms**: Linux, Windows, macOS, Android, **WebAssembly (Emscripten)**
- **Graphics**: IrrlichtMt (embedded CMake subproject in `irr/`), GLES2/WebGL in browser

The engine consists of a client and a server. The client target (`luanti`) always includes the server code. A dedicated server binary (`luantiserver`) can be built separately. Modding and game logic are driven by an embedded Lua interpreter.

The WASM port targets a **client-only browser build** (internal server for singleplayer; multiplayer via a WebSocket proxy in `util/wasm/proxy/`).

---

## Technology Stack & Key Dependencies

### Required
- CMake
- Lua 5.1+ or LuaJIT (system-wide PUC Lua is no longer supported for C++ interop reasons)
- GMP
- JsonCPP
- SQLite3
- ZLIB
- Zstd
- libzip 1.7.2+ (no Emscripten port — build it with `util/wasm/build_libzip.sh`)
- Freetype (client builds only)

### Optional (Native Builds)
- **Sound**: OpenAL + Vorbis (`ENABLE_SOUND`, default ON for client)
- **Networking/HTTP**: cURL (`ENABLE_CURL`, default ON)
- **Internationalization**: Gettext (`ENABLE_GETTEXT`, default ON for client)
- **Graphics variants**: OpenGL, OpenGL ES (`ENABLE_GLES2`)
- **Database backends**: PostgreSQL, LevelDB, Redis
- **Metrics**: Prometheus (`ENABLE_PROMETHEUS`)
- **Spatial indexing**: SpatialIndex (`ENABLE_SPATIAL`)
- **Crypto acceleration**: OpenSSL 3.0+ (`ENABLE_OPENSSL`)
- **Profiling**: Tracy (`BUILD_WITH_TRACY`)

### WASM / Emscripten Specifics
- **Graphics**: GLES2 via `-sFULL_ES2=1 -sMAX_WEBGL_VERSION=2`, rendered through WebGL
- **Windowing / Input**: SDL2 via Emscripten port (`-sUSE_SDL=2`)
- **Threading**: pthreads (`-pthread -sSHARED_MEMORY=1`), requires COOP/COEP headers; engine runs off the UI thread via `-sPROXY_TO_PTHREAD=1 -sOFFSCREEN_FRAMEBUFFER=1`
- **Memory**: 256 MB initial, 1 GB max (`-sALLOW_MEMORY_GROWTH=1`)
- **File System**: MEMFS for runtime, IDBFS for persistence, `--preload-file` for assets
- **Networking**: In-process loopback for singleplayer; remote servers via WebSocket proxy (`src/network/socket.cpp`, `client/web/network.js`, `util/wasm/proxy/`)
- **Sound**: Enabled (`ENABLE_SOUND=TRUE` in the preset; Emscripten Ogg/Vorbis ports)

### Bundled Libraries (in `lib/`)
- `bitop` — Lua bit operations (used when not using LuaJIT)
- `lstrpack` — Lua string packing
- `sha256` — SHA-256 implementation
- `catch2` — C++ testing framework (built when tests/benchmarks enabled)
- `tiniergltf` — glTF support

---

## Directory Structure

```
.
├── src/                    # Main C++ source code
│   ├── client/             # Client-only code (rendering, input, audio, shaders)
│   ├── server/             # Server-only code
│   ├── script/             # Lua scripting API and bindings (common, client, server, SSCSM)
│   ├── gui/                # GUI code
│   ├── network/            # Networking protocol implementation (UDP sockets, connection, packets)
│   ├── content/            # Content management (nodes, items, textures)
│   ├── database/           # Database backends (SQLite3, PostgreSQL, LevelDB, Redis)
│   ├── mapgen/             # Map generation
│   ├── threading/          # Threading utilities
│   ├── util/               # General utilities
│   ├── irrlicht_changes/   # Patches/modifications to IrrlichtMt
│   ├── unittest/           # C++ unit tests (Catch2)
│   ├── test/               # Additional C++ test helpers/fixtures
│   ├── benchmark/          # C++ benchmarks (Catch2)
│   ├── porting_emscripten.cpp  # WASM-specific FS init / IDBFS sync
│   ├── porting_emscripten.h
│   └── *.cpp / *.h         # Shared engine code (map, environment, player, etc.)
├── builtin/                # Lua code shipped with the engine
│   ├── client/             # Client-side Lua
│   ├── game/               # Server-side/game Lua logic
│   ├── common/             # Shared Lua utilities and tests
│   ├── mainmenu/           # Main menu Lua code
│   ├── async/              # Async environment Lua code
│   ├── emerge/             # Map generation async Lua
│   ├── profiler/           # Built-in profiler Lua
│   ├── pause_menu/         # Pause menu Lua code
│   ├── fstk/               # Formspec toolkit
│   ├── sscsm_client/       # Server-Sent Client-Side Mods (client)
│   └── sscsm_server/       # Server-Sent Client-Side Mods (server)
├── irr/                    # IrrlichtMt graphics engine (CMake subproject)
├── lib/                    # Bundled third-party libraries
├── games/                  # Bundled games: devtest, luanti_web (web default), flower_island, rollercoaster, log_ride, spire_tunnel
├── mods/                   # Mod installation directory placeholder
├── textures/               # Base textures and texture packs
├── client/                 # Client data (shaders, serverlist); client/web/ = browser shell, launcher/PWA, network.js, persistence.js, theater.js
├── doc/                    # Documentation (API refs, compiling guides, protocol spec)
├── docs/                   # **WASM-specific docs**
│   ├── wasm-investigation-paradust.md  # Analysis of prior art (paradust7/minetest-wasm)
│   └── wasm-issues/                    # Roadmap issues 00–08 (persistence, proxy, async loop, launcher, CI, showcase, theater)
├── po/                     # Translation files (gettext)
├── android/                # Android build files
├── cmake/Modules/          # Custom CMake modules
├── util/                   # Build scripts, CI helpers, test scripts (util/wasm/: serve, libzip, packaging, proxy, browser tests)
├── .github/workflows/      # GitHub Actions CI definitions
├── wasm_porting.md         # **Master living plan for the WASM port**
└── grok.md                 # Grok AI assistant guide for this repo
```

---

## Build Commands

### Quick Start (Linux typical — Native)
```bash
# Client + Server + Unit Tests (Debug)
cmake -B build -DCMAKE_BUILD_TYPE=Debug -DRUN_IN_PLACE=TRUE
cmake --build build --parallel $(($(nproc) + 1))
```

### Emscripten / WebAssembly Build
```bash
# Activate Emscripten SDK first (CI pins 6.0.3)
source /path/to/emsdk/emsdk_env.sh

# Once per SDK / EM_CACHE: libzip has no Emscripten port
util/wasm/build_libzip.sh

# Use the provided preset (binaryDir is build-wasm)
cmake --preset Emscripten
cmake --build build-wasm --parallel $(($(nproc) + 1))
# or: npm run build
```
Full guide: `doc/compiling/wasm.md`.

The `Emscripten` preset (defined in `CMakePresets.json`) configures:
- Release, client-only (`BUILD_CLIENT=TRUE`, `BUILD_SERVER=FALSE`, `BUILD_UNITTESTS=FALSE`)
- GLES2 rendering (`ENABLE_GLES2=TRUE`, `ENABLE_OPENGL=FALSE`, `ENABLE_OPENGL3=FALSE`)
- Sound enabled; disabled features not available in browser: curl, gettext, curses, PostgreSQL, LevelDB, Redis, Prometheus, Spatial, OpenSSL
- pthreads + shared memory
- Asset preloading is set in `src/CMakeLists.txt` (`--preload-file`: `builtin`, all bundled `games/*`, `textures`, `fonts`, `client/shaders`, `clientmods`) — that list is the source of truth

### Presets (from `CMakePresets.json`)
- `Debug` — debug symbols, no optimization
- `Release` — optimized, no debug symbols
- `RelWithDebInfo` — optimized with debug symbols
- `MinSizeRel` — minimal code size
- `Emscripten` — **WebAssembly client build**

There is also a custom `SemiDebug` build type (`-O1 -g -Wall`) defined in `src/CMakeLists.txt`.

### Common CMake Options
| Option | Default | Description |
|--------|---------|-------------|
| `BUILD_CLIENT` | `TRUE` | Build the client executable |
| `BUILD_SERVER` | `FALSE` | Build the dedicated server executable |
| `BUILD_UNITTESTS` | `TRUE` | Build unit tests into the binaries |
| `BUILD_BENCHMARKS` | `FALSE` | Build benchmarks |
| `RUN_IN_PLACE` | `TRUE` on Windows, `FALSE` on Unix | Run directly from source/build tree |
| `ENABLE_LTO` | `TRUE` (except Win/GCC, Apple) | Link-time optimization |
| `ENABLE_SOUND` | `TRUE` | Enable OpenAL/Vorbis sound |
| `ENABLE_CURL` | `TRUE` | Enable cURL support |
| `ENABLE_GETTEXT` | `TRUE` (client) | Enable localization |
| `ENABLE_OPENSSL` | `TRUE` | Use OpenSSL for SHA acceleration |
| `BUILD_WITH_TRACY` | `FALSE` | Fetch and link Tracy profiler |

### CI Build Reference
The project uses `util/ci/build.sh`, which runs:
```bash
cmake -B build \
    -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE:-Debug} \
    -DENABLE_LTO=FALSE \
    -DRUN_IN_PLACE=TRUE \
    -DENABLE_GETTEXT=${CMAKE_ENABLE_GETTEXT:-TRUE} \
    -DBUILD_SERVER=${CMAKE_BUILD_SERVER:-TRUE} \
    ${CMAKE_FLAGS}
cmake --build build --parallel $(($(nproc) + 1))
```

### Output Binaries
- `bin/luanti` — client (and embedded server)
- `bin/luantiserver` — dedicated server
- `build-wasm/bin/luanti.html` — **WASM browser build**
- `build-wasm/bin/luanti.wasm` — compiled engine
- `build-wasm/bin/luanti.data` — preloaded asset bundle
- `build-wasm/bin/{launcher.js,launcher.css,launcher-config.js,theater.js,videotexture.js,manifest.webmanifest,service-worker.js}` — launcher/PWA companions copied from `client/web/`

---

## Test Commands

### C++ Unit Tests
The unit tests are compiled into the executables when `BUILD_UNITTESTS=TRUE` (default).
```bash
# Run all C++ unit tests
./bin/luanti --run-unittests

# Or from the server binary
./bin/luantiserver --run-unittests
```

### C++ Benchmarks
Build with `-DBUILD_BENCHMARKS=1`, then run the binary with the benchmark flag (Catch2 CLI).

### Lua Unit Tests
Uses the **busted** framework on Lua 5.1 / LuaJIT.
```bash
# Run Lua tests in builtin/
busted builtin

# Run with LuaJIT explicitly
busted builtin --lua=/path/to/luajit
```

### Lua Linting
Uses **luacheck**.
```bash
luacheck builtin
luacheck --config=games/devtest/.luacheckrc games/devtest
```

### Integration Tests
```bash
# Multiplayer integration test (requires built client + server)
./util/test_multiplayer.sh

# Singleplayer integration test (requires X11 or xvfb for headless)
clientconf="video_driver=opengl3" xvfb-run ./util/test_singleplayer.sh

# Error case testing
./util/test_error_cases.sh
```

### WASM Browser Tests
Playwright 1.59.0 + Chrome, against a built `build-wasm/bin` (see `.github/workflows/wasm.yml`).
```bash
python3 util/wasm/test_client_browser.py --browser "$(command -v google-chrome)"
python3 util/wasm/test_first_playable.py --browser "$(command -v google-chrome)" --screenshot-dir wasm-gate-screenshots
python3 util/wasm/test_demo_tools.py        # packaging/deploy tooling
(cd util/wasm/proxy && npm test)             # WebSocket proxy (node --test)
```
Other probes live in `util/wasm/test_*.py` / `test_persistence.mjs`. The root `test_wasm.js` (Puppeteer/Express) is an older ad-hoc smoke test.

### C++ Linting
Uses **clang-tidy** (CI uses version 15).
```bash
CLANG_TIDY=clang-tidy-15 ./util/ci/clang-tidy.sh
```

---

## Code Style Guidelines

### C++
- **License header**: Every source file must start with:
  ```cpp
  // Luanti
  // SPDX-License-Identifier: LGPL-2.1-or-later
  // Copyright (C) YYYY Name <email>
  ```
- **Indentation**: Tabs (not spaces)
- **Warnings**: `-Wall -Wextra -Wno-unused-parameter -Werror=vla`
- **`struct`/`class` mismatch**: Treated as error on compilers that support `-Werror=mismatched-tags`
- **Naming**: Follow existing conventions in the surrounding module; the codebase uses a mix of `snake_case` and `CamelCase` depending on age and subsystem.
- **Build target macro**: `MT_BUILDTARGET` is defined as `1` for client, `2` for server. Code should use `CHECK_CLIENT_BUILD()` where appropriate.
- **Platform guards**: Use `#ifdef __EMSCRIPTEN__` for WASM-specific code. Keep platform-specific changes minimal and isolated (prefer new files like `porting_emscripten.cpp`).

### Lua
- Configuration is in `.luacheckrc`.
- The global `core` table is the engine API namespace.
- Read-only globals provided by the engine include `dump`, `vector`, `vector2`, `Settings`, `ItemStack`, `VoxelArea`, `VoxelManip`, `profiler`, etc.
- Do not introduce new globals without updating `.luacheckrc`.

---

## Testing & CI Strategy

- **C++ changes** trigger:
  - Linux builds (GCC 9/14, Clang 11/20, ARM64)
  - Windows, macOS, Android builds
  - `clang-tidy` linting
  - C++ unit tests, integration tests, error-case tests
- **Lua changes** trigger:
  - `luacheck` linting
  - `busted` unit tests
  - Integration tests via `util/test_multiplayer.sh` and `util/test_singleplayer.sh`
- **Asset changes** trigger PNG and whitespace checks.
- **WASM-relevant changes** (`src/`, `irr/`, `builtin/`, `client/`, `games/luanti_web/`, `util/wasm/`, …) trigger `wasm.yml`: Emscripten Release build, browser smoke, first-playable gate, `package_demo.py`, and Cloudflare Pages deploy on the default branch.

Key workflow files:
- `.github/workflows/linux.yml`
- `.github/workflows/lua.yml`
- `.github/workflows/cpp_lint.yml`
- `.github/workflows/windows.yml`
- `.github/workflows/macos.yml`
- `.github/workflows/android.yml`
- `.github/workflows/wasm.yml`

---

## Runtime Architecture Notes

- **Client-Server Model**: Even in singleplayer, the engine runs an internal server. The network protocol is documented in `doc/protocol.md`.
- **Content Loading**: At runtime the engine loads games from `games/`, mods from `mods/`, textures from `textures/`, and saves worlds to `worlds/`.
- **Scripting**: Lua is deeply embedded. The C++ side exposes an API to Lua (`src/script/`). Lua drives game logic, main menus, and client-side mods.
- **Database Abstraction**: Map data and player data can be stored in SQLite3 (default), PostgreSQL, LevelDB, or Redis. See `src/database/`.
- **Graphics**: Rendering is handled by IrrlichtMt. Client shaders live in `client/shaders/`.

### WASM-Specific Architecture

- **File System**: Read-only assets are bundled at link time via `--preload-file`. Read-write user data (`worlds/`, `minetest.conf`) is stored in an IDBFS mount at `/home/web_user/.luanti/`.
- **Persistence**: `porting::emscripten_sync_filesystem()` must be called after world saves, settings changes, or periodically to flush IDBFS to IndexedDB.
- **Rendering**: Uses GLES2 → WebGL via Emscripten's SDL2 port. IrrlichtMt already contains partial Emscripten support.
- **Threading**: pthreads are supported but require `SHARED_MEMORY` and correct COOP/COEP headers on the serving page.
- **Networking**: Native UDP is unavailable in browsers. The Emscripten `UDPSocket` delivers singleplayer traffic in-process and sends remote traffic through a WebSocket proxy that wraps Luanti's UDP protocol (`util/wasm/proxy/server.mjs`; run with `npm install && LUANTI_PROXY_ALLOWED_TARGETS=127.0.0.1:30000 npm start`). A deployed WSS proxy is still outstanding. See `docs/wasm-issues/02-websocket-proxy-networking.md`.
- **Main Loop**: The blocking native loops are kept; the engine runs on a pthread via `-sPROXY_TO_PTHREAD=1` + `-sOFFSCREEN_FRAMEBUFFER=1` (no ASYNCIFY / `emscripten_set_main_loop()`). Do not enable `OFFSCREENCANVAS_SUPPORT` (it blanked the game). See `docs/wasm-issues/03-async-main-loop.md`.

---

## Security Considerations

- The engine runs untrusted Lua code from mods and games. The sandbox model is critical; do not weaken Lua sandbox boundaries without thorough review.
- **SSCSM** (Server-Sent Client-Side Mods): Scripts come from the server (potentially malicious). They run in a Lua sandbox with limited API access. See `doc/sscsm_security.md`. In the browser context, untrusted mod code has additional security surface.
- Network protocol parsing must be robust against malicious clients/servers.
- File I/O from Lua is restricted; paths are validated before access.
- Serialization code (`src/serialization.cpp`) handles untrusted network and map data.
- Do not use `strcpy`, `sprintf`, or other unsafe C APIs. The project uses `snprintf`, `std::string`, and safe wrappers.
- **Browser-specific**: Any proxy networking transport will be a man-in-the-middle for game traffic. Plan for TLS (WSS) and validate proxy identity where possible.

---

## Known Issues / Blockers

- Read `wasm_porting.md` for current WASM-port status before planning work; outstanding items are a deployed TLS proxy / public-server multiplayer and cross-browser persistence acceptance.
- Recent commit history is dominated by WebGL-specific bugfixes (worker context creation, black wedges when looking down, leftover-vertex-buffer triangle artifacts, a WebGL shutdown crash). The GLES2/WebGL path through IrrlichtMt's Emscripten support is still the most fragile part of the port — expect more of this class of bug.
- `src/threading/thread.cpp:123` — `FIXME: what if this fails, or if already locked by same thread?` in the lock-acquisition path.
- Root-level `deploy.py` uploads `build-wasm/bin` to test.1ink.us via storage.noahcohn.com (token via `DEPLOY_TOKEN`); CI deploys separately to Cloudflare Pages.

## Useful Reference Files

- `wasm_porting.md` — **Master living plan for the WASM port** (read this first for WASM work)
- `grok.md` — Grok AI assistant guide tailored for this repo
- `docs/wasm-investigation-paradust.md` — Deep analysis of prior art (paradust7/minetest-wasm)
- `docs/wasm-issues/` — Roadmap issue files (persistence, proxy, async loop, launcher, CI, showcase, theater)
- `doc/compiling/wasm.md` — WASM build, smoke tests, packaging, common failures
- `doc/compiling/wasm-embedding.md` — Deep links, proxy regions, iframe/PWA embedding
- `doc/lua_api.md` — Server Lua API reference
- `doc/client_lua_api.md` — Client Lua API reference
- `doc/menu_lua_api.md` — Main menu Lua API reference
- `doc/protocol.md` — Network protocol specification
- `doc/world_format.md` — World database format
- `doc/texture_packs.md` — Texture pack documentation
- `doc/sscsm_security.md` — SSCSM security threat model
- `doc/compiling/` — Platform-specific compiling instructions
- `minetest.conf.example` — Available configuration options
- `util/bump_version.sh` — Version bumping script

---

## Quick Cheat Sheet

```bash
# Native: Configure and build (client + server + tests)
cmake -B build -DCMAKE_BUILD_TYPE=Debug -DRUN_IN_PLACE=TRUE -DBUILD_SERVER=TRUE
cmake --build build --parallel $(($(nproc) + 1))

# Native: Run C++ unit tests
./bin/luanti --run-unittests

# Native: Run Lua tests
busted builtin

# Native: Run Lua linter
luacheck builtin

# Native: Run integration tests
./util/test_multiplayer.sh
xvfb-run ./util/test_singleplayer.sh

# WASM: Build with Emscripten preset
source /path/to/emsdk/emsdk_env.sh
util/wasm/build_libzip.sh   # first time only
cmake --preset Emscripten
cmake --build build-wasm --parallel $(($(nproc) + 1))

# WASM: Serve build-wasm/bin with COOP/COEP headers (required for pthreads)
python3 util/wasm/serve.py
# Then open http://127.0.0.1:8000/luanti.html

# WASM: Browser smoke test
python3 util/wasm/test_client_browser.py --browser "$(command -v google-chrome)"
```

---

## Cursor Cloud specific instructions

Cloud Agent machines run `.cursor/install.sh` (from `.cursor/environment.json`) after checkout. The script is idempotent. It installs the native client/server build dependencies (including the optional LevelDB, Redis, PostgreSQL client, and SpatialIndex libraries CMake enables by default), Lua 5.1 `luacheck` and `busted` on `/usr/local/bin`, Playwright 1.59.0 for `util/wasm/test_*.py`, Node packages for the repo root and `util/wasm/proxy`, and Emscripten 6.0.3 at `$HOME/emsdk` (the same commit as `.github/workflows/wasm.yml`).

`/usr/bin/c++` on the base image is Clang, and it links against GCC 14's libstdc++. The install script pulls `g++-14` so a stock `cmake -B build` can link. `g++` (GCC 13) also works.

`/etc/profile.d/luanti-wasm.sh` exports `EMSDK` and puts `emcc` on `PATH`. Login shells and this image's session startup source it. The `Emscripten` CMake preset reads `$EMSDK` for its toolchain file, so if a shell does not have `EMSDK` set, run `source /etc/profile.d/luanti-wasm.sh` before `cmake --preset Emscripten`. `emcc` itself is also wrapped in `/usr/local/bin`.

Google Chrome for the WASM smoke tests is `/usr/local/bin/google-chrome`. Serve a built client with `python3 util/wasm/serve.py` (COOP/COEP); do not open `luanti.html` from a plain static server. Native configure, unit tests, and Lua checks use the cheat sheet above. The install script configures `build-wasm` once so Emscripten ports are cached; it does not compile the engine.
