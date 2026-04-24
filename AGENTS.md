# Luanti — Agent Development Guide

This file contains essential information for AI coding agents working on the Luanti codebase.
Luanti (formerly Minetest) is a free open-source voxel game engine with easy modding and game creation.

---

## Project Overview

- **Name**: Luanti (CMake project name: `luanti`)
- **Version**: 5.16.0-dev (development build)
- **License**: LGPL-2.1-or-later
- **Language**: C++17 (minimum GCC 7.5 or Clang 7.0.1)
- **Build System**: CMake (minimum 3.12; 3.20 for Android)
- **Primary Platforms**: Linux, Windows, macOS, Android
- **Graphics**: IrrlichtMt (embedded CMake subproject in `irr/`)

The engine consists of a client and a server. The client target (`luanti`) always includes the server code. A dedicated server binary (`luantiserver`) can be built separately. Modding and game logic are driven by an embedded Lua interpreter.

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
- Freetype (client builds only)

### Optional
- **Sound**: OpenAL + Vorbis (`ENABLE_SOUND`, default ON for client)
- **Networking/HTTP**: cURL (`ENABLE_CURL`, default ON)
- **Internationalization**: Gettext (`ENABLE_GETTEXT`, default ON for client)
- **Graphics variants**: OpenGL, OpenGL ES (`ENABLE_GLES2`)
- **Database backends**: PostgreSQL, LevelDB, Redis
- **Metrics**: Prometheus (`ENABLE_PROMETHEUS`)
- **Spatial indexing**: SpatialIndex (`ENABLE_SPATIAL`)
- **Crypto acceleration**: OpenSSL 3.0+ (`ENABLE_OPENSSL`)
- **Profiling**: Tracy (`BUILD_WITH_TRACY`)

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
│   ├── script/             # Lua scripting API and bindings (common, client, server)
│   ├── gui/                # GUI code
│   ├── network/            # Networking protocol implementation
│   ├── content/            # Content management (nodes, items, textures)
│   ├── database/           # Database backends (SQLite3, PostgreSQL, LevelDB, Redis)
│   ├── mapgen/             # Map generation
│   ├── threading/          # Threading utilities
│   ├── util/               # General utilities
│   ├── irrlicht_changes/   # Patches/modifications to IrrlichtMt
│   ├── unittest/           # C++ unit tests (Catch2)
│   ├── test/               # Additional C++ test helpers/fixtures
│   ├── benchmark/          # C++ benchmarks (Catch2)
│   └── *.cpp / *.h         # Shared engine code (map, environment, player, etc.)
├── builtin/                # Lua code shipped with the engine
│   ├── client/             # Client-side Lua
│   ├── game/               # Server-side/game Lua logic
│   ├── common/             # Shared Lua utilities and tests
│   ├── mainmenu/           # Main menu Lua code
│   └── async/              # Async environment Lua code
├── irr/                    # IrrlichtMt graphics engine (CMake subproject)
├── lib/                    # Bundled third-party libraries
├── games/                  # Bundled games (e.g. devtest)
├── mods/                   # Mod installation directory placeholder
├── textures/               # Base textures and texture packs
├── client/                 # Client data (shaders, serverlist)
├── doc/                    # Documentation (API refs, compiling guides, protocol spec)
├── po/                     # Translation files (gettext)
├── android/                # Android build files
├── cmake/Modules/          # Custom CMake modules
├── util/                   # Build scripts, CI helpers, test scripts
└── .github/workflows/      # GitHub Actions CI definitions
```

---

## Build Commands

### Quick Start (Linux typical)
```bash
# Client + Server + Unit Tests (Debug)
cmake -B build -DCMAKE_BUILD_TYPE=Debug -DRUN_IN_PLACE=TRUE
cmake --build build --parallel $(($(nproc) + 1))
```

### Presets (from `CMakePresets.json`)
- `Debug` — debug symbols, no optimization
- `Release` — optimized, no debug symbols
- `RelWithDebInfo` — optimized with debug symbols
- `MinSizeRel` — minimal code size

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

### C++ Linting
Uses **clang-tidy** (CI uses version 15).
```bash
./util/ci/clang-tidy.sh
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

Key workflow files:
- `.github/workflows/linux.yml`
- `.github/workflows/lua.yml`
- `.github/workflows/cpp_lint.yml`
- `.github/workflows/windows.yml`
- `.github/workflows/macos.yml`
- `.github/workflows/android.yml`

---

## Runtime Architecture Notes

- **Client-Server Model**: Even in singleplayer, the engine runs an internal server. The network protocol is documented in `doc/protocol.md`.
- **Content Loading**: At runtime the engine loads games from `games/`, mods from `mods/`, textures from `textures/`, and saves worlds to `worlds/`.
- **Scripting**: Lua is deeply embedded. The C++ side exposes an API to Lua (`src/script/`). Lua drives game logic, main menus, and client-side mods.
- **Database Abstraction**: Map data and player data can be stored in SQLite3 (default), PostgreSQL, LevelDB, or Redis. See `src/database/`.
- **Graphics**: Rendering is handled by IrrlichtMt. Client shaders live in `client/shaders/`.

---

## Security Considerations

- The engine runs untrusted Lua code from mods and games. The sandbox model is critical; do not weaken Lua sandbox boundaries without thorough review.
- Network protocol parsing must be robust against malicious clients/servers.
- File I/O from Lua is restricted; paths are validated before access.
- Serialization code (`src/serialization.cpp`) handles untrusted network and map data.
- Do not use `strcpy`, `sprintf`, or other unsafe C APIs. The project uses `snprintf`, `std::string`, and safe wrappers.

---

## Useful Reference Files

- `doc/lua_api.md` — Server Lua API reference
- `doc/client_lua_api.md` — Client Lua API reference
- `doc/menu_lua_api.md` — Main menu Lua API reference
- `doc/protocol.md` — Network protocol specification
- `doc/world_format.md` — World database format
- `doc/texture_packs.md` — Texture pack documentation
- `doc/compiling/` — Platform-specific compiling instructions
- `minetest.conf.example` — Available configuration options
- `util/bump_version.sh` — Version bumping script

---

## Quick Cheat Sheet

```bash
# Configure and build (client + server + tests)
cmake -B build -DCMAKE_BUILD_TYPE=Debug -DRUN_IN_PLACE=TRUE -DBUILD_SERVER=TRUE
cmake --build build --parallel $(($(nproc) + 1))

# Run C++ unit tests
./bin/luanti --run-unittests

# Run Lua tests
busted builtin

# Run Lua linter
luacheck builtin

# Run integration tests
./util/test_multiplayer.sh
xvfb-run ./util/test_singleplayer.sh
```
