# [WASM] Reproducible Emscripten Build, CI, and Public Demo Hosting

**Labels:** `wasm`, `build-system`, `ci`, `P1`

**Milestone:** Browser Client MVP (v0.1)

## Current Situation

The `Emscripten` preset now prepares the required Emscripten ports, builds a
pinned zstd source archive, and produces a generated client with SDL2,
OffscreenCanvas/WebGL2, pthreads, legacy JS FS + IDBFS, and the preload bundle.
The generated client passes a headless Chrome startup smoke with storage ready
before the application worker starts.

CI now builds the target with pinned Emscripten 6.0.3, runs the generated-client
startup smoke, uploads a versioned deployment artifact, and can deploy the
default branch to Cloudflare Pages. A repository owner still needs to create
the Pages project and configure its GitHub variable and credentials before a
public URL exists. The deployment enable flag must remain off until menu
rendering and world-entry acceptance pass the manual release gate; the current
automated smoke does not claim visual proof.

paradust7's system (content-addressed release UUIDs, separate packs, custom www builder, `.htaccess` templates) shows one working model. We can do something similar or simpler.

## Goals

- [x] `cmake --preset Emscripten` produces `luanti.html` + `.js` + `.wasm` + `.data` and passes the local generated-client startup smoke.
- [x] GitHub Actions workflow (`.github/workflows/wasm.yml`) that:
  - Installs emsdk (pinned version for reproducibility).
  - Builds the WASM client in Release mode.
  - Uploads the artifacts (or deploys to GitHub Pages / a demo bucket on success for `main`).
- [ ] A public, always-up-to-date demo. The Cloudflare Pages deployment path is
  implemented; project creation, credentials, URL verification, and the manual
  menu/world release gate remain owner/deployment work.
- [x] Clear `doc/compiling/wasm.md` with exact steps, common pitfalls (headers,
  memory, worker main loop vs Asyncify), local serving, and deployment setup.
- [x] Basic launcher/world smoke. Playwright verifies the ready launcher,
  starts DevTest, observes real engine world-loading status, and rejects page
  errors; optional screenshots retain the manual visual gate.
- [x] Asset / binary versioning strategy: each engine plus launcher/PWA output
  is packaged under `releases/<git-sha>/`, with a non-cacheable root, immutable
  release files, and a revalidated service-worker script.

## Non-Goals for First Pass

- Full matrix of debug/profile/release + different emsdk versions.
- Automatic visual regression screenshots (nice later).
- Self-updating "nightly" vs "stable" channels (overkill initially).

## Implementation Hints

- Keep emsdk 6.0.3 pinned in the workflow and validate pthreads plus the explicitly linked legacy IDBFS backend.
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

**Related:** `CMakePresets.json`, `src/CMakeLists.txt`,
`.github/workflows/wasm.yml`, `doc/compiling/wasm.md`, and `wasm_porting.md`.

This is the "make it real for other people" issue. Without a working public demo + easy local repro, the port will stay a private research project.
