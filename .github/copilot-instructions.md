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
