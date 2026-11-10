# grok.md — Grok AI Assistant Guide for luanti_wasm

> **Read this first.** Tailored instructions for Grok when working on the Luanti WebAssembly port.

## Project Overview

**luanti_wasm** is the ongoing effort to port **Luanti** (the free open-source voxel game engine, formerly Minetest) to WebAssembly via Emscripten so it runs in web browsers.

- **Core Goal**: Run the full client + internal server (singleplayer) in the browser using WebGL/GLES2 for rendering, IDBFS for persistence, and a WebSocket-to-UDP proxy for multiplayer.
- **Current Focus**: Make a playable singleplayer experience (menu → create/load world → place/break blocks) that survives page reloads.
- **Upstream**: This is a downstream fork/worktree of https://github.com/luanti-org/luanti. Most engine code is identical; WASM-specific code lives in guarded `#ifdef __EMSCRIPTEN__` blocks.
- **Key Artifact**: A detailed living plan in [wasm_porting.md](wasm_porting.md).

## Technology Stack & WASM Specifics

- **Core**: C++17, Lua 5.1 (bundled), IrrlichtMt (embedded in `irr/`)
- **Graphics**: GLES2 + WebGL (via Emscripten's SDL2 + EGL)
- **Build**: CMake + Emscripten (`emcmake`, `emmake`). Custom preset "Emscripten" in `CMakePresets.json`.
- **Persistence**: streamed asset packages (`util/wasm/packages.json`) for read-only assets (`builtin/`, `games/devtest/`, `textures/`, `fonts/`, `client/shaders/`, `clientmods/`) + IDBFS (IndexedDB) mounted at `/home/web_user/.luanti/` for `worlds/`, config, etc.
- **Threading**: pthreads via `-pthread -sSHARED_MEMORY=1` (requires COOP/COEP headers on the serving page).
- **Networking**: `src/network/socket.cpp` implements `UDPSocket` in-process (loopback for the internal server) and tunnels remote traffic through a WebSocket proxy (`client/web/network.js` ↔ `util/wasm/proxy/`). A deployed TLS (WSS) proxy is still outstanding.
- **Main Loop**: The classic blocking `while (m_rendering_engine->run())` loops are kept. The engine runs on a pthread via `-sPROXY_TO_PTHREAD=1` + `-sOFFSCREEN_FRAMEBUFFER=1`; no ASYNCIFY and no `emscripten_set_main_loop`.
- **Memory**: Starts at 256 MB, can grow to 1 GB. Large worlds or many mods can push limits.

## Critical Files for WASM Work

**Build / Config**
- `CMakePresets.json` — "Emscripten" preset
- `src/CMakeLists.txt` — `elseif(EMSCRIPTEN)` branches (platform libs, link flags and the `luanti_packages` target; the asset list lives in `util/wasm/packages.json`)
- `irr/src/CMakeLists.txt` — GLES2 / SDL2 Emscripten handling

**Platform Abstraction (the WASM glue)**
- `src/porting_emscripten.h` + `src/porting_emscripten.cpp` — IDBFS mount + `syncfs`
- `src/porting.cpp` — `setSystemPaths()` returns `path_share = "/"`, `path_user = "/home/web_user/.luanti"`
- `src/main.cpp` — calls `emscripten_init_filesystem()` early; guards `sockets_init/cleanup`
- `src/network/socket.cpp` — `UDPSocket` implementation (loopback + WebSocket proxy) under `#ifdef __EMSCRIPTEN__`
- `src/threading/thread.cpp` — no-op `setName()` / `bindToProcessor()` for Emscripten

**Other Hot Spots**
- `src/client/clientlauncher.cpp` + `src/client/game.cpp` — the blocking game loops (they run off the UI thread)
- `src/filesys.cpp` — directory / file ops must work on the virtual FS
- `client/shaders/` — must be valid GLES2/WebGL (no `GL_QUADS`, precision qualifiers, etc.)

## Build & Run Workflow (Current)

```bash
# 1. Activate Emscripten (emsdk must be installed and activated)
source /path/to/emsdk/emsdk_env.sh

# 2. Build libzip once per SDK/EM_CACHE (there is no Emscripten port)
util/wasm/build_libzip.sh

# 3. Configure with the dedicated preset (binaryDir is build-wasm) and build
cmake --preset Emscripten
cmake --build build-wasm --parallel $(($(nproc)+1))

# Output: build-wasm/bin/luanti.html + luanti.js + luanti.wasm + asset-manifest.json + assets/*.data
```

**Serving (mandatory for pthreads / SHARED_MEMORY):**

You **must** serve with these headers:

```bash
python3 util/wasm/serve.py   # serves build-wasm/bin with COOP/COEP; --directory/--bind/--port
```

Then open `http://127.0.0.1:8000/luanti.html`.

## Grok Guidelines (When Helping on This Project)

1. **Always read the context first**:
   - Start with this `grok.md`
   - Then [AGENTS.md](AGENTS.md) (Luanti C++17 + Lua style, license headers, tabs, etc.)
   - Then [wasm_porting.md](wasm_porting.md) — the authoritative phase plan and blocker analysis

2. **WASM constraints are non-negotiable**:
   - No raw UDP sockets in browsers → remote traffic must go through the WebSocket proxy. Do not reintroduce `socket()`/`sendto()` calls under `__EMSCRIPTEN__`.
   - The browser main thread cannot block → the engine loop stays on the `PROXY_TO_PTHREAD` thread; UI/launcher code lives in `client/web/` on the main thread.
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
   - Before adding anything to a package in `util/wasm/packages.json`
     (a new game, mod, or texture set), read the **Content Budget** section in
     [wasm_porting.md](wasm_porting.md#content-budget) — it has the first-visit and per-game
     size limit and the allow/deny list for what ships in the demo pack.

5. **Testing mindset**:
   - Manual browser testing (Chrome/Edge/Firefox with WebGPU/WebGL2 preferred).
   - After any FS or save-related change, verify world persistence across hard reload.
   - Check console for `IDBFS load/save` messages and Lua errors.
   - Singleplayer first. Public-server multiplayer (deployed WSS proxy) is the outstanding Phase 4 item — do not start it unless asked.
   - For JavaScript changes run `npm run lint && npm run typecheck && npm test`; update `client/web/emscripten-module.d.ts` when the `Module` surface shared with C++ changes.

6. **Style & Tone**:
   - Match the existing Luanti codebase (tabs, license headers on new .cpp/.h, snake_case + CamelCase mix).
   - When proposing larger refactors (main loop, transport layer), reference the exact phase in wasm_porting.md and outline the minimal diff.
   - Be direct about blockers: "This still needs the deployed WSS proxy from Phase 4."

## Common Tasks & Priorities

**High priority right now**
- Make the main menu + singleplayer world fully playable and stable under Emscripten.
- Fix any remaining link/runtime errors when building with current emsdk.
- Ensure `emscripten_sync_filesystem()` is called at the right moments (world save, settings write, logout).
- Improve pointer lock / mouse capture behavior in the browser (already partially in Irrlicht SDL device).
- Validate all core shaders under WebGL/GLES2 constraints.

**Next phases (see wasm_porting.md)**
- Phase 4: deployed TLS (WSS) proxy and public-server multiplayer acceptance.
- Cross-browser persistence acceptance (IDBFS).
- Polish: Touch controls, fullscreen, better asset streaming (runtime fetch instead of huge preload), binary size wins, GitHub Pages + COOP/COEP hosting.

**Useful commands for debugging**
```bash
# After build, inspect the generated JS for clues
grep -i "assert\|abort\|emscripten" build-wasm/bin/luanti.js | head -20

# Rebuild cleanly
rm -rf build-wasm && cmake --preset Emscripten && cmake --build build-wasm -j
```

## Quick Reference Links

- [AGENTS.md](AGENTS.md) — Full Luanti contributor rules (C++ style, testing, CI)
- [wasm_porting.md](wasm_porting.md) — The complete porting plan, architecture diagrams, blocker table, and build flag reference
- [doc/compiling/](doc/compiling/) — Native build docs (useful contrast)
- `minetest.conf.example` + `builtin/` — Engine defaults and Lua API

---

**Luanti in the browser is a big lift.** The engine was never designed for it, but the pieces (Irrlicht Emscripten support + careful FS + proxied networking + CMake awareness) are already in place. Your job is to keep pushing the playable boundary while respecting the constraints.

Let's make singleplayer rock-solid, then tackle the rest. 🚀
