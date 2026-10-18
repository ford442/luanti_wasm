# [WASM] Modern Web Launcher, Embedding & Shareability

**Labels:** `wasm`, `frontend`, `ux`, `P1`

**Milestone:** Browser Client MVP (v0.1) or v0.2 Polish

## Why This Matters

The technical port (engine in WASM) is only half the product. The "instant play in a browser tab" magic comes from the **web experience layer**:

- No native install, no launcher app, no "which version" confusion.
- Beautiful, fast, mobile-aware landing page / join flow.
- One-click or deep-linkable sessions ("join this exact world with these mods").
- Easy embedding in forums, wikis, education sites, itch.io pages, etc.
- PWA installability + offline support (after first load).
- Proxy selection, language, graphics presets, console for debugging.

paradust7 built a functional (if dated) launcher with resolution/aspect selectors, proxy chooser, console, progress, server-in-browser UI, and content-addressed deploys. It proves the pattern works.

We should do better with modern web practices while keeping the core simple and maintainable.

## Goals

- [x] A clean, attractive, responsive vanilla-JS launcher in `client/web/`, copied beside the Emscripten output.
- [x] Deployment-configurable proxy / region selector with singleplayer and custom/self-hosted defaults.
- [x] Direct connect plus the CORS-enabled official Luanti server directory, fetched only on request.
- [x] Player name, low-memory view-distance presets, and engine language selection.
- [x] Real Emscripten asset, IDBFS, engine/world, and shader/content loading status.
- [x] Deep linking: `?address=foo.example.com&port=30000&name=Player&game=devtest`.
- [x] Shareable, password-free link from the running-world toolbar.
- [x] SDL pointer lock, fullscreen, Escape release, focus-resume overlay, and runtime console.
- [x] PWA manifest and release-scoped service worker precaching Wasm plus the base data pack.
- [x] Minimal iframe, permissions, headers, and deployment configuration documentation.
- [x] Mobile warning and an explicit touch-controls roadmap note.

## Non-Goals (MVP)

- Full fancy UI framework (React/Vue) — keep it lightweight so it can be maintained by engine devs.
- Complete in-browser server hosting UI (defer to later).
- Account / cloud save integration.
- Mod browser inside the launcher (ContentDB integration is valuable but secondary).

## Technical Notes

- The launcher must be able to configure the Emscripten `Module` (proxy URL, initial conf overrides, canvas, preRun hooks for FS, etc.) **before** the engine starts.
- We will need a small set of stable cwrap exports from the engine (already partially planned in the async main loop work): `setProxy`, pause/unpause, installPack, setConf, etc.
- Use the existing `build_www.sh` / release UUID pattern or simplify it.
- Service worker + COOP/COEP headers are tricky but mandatory for pthreads/SHARED_MEMORY. Document the hosting requirements clearly (GitHub Pages needs a special setup or a thin proxy).

## Inspiration (Steal Unashamedly)

- paradust7's `static/{index.html, launcher.js, worker.js}` — the structure and features that worked.
- Modern web games (e.g. various itch.io WASM titles, Slay the Spire web ports, etc.) for loading feel and share UX.
- Luanti's own main menu aesthetic (keep some visual continuity).

## Success Metrics

- A new user lands on the demo URL and is in a playable world in < 15 seconds on a fast connection (first visit will be slower due to download + IDBFS population).
- Embedding the client in a third-party page with a specific server prefilled takes < 10 lines of HTML.
- The launcher feels like a first-class web app, not "a native game that happens to be in a browser."

## Dependencies

- Benefits from (but does not strictly block) the async main loop (the launcher needs to drive pause/unpause and show overlays).
- Proxy networking work (the launcher is the natural place to choose / configure the proxy).
- Persistence (saving a world and then "share this world" is powerful).

---

## Implemented contract

The shell sets `Module.noInitialRun` before generated code loads. Emscripten
still completes preload-file work and the fail-closed IDBFS `preRun`; only then
does the launcher enable Play and invoke the exported `Module.callMain()` once
with validated CLI settings. `porting::emscripten_report_status()` sends the
engine's existing loading messages and progress percentages to the browser
main thread. This avoids introducing a broad mutable `cwrap` surface before the
async-loop work has stable pause and re-entry semantics.

Hosted proxy endpoints are deliberately deployment configuration, not source
defaults. The repository cannot promise a region it does not operate.

**Related:** `wasm_porting.md` "Phase 6: Input & Browser Integration",
`doc/compiling/wasm-embedding.md`, and the paradust7 launcher patterns.

This is where our web + creative tooling strengths can shine and differentiate the port from a pure technical exercise.
