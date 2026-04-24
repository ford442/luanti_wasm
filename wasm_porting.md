# Luanti Emscripten / WebAssembly Porting Guide

This document describes the current state, blockers, and step-by-step plan for building Luanti (formerly Minetest) with Emscripten to run in web browsers via WebAssembly (WASM).

---

## Table of Contents

1. [Current State](#current-state)
2. [High-Level Architecture](#high-level-architecture)
3. [Blockers & Challenges](#blockers--challenges)
4. [Step-by-Step Implementation Plan](#step-by-step-implementation-plan)
5. [Build Instructions (Target)](#build-instructions-target)
6. [Files Requiring Changes](#files-requiring-changes)
7. [Dependency Notes](#dependency-notes)
8. [Networking Deep Dive](#networking-deep-dive)
9. [File System Strategy](#file-system-strategy)
10. [Rendering & Shaders](#rendering--shaders)
11. [Testing Strategy](#testing-strategy)
12. [Appendix: Useful Emscripten Flags](#appendix-useful-emscripten-flags)

---

## Current State

### What Already Works

- **IrrlichtMt** (the embedded graphics engine in `irr/`) already has **partial Emscripten support**:
  - `irr/src/CMakeLists.txt` detects `EMSCRIPTEN` and sets `_IRR_EMSCRIPTEN_PLATFORM_` and `_IRR_COMPILE_WITH_EGL_MANAGER_`
  - `irr/src/CIrrDeviceSDL.cpp/h` contain Emscripten-specific pointer-lock and event handling code
  - `irr/src/os.cpp` uses `emscripten_log()` and `emscripten_get_now()` for logging and timing
  - `irr/src/CEGLManager.cpp` has Emscripten EGL stubs
  - GLES2 is enabled by default for Emscripten
  - SDL2 device backend is used (Emscripten has excellent SDL2 port support)

### What Does NOT Work

- The **main Luanti engine** (`src/`) has **zero Emscripten-specific code**
- No Emscripten build preset or toolchain file exists
- The networking, file system, threading, and main loop are all designed for native desktop/server platforms

---

## High-Level Architecture

Luanti is a C++17 client-server engine. Even singleplayer runs an internal server and communicates over a UDP-based network protocol. Key subsystems relevant to WASM:

```
┌─────────────────────────────────────────┐
│  Browser (WASM + WebGL)                 │
│  ┌─────────────────────────────────────┐│
│  │  Luanti Client (C++17 → WASM)       ││
│  │  ┌─────────┐ ┌─────────┐ ┌────────┐ ││
│  │  │Rendering│ │  Game   │ │  GUI   │ ││
│  │  │(Irrlicht│ │  Loop   │ │        │ ││
│  │  │  + GLES2│ │         │ │        │ ││
│  │  └────┬────┘ └────┬────┘ └───┬────┘ ││
│  │       │           │          │      ││
│  │  ┌────┴───────────┴──────────┴────┐ ││
│  │  │  Internal Server (same binary)  │ ││
│  │  │  - Lua scripting                │ ││
│  │  │  - Mapgen (SQLite3)             │ ││
│  │  └─────────────────────────────────┘ ││
│  └─────────────────────────────────────┘│
└─────────────────────────────────────────┘
```

For a first WASM port, the simplest approach is to keep the internal server model but replace or bridge the UDP socket layer.

---

## Blockers & Challenges

### 1. Networking — THE BIGGEST BLOCKER

Luanti uses **raw UDP sockets** for all client-server communication (including singleplayer). Browsers **cannot do UDP**.

**Used in:**
- `src/network/socket.cpp` — `socket()`, `bind()`, `sendto()`, `recvfrom()`, `poll()`
- `src/network/address.cpp` — `getaddrinfo()`, `inet_ntop()`, `inet_pton()`
- `src/network/connection.cpp` — Reliable-UDP implementation, packet fragmentation, congestion control

**Options:**

| Approach | Pros | Cons |
|----------|------|------|
| **WebRTC DataChannels** | UDP-like, low latency, supported in all modern browsers | Complex signaling required; Luanti protocol would need STUN/TURN or a signaling server |
| **WebSockets** | Simple, widely supported | TCP-only; changes game feel (head-of-line blocking); requires proxy server or protocol rewrite |
| **WebTransport** | Modern UDP-like API | Still emerging; not universally supported; requires HTTP/3 server |
| **Disable networking** | Gets a build working fastest | Only local singleplayer works; no multiplayer, no server list |

**Recommendation:** For the first milestone, **disable real networking entirely** and run the internal server with a localhost loopback shim. For multiplayer, implement WebRTC DataChannels later.

### 2. Main Game Loop

Luanti uses blocking `while` loops:

```cpp
// src/client/clientlauncher.cpp
while (m_rendering_engine->run() && !*kill) { ... }

// src/client/game.cpp
while (m_rendering_engine->run()) { ... }
```

Browsers require yielding control to the event loop. A blocking loop freezes the page.

**Options:**
- **`-sASYNCIFY`**: Emscripten can automatically transform the binary to yield at `emscripten_sleep()` calls. Easy but has significant runtime overhead and binary size cost.
- **`emscripten_set_main_loop()`**: Refactor the game loop into a callback function. This is the cleanest approach but requires restructuring `ClientLauncher::run()` and `Game::run()`.
- **`-sPROXY_TO_PTHREAD`**: Run the main application on a web worker thread. Allows blocking code but requires `SHARED_MEMORY` and has compatibility constraints.

**Recommendation:** Use `emscripten_set_main_loop()` with a state machine refactor. It is the most performant and idiomatic approach.

### 3. Threading

Luanti uses `std::thread` via `src/threading/thread.cpp` and `std::mutex`, `std::condition_variable`, etc.

Emscripten supports pthreads, but:
- Requires `-pthread` at compile AND link time
- Requires `-sSHARED_MEMORY=1`
- Requires the hosting page to send `Cross-Origin-Opener-Policy: same-origin` and `Cross-Origin-Embedder-Policy: require-corp` headers
- Some pthread APIs are missing or limited (`pthread_setaffinity_np`, `pthread_setname_np` on some platforms)

**Files to modify:**
- `src/threading/thread.cpp` — `setName()`, `bindToProcessor()` need `__EMSCRIPTEN__` fallbacks

### 4. File System

Luanti expects a POSIX/Windows file system with directories like:
- `builtin/` (engine Lua)
- `games/` (games like devtest)
- `mods/`
- `textures/`
- `worlds/` (save data)
- `minetest.conf`
- `debug.txt`

Emscripten provides virtual file systems:
- **MEMFS**: In-memory, lost on refresh
- **IDBFS**: Persists to IndexedDB, but must be explicitly synced
- **WORKERFS**: Read-only access to files dropped by user
- **NODEFS**: Only for Node.js

**Strategy:**
1. At build time, use `--preload-file` or `--embed-file` to bundle read-only assets (`builtin/`, `games/devtest/`, `textures/`, `fonts/`)
2. At runtime, mount an `IDBFS` on `/home/web_user/.luanti/` for `worlds/`, `minetest.conf`, and `debug.txt`
3. Call `EM_ASM(FS.syncfs(true, ...))` on startup to load saved data
4. Call `EM_ASM(FS.syncfs(false, ...))` periodically or on exit to persist

**Files to modify:**
- `src/filesys.cpp` — Path logic, directory listing
- `src/porting.cpp` — `path_share`, `path_user`, `path_cache` determination
- `src/main.cpp` — Initial FS setup

### 5. Build System

The CMake build assumes native targets. Key issues:

- `src/CMakeLists.txt` line 283: `find_package(Threads REQUIRED)` — works with Emscripten pthreads but needs flag propagation
- `src/CMakeLists.txt` lines 287-352: Platform library linking (`ws2_32`, `winmm`, `dl`, `rt`, `iconv`, `android`) — needs an `EMSCRIPTEN` branch
- `src/CMakeLists.txt` line 601: `CMAKE_CROSSCOMPILING` sets executable output to `build/bin` — okay, but install logic needs to output `.js`/`.wasm`/`.html`
- `src/CMakeLists.txt` lines 1003-1074: Windows DLL installation logic — irrelevant, needs skipping
- `irr/src/CMakeLists.txt` line 163: `find_library(EGL_LIBRARY NAMES EGL)` — Emscripten provides EGL via `-sEGL_LIBRARY` or system libs

---

## Step-by-Step Implementation Plan

### Phase 0: Preparation & Tooling

1. **Install Emscripten SDK** (emsdk) and verify with `emcc --version`
2. **Build or obtain Emscripten ports** for dependencies:
   - Lua 5.1 (or LuaJIT if WASM support works)
   - GMP
   - JsonCPP
   - SQLite3
   - ZLIB
   - Zstd
   - Freetype
   - SDL2 (use Emscripten's built-in: `-sUSE_SDL=2`)
   - Optionally: OpenAL-soft (`-sUSE_OPENAL=1`)
3. **Create a CMake toolchain file** or Emscripten preset in `CMakePresets.json`

### Phase 1: CMake & Compilation (Client Only, No Network)

Goal: Get `luanti` to compile and link as a `.js` + `.wasm` blob, even if it crashes at runtime.

1. **Create `cmake/Modules/EmscriptenOptions.cmake`** or modify `src/CMakeLists.txt`:
   - Add `elseif(EMSCRIPTEN)` branch alongside `WIN32`, `APPLE`, `UNIX`
   - Set `PLATFORM_LIBS` to Emscripten-specific libs
   - Disable `ENABLE_SOUND`, `ENABLE_CURL`, `ENABLE_GETTEXT`, `ENABLE_CURSES`
   - Disable PostgreSQL, LevelDB, Redis backends (keep SQLite3 only)
   - Disable `BUILD_SERVER`
   - Disable `BUILD_UNITTESTS` (re-enable later)
   - Set `ENABLE_GLES2=TRUE`, `ENABLE_OPENGL=FALSE`, `ENABLE_OPENGL3=FALSE`
   - Add Emscripten linker flags for SDL2, FS, memory, threading

2. **Patch `irr/src/CMakeLists.txt`**:
   - Ensure `ENABLE_WEBGL1` stays `FALSE` (broken upstream)
   - Ensure `ENABLE_GLES2` is `TRUE`
   - Verify SDL2 detection works with Emscripten's SDL2 port

3. **Patch `src/CMakeLists.txt`**:
   - Wrap Windows-specific resource compilation (`winresource.rc`) in `if(WIN32)` only
   - Wrap `sockets_init()` call or make it a no-op for Emscripten
   - Adjust `EXECUTABLE_OUTPUT_PATH` if needed
   - Remove or guard `CreateLegacyAlias` (symlinks don't exist on Emscripten FS)

4. **Patch `src/network/socket.cpp` and `address.cpp`**:
   - Create stub implementations for Emscripten:
     - `UDPSocket::init()` returns a dummy handle
     - `Send()` / `Receive()` / `Bind()` are no-ops or log warnings
     - `Address::Resolve()` returns localhost
   - This temporarily breaks multiplayer but allows compilation

5. **Patch `src/porting.cpp` and `src/porting.h`**:
   - Add `__EMSCRIPTEN__` includes where needed
   - Implement `path_share` and `path_user` to point to virtual FS paths
   - Stub out `signal_handler_killstatus()` (SIGINT doesn't apply)
   - Stub out `secure_rand_fill_buf()` if needed, or use `getrandom` via Emscripten

6. **Patch `src/threading/thread.cpp`**:
   - Add `#ifdef __EMSCRIPTEN__` fallbacks for `setName()` (no-op) and `bindToProcessor()` (return false)

7. **Build and iterate** until linking succeeds.

### Phase 2: File System & Asset Bundling

Goal: The game can load its Lua builtins, textures, and fonts; save data goes to IDBFS.

1. **Bundle read-only assets** at link time:
   ```bash
   --preload-file ${CMAKE_SOURCE_DIR}/builtin@/builtin
   --preload-file ${CMAKE_SOURCE_DIR}/games/devtest@/games/devtest
   --preload-file ${CMAKE_SOURCE_DIR}/textures@/textures
   --preload-file ${CMAKE_SOURCE_DIR}/fonts@/fonts
   --preload-file ${CMAKE_SOURCE_DIR}/client/shaders@/client/shaders
   --preload-file ${CMAKE_SOURCE_DIR}/clientmods@/clientmods
   ```
   Or use `--embed-file` if you want them inside the `.wasm` binary.

2. **Mount IDBFS for user data** in `src/main.cpp` (or a new `src/porting_emscripten.cpp`):
   ```cpp
   #ifdef __EMSCRIPTEN__
   #include <emscripten.h>
   void emscripten_init_filesystem()
   {
       EM_ASM(
           // Create the directory structure
           FS.mkdir('/home');
           FS.mkdir('/home/web_user');
           FS.mkdir('/home/web_user/.luanti');
           FS.mkdir('/home/web_user/.luanti/worlds');
           FS.mkdir('/home/web_user/.luanti/mods');
           FS.mkdir('/home/web_user/.luanti/textures');
           
           // Mount IDBFS for persistence
           FS.mount(IDBFS, {}, '/home/web_user/.luanti');
           
           // Sync from IndexedDB to memory
           FS.syncfs(true, function(err) {
               if (err) console.error('IDBFS sync load error:', err);
               else console.log('IDBFS loaded');
           });
       );
   }
   #endif
   ```

3. **Set default paths** in `src/porting.cpp`:
   - `path_share = "/"` (or wherever preloaded files are mounted)
   - `path_user = "/home/web_user/.luanti"`

4. **Add periodic save sync** or sync on `atexit()` / `main()` cleanup.

### Phase 3: Async Main Loop

Goal: The game renders without freezing the browser tab.

1. **Refactor `ClientLauncher::run()` and `Game::run()`**:
   - Extract the body of the `while (m_rendering_engine->run())` loops into a `step()` or `frame()` method
   - Store all local variables that cross frame boundaries as class members

2. **Create an Emscripten main loop callback**:
   ```cpp
   #ifdef __EMSCRIPTEN__
   #include <emscripten.h>
   
   static Game *g_game = nullptr;
   
   void emscripten_game_loop()
   {
       if (!g_game || !g_game->step()) {
           emscripten_cancel_main_loop();
       }
   }
   #endif
   ```

3. **In `main.cpp` or `ClientLauncher`**:
   ```cpp
   #ifdef __EMSCRIPTEN__
       g_game = &game;
       emscripten_set_main_loop(emscripten_game_loop, 0, 1);
   #else
       while (m_rendering_engine->run() && !*kill) { ... }
   #endif
   ```

4. **Alternative:** If refactoring is too invasive, use `-sASYNCIFY` as a temporary bridge:
   ```cmake
   target_link_options(luanti PRIVATE -sASYNCIFY)
   ```
   Then insert `emscripten_sleep(1)` inside tight loops. This is slower but requires less code change.

### Phase 4: Networking (WebRTC DataChannels)

Goal: Multiplayer works by connecting to servers via a WebRTC bridge.

This is the most complex phase and can be deferred.

1. **Design a WebRTC transport layer** in `src/network/webrtc_transport.cpp` (new file):
   - Wraps a JavaScript WebRTC peer connection via `EM_ASM` / `emscripten::val` (if using Embind)
   - Uses a lightweight signaling server (WebSocket) for SDP exchange
   - Presents the same interface as `UDPSocket` so `Connection` doesn't need to change

2. **Alternatively, use WebSockets**:
   - Implement a `WebSocketSocket` class that speaks TCP
   - Run a proxy server that translates WebSocket ↔ UDP
   - This is easier to implement but changes latency characteristics

3. **For singleplayer** (internal server):
   - Keep the existing `UDPSocket` stub that simply delivers packets in-memory
   - The client and server can communicate via a shared memory queue instead of a real socket

### Phase 5: Sound

Goal: In-game audio works.

1. **Option A:** Use Emscripten's OpenAL port:
   ```cmake
   target_link_options(luanti PRIVATE -sUSE_OPENAL=1)
   ```
   Then verify `src/sound/sound_openal.cpp` compiles and links.

2. **Option B:** Disable sound initially (`-DENABLE_SOUND=FALSE`) and implement a Web Audio API backend later.

### Phase 6: Input & Browser Integration

Goal: Keyboard, mouse, touch, and gamepad work correctly in the browser.

1. **Mouse capture:**
   - SDL2 on Emscripten handles `SDL_SetRelativeMouseMode()` → calls `emscripten_request_pointerlock()`
   - Already partially handled in `irr/src/CIrrDeviceSDL.cpp`
   - Test and verify pointer-lock behavior when clicking into the canvas

2. **Touch controls:**
   - Luanti has touch controls for Android (`src/gui/touchcontrols.cpp`)
   - These may work out-of-the-box or need minor adjustments for browser touch events

3. **Keyboard:**
   - SDL2 maps browser key events to SDL keycodes
   - Verify that text input (`SDL_StartTextInput`) works for chat

4. **Fullscreen:**
   - Use `emscripten_request_fullscreen()` or SDL's fullscreen toggle

### Phase 7: Polish & Optimization

1. **Memory tuning**:
   - Start with `-sINITIAL_MEMORY=256MB -sALLOW_MEMORY_GROWTH=1`
   - Profile with browser DevTools to find a stable size
   - Large worlds may require 512MB+; consider chunk unloading strategies

2. **Binary size**:
   - Use `-O3` or `-Oz` for release builds
   - Use `-sMODULARIZE=1` to wrap the output in a factory function
   - Use `-sEXPORT_NAME="LuantiModule"`
   - Strip debug info: `-g0`
   - Consider `WASM=1` (default) and disable unnecessary Emscripten runtime features

3. **Asset loading**:
   - Instead of `--preload-file` (which base64-encodes data into JS), consider:
     - Fetching assets at runtime via `emscripten_async_wget()` or the Fetch API
     - Using a `.data` file with `--preload-file` (kept separate from `.wasm`)

4. **CI/CD**:
   - Add a GitHub Actions workflow that installs emsdk and builds the WASM target
   - Host the output on GitHub Pages for easy testing

---

## Build Instructions (Target)

These are the *target* commands once the port is complete. They will not work today without the code changes described above.

### Configure

```bash
# Activate Emscripten
source /path/to/emsdk/emsdk_env.sh

# Configure
emcmake cmake -B build-wasm \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_CLIENT=TRUE \
    -DBUILD_SERVER=FALSE \
    -DBUILD_UNITTESTS=FALSE \
    -DBUILD_BENCHMARKS=FALSE \
    -DENABLE_SOUND=FALSE \
    -DENABLE_CURL=FALSE \
    -DENABLE_GETTEXT=FALSE \
    -DENABLE_CURSES=FALSE \
    -DENABLE_POSTGRESQL=FALSE \
    -DENABLE_LEVELDB=FALSE \
    -DENABLE_REDIS=FALSE \
    -DENABLE_PROMETHEUS=FALSE \
    -DENABLE_SPATIAL=FALSE \
    -DENABLE_OPENSSL=FALSE \
    -DENABLE_GLES2=TRUE \
    -DENABLE_OPENGL=FALSE \
    -DENABLE_OPENGL3=FALSE \
    -DRUN_IN_PLACE=TRUE \
    -DCMAKE_EXE_LINKER_FLAGS="\
        -sUSE_SDL=2 \
        -sUSE_ZLIB=1 \
        -sUSE_FREETYPE=1 \
        -sFULL_ES2=1 \
        -sALLOW_MEMORY_GROWTH=1 \
        -sINITIAL_MEMORY=256MB \
        -sMAXIMUM_MEMORY=1GB \
        -pthread \
        -sSHARED_MEMORY=1 \
        -sFETCH=1 \
        -sFORCE_FILESYSTEM=1 \
        --preload-file builtin \
        --preload-file games/devtest \
        --preload-file textures \
        --preload-file fonts \
        --preload-file client/shaders \
        --preload-file clientmods \
    "
```

### Build

```bash
emmake cmake --build build-wasm --parallel $(nproc)
```

### Output

```
build-wasm/bin/
├── luanti.js          # JS runtime / loader
├── luanti.wasm        # Compiled engine
├── luanti.data        # Preloaded asset bundle
└── luanti.html        # Shell page (if -o luanti.html or --shell-file used)
```

### Serve

You must serve the files with the correct COOP/COEP headers for `SHARED_MEMORY` / pthreads:

```python
# serve.py
import http.server
import socketserver

PORT = 8000

class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        super().end_headers()

with socketserver.TCPServer(("", PORT), Handler) as httpd:
    print(f"Serving at http://localhost:{PORT}")
    httpd.serve_forever()
```

Then open `http://localhost:8000/build-wasm/bin/luanti.html`.

---

## Files Requiring Changes

### CMake / Build
- `CMakeLists.txt` — Packaging (`CPACK_GENERATOR`), executable suffixes
- `src/CMakeLists.txt` — Platform libs, install rules, `find_package` logic, Emscripten branch
- `irr/src/CMakeLists.txt` — SDL2 detection for Emscripten, EGL library finding
- `cmake/Modules/*.cmake` — Possibly new `FindEmscriptenLua.cmake`, etc.

### Platform Abstraction
- `src/porting.cpp` — Paths, signals, `secure_rand_fill_buf()`, `get_sysinfo()`, `getTimeNs()`
- `src/porting.h` — `sleep_ms()`, `sleep_us()` macros (already work, but verify)
- **NEW:** `src/porting_emscripten.cpp/h` — FS init, IDBFS sync, WebRTC helpers

### File System
- `src/filesys.cpp` — `GetDirListing()`, `CreateDir()`, `RemoveDir()`, `CopyFile()`, `DeleteSingleFile()`

### Networking
- `src/network/socket.cpp` — Stub or replace UDP socket implementation
- `src/network/socket.h` — Interface is fine
- `src/network/address.cpp` — `Resolve()` may need localhost-only fallback
- `src/network/connection.cpp` — May need `#ifdef __EMSCRIPTEN__` guards around raw socket assumptions
- **NEW:** `src/network/websocket_socket.cpp/h` — Optional WebSocket transport
- **NEW:** `src/network/webrtc_transport.cpp/h` — Optional WebRTC DataChannel transport

### Threading
- `src/threading/thread.cpp` — `setName()`, `bindToProcessor()`

### Main Loop & Entry Point
- `src/main.cpp` — Add `emscripten_init_filesystem()` call, `#ifdef __EMSCRIPTEN__` around `main()` loop
- `src/client/clientlauncher.cpp` — Refactor `run()` into step-based or use ASYNCIFY
- `src/client/game.cpp` — Refactor `run()` into `step()` or `frame()`

### Rendering
- `src/client/renderingengine.cpp/h` — Verify GLES2 context creation
- `src/irrlicht_changes/` — Any patches may need Emscripten guards
- `client/shaders/` — Test shaders under WebGL/GLES2 constraints (no `GL_QUADS`, limited texture formats, etc.)

### Sound
- `src/sound/sound_openal.cpp` — Test with Emscripten's OpenAL port or stub out

### HTTP
- `src/httpfetch.cpp` — Replace cURL with `emscripten_fetch` or disable (`USE_CURL=FALSE`)

### Dependencies (in `lib/`)
- `lib/lua/` — Ensure Lua 5.1 builds with Emscripten
- `lib/sha256/` — Pure C, should work
- `lib/bitop/` — Pure C, should work
- `lib/lstrpack/` — Pure C, should work
- `lib/tiniergltf/` — Header-only C++, should work

---

## Dependency Notes

| Dependency | WASM Status | Action |
|------------|-------------|--------|
| **Lua 5.1** | Builds with Emscripten | Use bundled `lib/lua/` or compile upstream with `emcc` |
| **LuaJIT** | Experimental WASM support | Not recommended for first port; stick with PUC Lua 5.1 |
| **GMP** | Supported | Compile with `emconfigure ./configure && emmake make` |
| **JsonCPP** | Supported | Use bundled `lib/jsoncpp/` or compile upstream |
| **SQLite3** | Supported | Use bundled amalgamation or compile upstream |
| **ZLIB** | Emscripten port | `-sUSE_ZLIB=1` or compile upstream |
| **Zstd** | Supported | Compile upstream with `emcc` |
| **Freetype** | Emscripten port | `-sUSE_FREETYPE=1` or compile upstream |
| **SDL2** | Emscripten port | `-sUSE_SDL=2` (strongly recommended) |
| **OpenAL** | Emscripten port | `-sUSE_OPENAL=1` for OpenAL-soft wrapper |
| **cURL** | Complex | Disable initially; use `emscripten_fetch` or browser `fetch()` |
| **Gettext** | Not supported | Disable (`ENABLE_GETTEXT=FALSE`) |
| **Vorbis/Ogg** | Emscripten ports | `-sUSE_VORBIS=1 -sUSE_OGG=1` if using OpenAL |

---

## Networking Deep Dive

### Option A: In-Memory Loopback (Singleplayer Only)

For the fastest path to a playable WASM build, implement a fake `UDPSocket` that delivers packets directly to an in-memory queue:

```cpp
#ifdef __EMSCRIPTEN__
class LocalUDPSocket : public UDPSocket {
    std::queue<std::pair<Address, std::vector<u8>>> m_queue;
public:
    void Send(const Address &dest, const void *data, int size) override {
        // Push to a global queue that the "server" reads from
        g_loopback_queue.emplace(dest, std::vector<u8>((u8*)data, (u8*)data + size));
    }
    int Receive(Address &sender, void *data, int size) override {
        if (m_queue.empty()) return -1;
        // Pop from queue
    }
};
#endif
```

This lets you test the full client + internal server stack without any real network code.

### Option B: WebRTC DataChannels

WebRTC provides unreliable & ordered/unordered data channels (UDP-like) in browsers.

**Architecture:**
```
Browser (Luanti WASM)
  ↕ WebRTC DataChannel
Signaling Server (WebSocket, lightweight)
  ↕ WebRTC DataChannel
Native Luanti Server
```

**Implementation sketch:**
1. Write a small signaling server in Python/Node that exchanges SDP offers/answers over WebSockets
2. In `src/network/`, add `WebRTCDataChannel` class using `EM_ASM` / `emscripten::val` to call JS WebRTC APIs
3. Map `UDPSocket` interface to `RTCDataChannel.send()` / `onmessage`
4. Handle connection state changes and ICE candidates

### Option C: WebSocket Proxy

Write a proxy that sits between the browser and native Luanti servers:
```
Browser (WebSocket)  →  WS-to-UDP Proxy  →  Native Luanti Server
```

This requires no changes to the native server and minimal changes to the client (just replace UDP with WebSocket), but TCP head-of-line blocking can affect real-time gameplay.

---

## File System Strategy

### Read-Only Assets
Use `--preload-file` or `--embed-file` at link time.

| Asset | Mount Point | Method |
|-------|-------------|--------|
| `builtin/` | `/builtin` | `--preload-file` |
| `games/devtest/` | `/games/devtest` | `--preload-file` |
| `textures/` | `/textures` | `--preload-file` |
| `fonts/` | `/fonts` | `--preload-file` |
| `client/shaders/` | `/client/shaders` | `--preload-file` |
| `clientmods/` | `/clientmods` | `--preload-file` |

### Read-Write User Data
Use `IDBFS` mounted at runtime.

```javascript
// In pre-run JS or EM_ASM
FS.mkdir('/home/web_user/.luanti');
FS.mount(IDBFS, {}, '/home/web_user/.luanti');
FS.syncfs(true, function(err) {
    if (err) console.warn('syncfs error:', err);
    // Now safe to call main()
});
```

**Call `FS.syncfs(false, cb)` after:**
- World save
- Settings change
- Player logout
- Every N minutes (auto-save)

---

## Rendering & Shaders

### WebGL / GLES2 Constraints

Luanti's shaders in `client/shaders/` use GLSL. Under WebGL/GLES2:
- No `GL_QUADS` — must use triangles or triangle strips (IrrlichtMt handles this internally)
- No `gl_FragColor` in WebGL2 without `out` declaration; WebGL1 uses it
- Precision qualifiers required in fragment shaders: `precision mediump float;`
- Texture format limitations — no `GL_RGB10_A2` in WebGL1
- Max texture size may be 4096 or 8192 depending on GPU

### What to Test
- Menu rendering (GUI)
- Block/node rendering
- Entity rendering
- Sky, clouds, shadows
- Post-processing (FXAA)

---

## Testing Strategy

1. **Compile-time:** Get a clean build with zero errors
2. **Link-time:** Resolve all missing symbols
3. **Startup test:** Does `main()` run? Does the virtual FS mount?
4. **Menu test:** Does the main menu render? Can you click buttons?
5. **Singleplayer test:** Create a world, load it, place/break blocks
6. **Save/load test:** Exit, reload the page, verify world persisted in IDBFS
7. **Input test:** Keyboard, mouse look, touch, chat
8. **Multiplayer test:** (Phase 4) Connect to a server via WebRTC or WS proxy

---

## Appendix: Useful Emscripten Flags

| Flag | Purpose |
|------|---------|
| `-sUSE_SDL=2` | Use Emscripten's SDL2 port |
| `-sUSE_ZLIB=1` | Use Emscripten's ZLIB port |
| `-sUSE_FREETYPE=1` | Use Emscripten's Freetype port |
| `-sUSE_OPENAL=1` | Use Emscripten's OpenAL-soft port |
| `-sFULL_ES2=1` | Full OpenGL ES 2.0 emulation |
| `-sALLOW_MEMORY_GROWTH=1` | Grow heap dynamically |
| `-sINITIAL_MEMORY=256MB` | Starting heap size |
| `-sMAXIMUM_MEMORY=1GB` | Max heap size |
| `-pthread` | Enable pthread support |
| `-sSHARED_MEMORY=1` | Required for pthreads |
| `-sFETCH=1` | Enable `emscripten_fetch` API |
| `-sFORCE_FILESYSTEM=1` | Include FS support even if not auto-detected |
| `-sASYNCIFY` | Enable ASYNCIFY for blocking sleep/yield |
| `-sEXIT_RUNTIME=1` | Allow `atexit` handlers and full runtime shutdown |
| `-sMODULARIZE=1` | Wrap output in a factory function |
| `-sEXPORT_NAME="LuantiModule"` | Name of the factory function |
| `--preload-file src@dst` | Bundle files into a `.data` payload |
| `--embed-file src@dst` | Embed files into the wasm binary |
| `--shell-file template.html` | Custom HTML shell |
| `-sASSERTIONS=1` | Enable runtime assertions (debug builds) |
| `-sSAFE_HEAP=1` | Check for memory errors (debug builds) |
| `-g` / `-gsource-map` | Debug info / source maps |

---

## Summary Checklist

- [ ] Phase 0: Emscripten SDK installed; all dependencies compiled for WASM
- [ ] Phase 1: CMake configures and links a client-only build
- [ ] Phase 1: UDP sockets stubbed; game compiles
- [ ] Phase 1: `porting.cpp` returns correct virtual paths
- [ ] Phase 2: Asset preloading works; menu Lua loads
- [ ] Phase 2: IDBFS mounts and syncs; worlds save across reloads
- [ ] Phase 3: Async main loop works; browser stays responsive
- [ ] Phase 3: Rendering pipeline runs (menu visible)
- [ ] Phase 4: (Optional) Networking via WebRTC or WebSocket proxy
- [ ] Phase 5: (Optional) Sound enabled
- [ ] Phase 6: Input fully functional (keyboard, mouse, touch)
- [ ] Phase 7: Optimized release build; CI workflow added

---

*This document is a living plan. Update it as the port progresses.*
