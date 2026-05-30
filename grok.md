# grok.md — Grok AI Assistant Guide for luanti_wasm

> **Read this first.** Tailored instructions for Grok when working on the Luanti WebAssembly port.

## Project Overview

**luanti_wasm** is the ongoing effort to port **Luanti** (the free open-source voxel game engine, formerly Minetest) to WebAssembly via Emscripten so it runs in web browsers.

- **Core Goal**: Run the full client + internal server (singleplayer) in the browser using WebGL/GLES2 for rendering, IDBFS for persistence, and eventually WebRTC for multiplayer.
- **Current Focus**: Make a playable singleplayer experience (menu → create/load world → place/break blocks) that survives page reloads.
- **Upstream**: This is a downstream fork/worktree of https://github.com/luanti-org/luanti. Most engine code is identical; WASM-specific code lives in guarded `#ifdef __EMSCRIPTEN__` blocks.
- **Key Artifact**: A detailed living plan in [wasm_porting.md](wasm_porting.md).

## Technology Stack & WASM Specifics

- **Core**: C++17, Lua 5.1 (bundled), IrrlichtMt (embedded in `irr/`)
- **Graphics**: GLES2 + WebGL (via Emscripten's SDL2 + EGL)
- **Build**: CMake + Emscripten (`emcmake`, `emmake`). Custom preset "Emscripten" in `CMakePresets.json`.
- **Persistence**: `--preload-file` for read-only assets (`builtin/`, `games/devtest/`, `textures/`, `fonts/`, `client/shaders/`, `clientmods/`) + IDBFS (IndexedDB) mounted at `/home/web_user/.luanti/` for `worlds/`, config, etc.
- **Threading**: pthreads via `-pthread -sSHARED_MEMORY=1` (requires COOP/COEP headers on the serving page).
- **Networking**: Currently stubbed (see `src/network/socket.cpp`). Internal server + client communicate via no-op sockets for singleplayer only.
- **Main Loop**: Still uses classic blocking `while (m_rendering_engine->run())` loops. Emscripten support currently depends on `-sASYNCIFY` (or will need `emscripten_set_main_loop` refactor).
- **Memory**: Starts at 256 MB, can grow to 1 GB. Large worlds or many mods can push limits.

## Critical Files for WASM Work

**Build / Config**
- `CMakePresets.json` — "Emscripten" preset
- `src/CMakeLists.txt` — `elseif(EMSCRIPTEN)` branches (platform libs, linker flags at ~774)
- `irr/src/CMakeLists.txt` — GLES2 / SDL2 Emscripten handling

**Platform Abstraction (the WASM glue)**
- `src/porting_emscripten.h` + `src/porting_emscripten.cpp` — IDBFS mount + `syncfs`
- `src/porting.cpp` — `setSystemPaths()` returns `path_share = "/"`, `path_user = "/home/web_user/.luanti"`
- `src/main.cpp` — calls `emscripten_init_filesystem()` early; guards `sockets_init/cleanup`
- `src/network/socket.cpp` — full no-op `UDPSocket` implementation under `#ifdef __EMSCRIPTEN__`
- `src/threading/thread.cpp` — no-op `setName()` / `bindToProcessor()` for Emscripten

**Other Hot Spots**
- `src/client/clientlauncher.cpp` + `src/client/game.cpp` — the blocking game loops (Phase 3 in the porting plan)
- `src/filesys.cpp` — directory / file ops must work on the virtual FS
- `client/shaders/` — must be valid GLES2/WebGL (no `GL_QUADS`, precision qualifiers, etc.)

## Build & Run Workflow (Current)

```bash
# 1. Activate Emscripten (emsdk must be installed and activated)
source /path/to/emsdk/emsdk_env.sh

# 2. Configure using the dedicated preset
emcmake cmake --preset Emscripten -B build-wasm

# 3. Build
emmake cmake --build build-wasm --parallel $(($(nproc)+1))

# Output: build-wasm/bin/luanti.html + luanti.js + luanti.wasm + luanti.data
```

**Serving (mandatory for pthreads / SHARED_MEMORY):**

You **must** serve with these headers:

```python
# serve.py (or equivalent)
import http.server, socketserver
class COOPHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        super().end_headers()
socketserver.TCPServer(("", 8000), COOPHandler).serve_forever()
```

Then open `http://localhost:8000/build-wasm/bin/luanti.html`.

## Grok Guidelines (When Helping on This Project)

1. **Always read the context first**:
   - Start with this `grok.md`
   - Then [AGENTS.md](AGENTS.md) (Luanti C++17 + Lua style, license headers, tabs, etc.)
   - Then [wasm_porting.md](wasm_porting.md) — the authoritative phase plan and blocker analysis

2. **WASM constraints are non-negotiable**:
   - No raw UDP sockets → current stubs are intentional. Do not reintroduce `socket()`/`sendto()` calls without a plan for WebRTC or a proxy.
   - Browser main thread cannot block → long-term we need to break the game loop (or rely on ASYNCIFY).
   - File system is virtual → never assume POSIX paths or that writes survive without explicit `emscripten_sync_filesystem()` after saves/settings changes.
   - Rendering is GLES2/WebGL → shader changes must be validated (no desktop-only extensions).

3. **Change discipline**:
   - Guard every WASM-specific change with `#ifdef __EMSCRIPTEN__` (or `if(EMSCRIPTEN)` in CMake).
   - Prefer changes that keep native builds (Linux/Windows/macOS) working unchanged.
   - When touching shared code (porting, filesys, network), add clear comments explaining the WASM impact.

4. **Performance & Size awareness**:
   - 256 MB initial heap is tight for big worlds + Lua + assets. Suggest chunking/unloading strategies when relevant.
   - Binary size matters for web delivery. `-Oz`, `-sASSERTIONS=0` for release, modularize when appropriate.
   - Profile in browser DevTools (Memory, Performance tabs) + Emscripten's `--profiling-funcs`.

5. **Testing mindset**:
   - Manual browser testing (Chrome/Edge/Firefox with WebGPU/WebGL2 preferred).
   - After any FS or save-related change, verify world persistence across hard reload.
   - Check console for `IDBFS load/save` messages and Lua errors.
   - Singleplayer first. Multiplayer (WebRTC DataChannels + signaling server) is explicitly Phase 4 — do not start it unless asked.

6. **Style & Tone**:
   - Match the existing Luanti codebase (tabs, license headers on new .cpp/.h, snake_case + CamelCase mix).
   - When proposing larger refactors (main loop, transport layer), reference the exact phase in wasm_porting.md and outline the minimal diff.
   - Be direct about blockers: "This still requires the main-loop refactor from Phase 3."

## Common Tasks & Priorities

**High priority right now**
- Make the main menu + singleplayer world fully playable and stable under Emscripten.
- Fix any remaining link/runtime errors when building with current emsdk.
- Ensure `emscripten_sync_filesystem()` is called at the right moments (world save, settings write, logout).
- Improve pointer lock / mouse capture behavior in the browser (already partially in Irrlicht SDL device).
- Validate all core shaders under WebGL/GLES2 constraints.

**Next phases (see wasm_porting.md)**
- Phase 3: Proper async main loop (`emscripten_set_main_loop` + step extraction) or reliable ASYNCIFY usage.
- Phase 5: Sound (Emscripten's OpenAL port or Web Audio backend).
- Phase 4 (later): WebRTC DataChannel transport + lightweight signaling server for real multiplayer.
- Polish: Touch controls, fullscreen, better asset streaming (runtime fetch instead of huge preload), binary size wins, GitHub Pages + COOP/COEP hosting.

**Useful commands for debugging**
```bash
# After build, inspect the generated JS for clues
grep -i "assert\|abort\|emscripten" build-wasm/bin/luanti.js | head -20

# Rebuild cleanly
rm -rf build-wasm && emcmake cmake --preset Emscripten -B build-wasm && emmake cmake --build build-wasm -j
```

## Quick Reference Links

- [AGENTS.md](AGENTS.md) — Full Luanti contributor rules (C++ style, testing, CI)
- [wasm_porting.md](wasm_porting.md) — The complete porting plan, architecture diagrams, blocker table, and build flag reference
- [doc/compiling/](doc/compiling/) — Native build docs (useful contrast)
- `minetest.conf.example` + `builtin/` — Engine defaults and Lua API

---

**Luanti in the browser is a big lift.** The engine was never designed for it, but the pieces (Irrlicht Emscripten support + careful FS + stubbed networking + CMake awareness) are already in place. Your job is to keep pushing the playable boundary while respecting the constraints.

Let's make singleplayer rock-solid, then tackle the rest. 🚀
