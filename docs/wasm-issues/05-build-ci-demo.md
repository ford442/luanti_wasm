# [WASM] Reproducible Emscripten Build, CI, and Public Demo Hosting

**Labels:** `wasm`, `build-system`, `ci`, `P1`

**Milestone:** Browser Client MVP (v0.1)

## Current Situation

The `Emscripten` preset now prepares the required Emscripten ports, builds a
pinned zstd source archive, and produces a generated client with SDL2,
OffscreenCanvas/WebGL2, pthreads, legacy JS FS + IDBFS, and the preload bundle.
The generated client passes a headless Chrome startup smoke with storage ready
before the application worker starts.

However:
- No automated CI job that builds the WASM target on every PR (or nightly).
- No public demo that outsiders can try without cloning + installing emsdk + fighting COOP/COEP headers.
- The build still requires a full emsdk; CI does not yet guard the path.
- Hosting a real demo is non-trivial (must serve with `Cross-Origin-Opener-Policy: same-origin` and `Cross-Origin-Embedder-Policy: require-corp` for pthreads + SharedArrayBuffer).
- Our vendoring / asset strategy for the big preload `.data` file needs care for cache invalidation and load time.

paradust7's system (content-addressed release UUIDs, separate packs, custom www builder, `.htaccess` templates) shows one working model. We can do something similar or simpler.

## Goals

- [x] `cmake --preset Emscripten` produces `luanti.html` + `.js` + `.wasm` + `.data` and passes the local generated-client startup smoke.
- [ ] GitHub Actions workflow (`.github/workflows/wasm.yml` or similar) that:
  - Installs emsdk (pinned version for reproducibility).
  - Builds the WASM client in Release mode.
  - Uploads the artifacts (or deploys to GitHub Pages / a demo bucket on success for `main`).
- [ ] A public, always-up-to-date demo at something like `https://luanti-wasm.example.org/` or a GitHub Pages site (with proper headers — this may require a Cloudflare Worker / thin nginx proxy or Pages + special config).
- [ ] Clear `doc/compiling/wasm.md` (or update `wasm_porting.md`) with exact steps, common pitfalls (headers, memory, asyncify vs main_loop), and how to run a local demo with the required COOP/COEP.
- [ ] Basic smoke test (even if manual or Playwright-driven in headless with xvfb + special flags) that the main menu renders and a world can at least start loading.
- [ ] Asset / binary versioning strategy so updates don't break clients mid-session (or at least a clear "hard refresh" instruction).

## Non-Goals for First Pass

- Full matrix of debug/profile/release + different emsdk versions.
- Automatic visual regression screenshots (nice later).
- Self-updating "nightly" vs "stable" channels (overkill initially).

## Implementation Hints

- Pin emsdk 6.0.3 in the future workflow and validate pthreads plus the explicitly linked legacy IDBFS backend.
- Consider using Emscripten's own `embuilder` + ports more aggressively to reduce custom build scripts.
- The preload-file list is already in CMakeLists — keep it there as the source of truth.
- For GitHub Pages demo: the headers problem is well-known. Common solutions:
  - Cloudflare Pages / Worker (easy header injection).
  - A tiny Express / Caddy / nginx static server in a Docker container on a cheap VPS.
  - Document "run locally with this Python serve.py that adds the headers."
- Start the CI job as "optional" / "manual" then make it required once stable.

## Success Criteria

- A contributor can run the documented commands on a fresh Ubuntu box (or via the provided Dockerfile) and have a working local demo in < 30 minutes.
- `main` branch pushes produce a new demo build within an hour that external people can try without special setup.
- WASM build failures are caught in CI before they reach users (currently they are invisible).

## Dependencies

- Benefits from the persistence and async loop work (a demo that crashes on world load or freezes the tab is bad PR).
- The launcher work will consume the output of this (the www/ tree + versioned assets).

---

**Related:** `CMakePresets.json` (Emscripten preset), `src/CMakeLists.txt:774` (the big `if(EMSCRIPTEN)` linker block), `wasm_porting.md` "Appendix: Useful Emscripten Flags" and "Build Instructions (Target)", our current lack of `.github/workflows/*wasm*`.

This is the "make it real for other people" issue. Without a working public demo + easy local repro, the port will stay a private research project.
