# Investigation: paradust7/minetest-wasm for Luanti WASM Client Fork

**Date:** 2026-05 (analysis performed in current session)
**Analyst:** Grok (systems + game engine porting focus)
**Subject Repo:** https://github.com/paradust7/minetest-wasm (128 stars, experimental, active as of late 2025)
**Live Demo:** https://minetest.dustlabs.io/
**Related:** paradust7/minetest (his fork at 5.14-era commit 1cfdd6d), webshims (emsocket), minetest-wasm-sample-proxy

---

## Executive Summary

paradust7/minetest-wasm is the most complete, battle-tested public attempt at a browser-port of the Minetest/Luanti engine. It delivers a **working multiplayer client** (and even in-browser server hosting) via a custom WebSocket proxy, has a polished custom launcher, and solves several hard browser integration problems (non-blocking main loop, runtime content packs, pointerlock, etc.).

**However, it is not a drop-in foundation for a modern, maintainable Luanti WASM client.**

Its strengths (proven proxy networking + loop control) are highly reusable in design. Its weaknesses (old forked engine base, incomplete persistence, high invasiveness/complexity, bespoke build system) make a full fork or direct reuse risky for long-term maintenance as Luanti evolves.

**Recommended path:** Clean modern Luanti base (our current direction) + selective, isolated port of the 2-3 highest-leverage components (proxy networking shim + main loop yielding pattern + pack loader UX). Prioritize fixing persistence (paradust's biggest open wound) early.

---

## 1. Current State of paradust7/minetest-wasm (Deep Analysis)

### Base & Version
- Built on a **personal fork** (paradust7/minetest) pinned to a 5.14-dev era snapshot (Nov 2025 commit 1cfdd6d "Make createServer async").
- Minetest_Game also pinned to an old commit.
- **Not tracking upstream Luanti** (current ~5.16-dev). Demo site was even further behind (5.9-era per open issues).
- This is the single largest long-term liability.

### Build System
- ~15 specialized `build_*.sh` scripts + `common.sh`, `fetch_sources.sh`, `apply_patches.sh`, `incremental.sh`.
- **Vendors/pins ancient tarballs** for most deps (curl 7.82, openssl 1.1.1n, libarchive, etc.) + git checkouts at exact revs for zlib/libpng/freetype/zstd/etc.
- Reason (stated in code): "Emscripten ports don't compile with pthread support" (true at the time; situation has improved).
- Custom Emscripten SDK install + 3 invasive patches to WASMFS internals (`emsdk_openat.patch`, `dirperms`, `file_packager`).
- Produces a `www/` tree with content-addressed release UUID subdirs, `.pack` files (zstd tar of fsroot), custom `.htaccess` for COOP/COEP + caching.
- **Strength:** Reproducible, works. **Weakness:** Brittle, high maintenance, not "just `emcmake`".

### Emscripten Integration & Patches
- `-sWASMFS=1 -sUSE_WEBGL2 -sMIN_WEBGL_VERSION=2 -sPTHREAD_POOL_SIZE=20 -sINITIAL_MEMORY=~2GB`.
- Custom `mainloop.cpp` (new file) + many `EMSCRIPTEN_KEEPALIVE` exports (`emloop_*`, `emsocket_*`, `irrlicht_*`).
- Heavy use of `MAIN_THREAD_ASYNC_EM_ASM`, cwrap for JS <-> C++ control (pause/unpause, pack install, conf injection, pointerlock requests).
- **Key innovation:** `MainLoop` class with dedicated helper pthread for "async then resume" tasks, rAF integration to yield control, blessed reentry.

### Networking / Proxy (The Crown Jewel)
- Browsers have no raw UDP/TCP → full replacement.
- **emsocket** (in webshims repo): Complete userspace reimplementation of BSD sockets (`socket`, `bind`, `sendto`, `recvfrom`, `select`/`poll` family, getaddrinfo, etc.).
  - `VirtualSocket` / `ProxyLink` / encapsulation protocol (12-byte header + magic + IP/port).
  - Two modes:
    - Simple PROXY for TCP (e.g. server list / curl?).
    - "VPN" encapsulated UDP mode for game protocol (the real Minetest UDP packets are wrapped and sent over WS to the proxy, which unwraps and forwards as real UDP).
- **proxy.js** (Web Worker): WebSocket client to regional proxies (`wss://*.dustlabs.io/mtproxy`), handshake, encapsulation/decapsulation, VPN code support.
- **Sample proxy** (Node): `UDPProxy.js`, `VPN.js`, `ConnectProxy.js` — receives WS, does real UDP to target servers (or hosts in-browser "servers").
- Regional anycast-ish proxies for latency. In-browser server hosting UI exists (player name + game selection → copyable join URL).
- **Quality:** Surprisingly robust for an experimental system. Handles the fundamental mismatch well. Custom protocol is documented in code.
- **Tradeoffs:** Proxy is a trusted man-in-the-middle for all multiplayer traffic (privacy/latency/jitter). Maintenance burden on operator. Encapsulation adds overhead vs native UDP.

### Filesystem & Persistence
- `--preload` / packager for initial assets → extracted via custom `emloop_install_pack` (uses libarchive + zstd into WASMFS).
- WASMFS with custom patches for better POSIX semantics (openat with O_CREAT, directory perms).
- **Persistence story is weak/incomplete:**
  - Open issue #32 ("No way to save game", created 2024, still active 2025) is the smoking gun.
  - Worlds/config appear to live in the VFS, but reliable cross-reload save (IDBFS/OPFS + periodic `syncfs` + beforeunload) was never fully solved or regressed.
  - The pack system excels at *injecting* content at runtime (great for mods/texturepacks/games) but is not a substitute for engine-native SQLite world saves + player metadata persisting automatically.
- This is the area where our current IDBFS work in `porting_emscripten.cpp` is already ahead in intent.

### Client vs Server Capabilities
- Primarily **client** build.
- Surprisingly, also supports **running a server inside the browser tab** (via the VPN/proxy path). The tab becomes the "server" that other WASM (or native?) clients can join through the proxy.
- Cool demo feature, but has obvious limitations (tab must stay open, high resource use, single point of failure).

### Mod / Game Support & Limitations
- Works with minetest_game and some simple games.
- Known crashes on content-heavy or "unusual" games/mods (e.g. Subway Miner #37).
- Mods that do heavy FS I/O, assume native timing/threads, or use unsupported sound/extensions will have issues.
- No first-class mobile touch controls (open issue).
- Some rendering glitches reported (duplicated minimap, HUD color issues in specific games).

### Other Notable Engineering
- Sophisticated launcher.js (resolution/aspect selectors, proxy chooser, console, progress, language, beforeunload hooks sketched).
- Worker.js for off-main-thread Emscripten module.
- Sound init bridge (`emloop_init_sound`).
- Pointerlock JS/C++ coordination (Irrlicht wants it → JS requests it on gesture).
- Content-addressed deploys for cache-busting.

---

## 2. Reusability Assessment — What to Take, What to Leave

### High-Value, Reusable (Port the *Design* + Core Shims)
| Component              | Reusability | Notes / Risk |
|------------------------|-------------|--------------|
| **emsocket + proxy.js + sample proxy** (networking model) | ★★★★★ | The encapsulation + "VPN over WS" pattern is the practical solution. Clean-room reimplement or adapt under our socket layer. Proxy server can be a separate small service. |
| **MainLoop / emloop pause-unpause + helper thread + rAF yielding** | ★★★★☆ | Solves the "browser hates blocking C++ loops" problem elegantly. We need *something* like this (or disciplined ASYNCIFY + emscripten_set_main_loop). Make it far less invasive. |
| **Runtime pack (tar.zst + libarchive install)** | ★★★☆☆ | Excellent for dynamic content (CDN mods, user texture packs, "save bundles"). Nice-to-have after core persistence works. |
| **WASMFS Emscripten patches** (openat, dirperms, packager) | ★★★☆☆ | Small, targeted. Re-apply if we hit the same bugs on current emsdk; consider upstreaming. |
| **Launcher UX patterns** (proxy select, console, resolution, progress, pointerlock) | ★★★★ | Pure web frontend — copy ideas + modernize (TS, nice UI). |
| **Build flags & memory/pthreads/WebGL2 config** | ★★★★ | Directly applicable. |

### Low / No Reusability (Rewrite or Avoid)
- The **paradust7/minetest fork** itself — too old, too divergent.
- The entire bespoke shell build system + vendored deps — our CMake + `-sUSE_*` + preset is superior for maintainability.
- The **deeply invasive integration** (new mainloop.cpp + 20+ cwrap exports + changes scattered across clientlauncher/game/server.cpp) — creates permanent maintenance tax.
- The full socket reimplementation (keep the *protocol*, replace the hundreds of lines of C++ shim if possible with something thinner).
- Persistence implementation (whatever exists) — it didn't solve the problem per their own issues.

### Comparison to Upstream Luanti + Our Current luanti_wasm State
- **Upstream Luanti**: Zero official WASM. IrrlichtMt has partial Emscripten bits (SDL, EGL stubs). Our wasm_porting.md + existing guarded code (porting_emscripten, socket stubs, CMake Emscripten support, IDBFS) is a clean modern starting point.
- **paradust**: More "done" on the hard problems (multiplayer that works today, non-blocking execution, runtime content).
- **Our edge**: Modern engine, better FS intent (IDBFS), cleaner build foundation. **Gap**: No working multiplayer transport, no proven main-loop solution, no launcher.

---

## 3. Biggest Technical Risks & Opportunities (Browser Client Specific)

### Risks (Unique or Acute in Browser)
- **Persistence is existential**: If players lose worlds on reload or tab crash, the product is unusable for anything but demos. paradust never cracked this at scale. OPFS quotas, async perf, private mode, site-data clearing, and SQLite + Lua interactions are all traps.
- **Networking model tradeoffs**: WS proxy adds latency/jitter, is a SPOF/privacy concern, and requires ongoing operation. WebTransport (UDP-ish native in browser) is emerging but not universal yet.
- **Memory & threading constraints**: 256MB–2GB is easy to blow. pthreads + COOP/COEP headers make embedding in arbitrary pages/iframes hard (breaks isolation).
- **Input/UX expectations**: Pointerlock is gesture-only and fragile. No keyboard on mobile/tablet by default. Touch controls are a whole separate Android-grade feature.
- **Divergence death spiral**: Any fork that touches 100+ files for WASM will bitrot instantly as Luanti moves (new rendering, physics, mod API, etc.).
- **Content & mods**: Many popular mods/games will just not work (perf, native deps, assumptions). C++ mods impossible. Untrusted mod code in browser context has extra security surface.
- **Distribution**: Large .wasm + .data + assets. Initial load time, caching strategy, and update story matter enormously.

### Opportunities (Where Web + Our Strengths Win)
- **Instant play / zero install** is the killer feature. Link in chat → playable world in <10s.
- **Embedding & sharing**: Canvas widget, "play this exact map with these mods" deep links, spectator mode, easy recording/sharing of clips.
- **PWA + offline**: Service worker + precached assets + OPFS = playable on planes/trains with no net (after first load). Huge for education/creative use.
- **Modern web tech**: Better shaders (eventually WebGPU), Web Audio for superior sound, WebRTC for future lower-latency direct P2P (bypass proxy for some cases), excellent DevTools.
- **Creative/educational tooling**: In-browser world editor, mod sandbox with live reload, classroom "join this server" buttons.
- **Fast iteration**: We (web + creative tooling strengths) can outpace native on the *web experience layer* even if core engine parity lags.

---

## 4. Recommended Strategy & Tradeoffs

**Primary Recommendation: "Clean Base + Selective High-Leverage Port" (Hybrid)**

Stay on **upstream Luanti** (our current luanti_wasm tree). Treat paradust's work as a **proven reference implementation and design spec**, not a codebase to fork.

**Concrete Plan:**
1. Keep/expand our CMake + Emscripten preset + porting_emscripten layer (already better in some ways).
2. **Port 1 (high priority):** Networking transport — implement a clean `WebSocketProxySocket` (or reuse/adapt emsocket logic) + a minimal, self-hostable proxy server (Node or whatever we prefer). Support the proven encapsulation for UDP game traffic. Start with client-to-existing-servers; add in-browser hosting later.
3. **Port 2 (high priority):** Non-blocking execution — introduce a small, well-isolated `EmscriptenMainLoop` or step-based refactor of `Game` + `ClientLauncher` (inspired by but not copying the complexity of mainloop.cpp). Use `emscripten_set_main_loop` + explicit yields, or a controlled ASYNCIFY subset. Expose only the minimal JS hooks needed.
4. **Port 3 (medium):** Runtime pack loader (tar.zst + libarchive) as an optional "ContentPackSystem" for dynamic games/mods/textures. Nice for a "no install" experience.
5. **Core work (our advantage):** Make **persistence rock-solid first** (IDBFS + OPFS backend options, explicit sync points after world save / player leave / settings change, beforeunload handler, quota warnings, export/import UI). This is the #1 thing paradust never delivered.
6. Build a modern, beautiful, embeddable launcher (HTML/TS or simple) that makes the "instant browser tab" magic real.
7. Add CI that actually builds + hosts a demo (GitHub Pages + proper headers is non-trivial but doable).
8. Upstream anything that makes sense (better Emscripten platform abstractions, WASMFS fixes).

**Pros of Recommended Strategy**
- Long-term maintainable (small surface area of guarded `#ifdef __EMSCRIPTEN__` + separate JS proxy lib).
- Benefits from all future Luanti improvements automatically.
- Lets us move fast on the *web-specific* value (launcher, embedding, PWA, persistence UX) where we have strength.
- Avoids the "we are now 2 years behind on engine features" trap.

**Cons**
- 3–6 months more initial work than "just fork paradust and forward-port" (but that path has 5+ year tax).
- We still have to build/run a proxy (but it's a small, well-scoped service; we can start by self-hosting a version of his if licensing allows, or reimplement cleanly).

**Rejected Alternatives**
- Full fork of paradust7/minetest + forward-port: High short-term velocity, catastrophic maintenance. Do not do this.
- Pure fresh start ignoring paradust: Wastes the only real-world data point we have on "what actually works for multiplayer in the browser."

**When to Reconsider Full Reuse**
Only if Luanti upstream adopts a large part of the WASM work officially, or if we decide this is a permanent hard fork with its own release cadence (unlikely for "practical client").

---

## 5. Prioritized Next Technical Steps (for GitHub Issues)

1. **Persistence MVP** (P0 — unblocks all real use)
2. **WebSocket Proxy Transport + Basic Multiplayer** (P0 — the feature that makes it more than a tech demo)
3. **Browser-Compatible Main Loop / Yielding** (P0 — prevents frozen tabs, enables real UX)
4. **Modern Web Launcher + Embedding Surface** (P1 — the "wow" and shareability)
5. **Build, CI, Demo Hosting & Documentation** (P1 — without this nobody can try it)
6. **Runtime Content Packs + Polish** (P2)
7. **Mobile/Touch, Sound, Memory Tuning, PWA/Offline** (P2+)

See the generated issues below for details, suggested labels, and dependencies.

---

## Appendix: Key References from Analysis

- paradust open issues (especially #32 "No way to save game")
- `webshims/src/emsocket/{proxy.js, emsocket.cpp, ProxyLink.cpp, ...}`
- `minetest-wasm/{build_minetest.sh, build_fsroot.sh, build_www.sh, static/launcher.js, apply_patches.sh, emsdk_*.patch}`
- `paradust-minetest/src/{mainloop.cpp, porting.cpp (EMSCRIPTEN sections), network/socket.cpp}`
- Our `wasm_porting.md`, `src/porting_emscripten.*`, `src/CMakeLists.txt` (EMSCRIPTEN branch), current IDBFS work.

**Conclusion:** paradust did the hard, unglamorous engineering to prove the concept is viable. We should stand on his shoulders for the *networking and execution model*, while building a cleaner, current, persistence-first, low-divergence client on the modern Luanti tree. This gives us the best chance of shipping something people will actually use and that we can maintain.

---

*This investigation is intended to be living — update as the port progresses and as upstream Emscripten/Luanti change.*