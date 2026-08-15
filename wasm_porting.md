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

### Remaining Work

- A deployed TLS proxy and public-server multiplayer acceptance are outstanding.
- Full world persistence acceptance across Chrome/Edge/Firefox is outstanding.
- CI and public demo hosting are not yet configured.
- Sound and complete keyboard, pointer-lock, and touch acceptance remain.

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
| **In-process loopback** | No browser transport overhead for singleplayer | Does not reach remote servers |

**Implemented MVP:** Keep singleplayer UDP in an in-process queue and route only
remote IPv4 destinations through a versioned WebSocket-to-UDP proxy. This leaves
Luanti's reliable-UDP layer unchanged and works in current browsers. It adds one
TCP/WebSocket hop, so head-of-line blocking and proxy placement still affect
latency. See `docs/wasm-issues/02-websocket-proxy-networking.md`.

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

**Implemented MVP:** Use `PROXY_TO_PTHREAD` with an offscreen framebuffer so the full
synchronous launcher/menu/game lifecycle runs on an application worker. Keep a
complete `emscripten_set_main_loop()` state-machine conversion as a measured
follow-up if worker-side canvas stalls remain.

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
3. Hydrate with `FS.syncfs(true)` from the `Module.preRun` bootstrap before `main()`
4. Submit committed saves to the serialized `FS.syncfs(false)` service

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

4. **Use the browser `UDPSocket` transport in `src/network/socket.cpp`:**
   - Deliver loopback packets through a shared-memory queue for the internal
     singleplayer server.
   - Submit remote packets to `client/web/network.js`, which connects to the
     configured WebSocket-to-UDP proxy.
   - Register Emscripten's synthetic DNS addresses from `Address::Resolve()` so
     the proxy resolves the original hostname.

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

2. **Mount and hydrate IDBFS before `main()`.**
   `client/web/persistence.js` is linked as `--pre-js`. Its `Module.preRun`
   callback holds a run dependency until `FS.syncfs(true)` succeeds, then creates
   the writable user directories. A startup storage failure intentionally keeps
   `main()` gated. See `docs/wasm-issues/01-persistence-mvp.md` for the runtime
   state contract and error behavior.

3. **Set default paths** in `src/porting.cpp`:
   - `path_share = "/"` (or wherever preloaded files are mounted)
   - `path_user = "/home/web_user/.luanti"`

4. **Service committed saves.** Engine save paths record atomic dirty
   generations. The application-worker frame pump submits them to the
   single-flight JavaScript `FS.syncfs(false)` service, with urgent disconnect,
   shutdown, and page lifecycle requests.

### Phase 3: Async Main Loop

Goal: The game renders without freezing the browser tab.

**Implemented MVP:** link with `-sPROXY_TO_PTHREAD=1` and
`-sOFFSCREEN_FRAMEBUFFER=1`. Luanti's synchronous launcher, menu, gameplay,
server-start, and shutdown stacks run away from the browser UI thread while the
SDL/EGL GL calls are proxied to the browser-owned canvas. Direct OffscreenCanvas
transfer is not enabled because it conflicts with that context-creation path in
Emscripten 6.0.3. No Asyncify or native behavior changes are required.

`porting::emscripten_validate_main_loop()` enforces this build contract at
startup. Every `RenderingEngine::run()` call services browser-platform work;
this currently submits persistence dirty generations. During final durable
shutdown, only the application worker waits, so the browser can keep showing
storage state and completing IndexedDB callbacks.

This architecture keeps the page and launcher overlays responsive during
engine work. A single long Lua callback can still stall the game canvas on the
application worker. If profiling proves that boundary unacceptable, the
follow-up is a complete `ClientLauncher` + `GUIEngine` + `Game` lifecycle state
machine for `emscripten_set_main_loop()`, not a gameplay-loop-only extraction.
See `docs/wasm-issues/03-async-main-loop.md` for the contract and focused browser
smoke.

### Phase 4: WebSocket Proxy Networking

Goal: Join native Luanti servers without changing those servers.

**Implemented transport:** The Emscripten `UDPSocket` branch presents the same
blocking interface used by `Connection`. Remote packets cross the browser main
thread through `client/web/network.js`, use a 12-byte destination/source header
over WebSocket, and are forwarded by the self-hostable Node server under
`util/wasm/proxy/`. The generated shell and `?proxy=` query parameter configure
the URL. IPv6 is intentionally rejected for this MVP.

The remaining phase gate is deployed acceptance: serve the built client with
COOP/COEP, deploy the proxy behind WSS near the test server, join by hostname,
and validate at least ten minutes of movement and chat. The proxy's shell status
and `Module.luantiNetwork.getState()` expose link RTT and packet counters.

### Phase 5: Sound

Goal: In-game audio works.

- **Implemented:** Enabled OpenAL and Vorbis via Emscripten ports (`-sUSE_OPENAL=1`, `-sUSE_OGG=1`, `-sUSE_VORBIS=1`).
- `EmscriptenDependencies.cmake` prepares `ogg` and `vorbis` ports and registers static library cache paths.
- Browser autoplay unlock handler added to `launcher.js` to resume the Web Audio context on user interactions.
- Threaded OpenAL audio pipeline runs seamlessly via Emscripten pthreads.

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

The MVP web experience now lives in `client/web/`. It holds `main()` with
`Module.noInitialRun` until preload-file and IDBFS startup complete, then calls
the exported Emscripten `callMain` once with validated launcher arguments. It
includes local/direct launch flows, an opt-in public server list, deployment-
configured WSS regions, real engine loading status, deep links, sharing,
fullscreen/pointer-lock affordances, a runtime console, and release-scoped PWA
caching. See `doc/compiling/wasm-embedding.md` for the supported iframe contract.

Touch-only gameplay and a stable pause/unpause API remain follow-up work. The
launcher intentionally does not expose provisional setters that would race the
synchronous application-worker lifecycle.

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

## Build Instructions

The checked-in Emscripten preset is now the supported build path:

```bash
source /path/to/emsdk/emsdk_env.sh
cmake --preset Emscripten
cmake --build build-wasm --parallel 2
python3 util/wasm/serve.py
```

Then open `http://127.0.0.1:8000/luanti.html`. The server helper sends the
COOP/COEP headers required by pthreads and shared WebAssembly memory. See
`doc/compiling/wasm.md` for the pinned SDK revision, emitted files, browser
smoke, Cloudflare Pages deployment, cache strategy, and troubleshooting.

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
- `src/porting_emscripten.cpp/h` — dirty generations and application-thread persistence service
- `client/web/persistence.js` — pre-main hydration, IDBFS sync serialization, retries, and public API
- `client/web/shell.html` — generated-shell persistence status and sticky errors

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
- `src/main.cpp` — Submit the urgent final persistence generation on graceful shutdown
- `src/porting_emscripten.cpp/h` — Enforce and service the worker-main contract
- `src/client/renderingengine.h` — Service browser-platform work once per frame
- `src/client/clientlauncher.cpp`, `src/gui/guiEngine.cpp`, `src/client/game.cpp` — Preserve synchronous lifecycle under `PROXY_TO_PTHREAD`; a complete state-machine conversion remains optional follow-up work

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

This is the implemented multiplayer path. `client/web/network.js` and
`util/wasm/proxy/` implement protocol version 1 while the C++ adapter keeps the
normal `UDPSocket` contract. TCP head-of-line blocking can still affect
real-time gameplay. The proxy can inspect unencrypted game traffic, so users
must trust its operator or self-host it.

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

The implementation is `client/web/persistence.js`, linked through `--pre-js` and
`-lidbfs.js`. It hydrates in `Module.preRun`, exposes
`Module.luantiPersistence`, and serializes every `FS.syncfs(false)` call. Engine
save paths record committed work; they do not call asynchronous JavaScript from
worker threads. See `docs/wasm-issues/01-persistence-mvp.md`.

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

### First Playable Smoke Test (Integration Gate)
Before a public demo can be approved, the build must pass this end-to-end checklist on Chrome and Firefox:
1. Serve with COOP/COEP headers (`Cross-Origin-Opener-Policy: same-origin`, `Cross-Origin-Embedder-Policy: require-corp`)
2. Page loads without JS/WASM errors
3. IDBFS sync completes
4. Main menu renders and accepts input (no tab freeze)
5. Create a new singleplayer devtest world
6. Load world, move, place 10 blocks, break 5 blocks
7. Exit to menu, hard-reload tab, load same world — blocks persist
8. `minetest.conf` change survives reload

*Note: Multiplayer testing (WebSocket proxy) is tracked as a separate milestone.*

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
| `-sPROXY_TO_PTHREAD=1` | Run the synchronous application main on a worker |
| `-sOFFSCREEN_FRAMEBUFFER=1` | Proxy worker-side SDL/EGL rendering to the browser canvas |
| `-sFETCH=1` | Enable `emscripten_fetch` API |
| `-sFORCE_FILESYSTEM=1` | Include FS support even if not auto-detected |
| `-sASYNCIFY` | Optional blocking-yield transform; not used by the current target |
| `-sEXIT_RUNTIME=0` | Keep browser callbacks and final persistence retries alive after `main()` returns |
| `-lidbfs.js` | Explicitly retain the legacy JavaScript IDBFS backend |
| `-sMODULARIZE=1` | Wrap output in a factory function |
| `-sEXPORT_NAME="LuantiModule"` | Name of the factory function |
| `--preload-file src@dst` | Bundle files into a `.data` payload |
| `--embed-file src@dst` | Embed files into the wasm binary |
| `--shell-file template.html` | Custom HTML shell |
| `--pre-js file.js` | Install the browser networking and persistence contracts before engine startup |
| `-sASSERTIONS=1` | Enable runtime assertions (debug builds) |
| `-sSAFE_HEAP=1` | Check for memory errors (debug builds) |
| `-g` / `-gsource-map` | Debug info / source maps |

---

## Summary Checklist

- [x] Phase 0: Emscripten SDK installed; required dependencies prepared for WASM
- [x] Phase 1: CMake configures and links a client-only build
- [x] Phase 1: Browser UDP interface has in-process loopback and proxy routing
- [x] Phase 1: `porting.cpp` returns correct virtual paths
- [x] Phase 2: Asset preload bundle is emitted and available at startup
- [x] Phase 2: IDBFS hydration and sentinel persistence pass browser automation
- [x] Phase 3: Synchronous engine loop is isolated from the browser main thread
- [x] Phase 3: Rendering pipeline runs (menu visible)
- [x] Phase 4: WebSocket/UDP transport, launcher configuration, and self-hostable proxy implemented
- [ ] Phase 4: Public-server browser play acceptance completed
- [x] Phase 5: (Optional) Sound enabled via OpenAL + Vorbis
- [x] Phase 6: Input functional (keyboard, mouse look & pointer-lock, text input, touch/gamepad)
- [ ] Phase 7: Optimized release build; CI workflow added
- [x] **Shaders**: Added integer precision qualifiers (`int`, `uint`, `sampler2DArray`) in `src/client/shader.cpp` to ensure WebGL 2 / GLES 3 compilation passes for advanced features like FXAA and 3D UI nodes.

---

*This document is a living plan. Update it as the port progresses.*
