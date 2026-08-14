# Compiling Luanti for WebAssembly

The `Emscripten` preset builds the browser client in Release mode with
Emscripten 6.0.3. It emits a directly servable HTML shell and its JavaScript,
WebAssembly, and preloaded-data companions.

## Prerequisites

On a fresh Ubuntu system, install Git, CMake, Python, and normal build tools:

```bash
sudo apt update
sudo apt install build-essential cmake git python3 python3-pip
```

Install the same Emscripten SDK revision used by CI:

```bash
git clone https://github.com/emscripten-core/emsdk.git
cd emsdk
git checkout 1b8b2456bf3f54fd6e47d55a82dde7752978a40f
./emsdk install 6.0.3
./emsdk activate 6.0.3
source ./emsdk_env.sh
cd /path/to/luanti_wasm
```

The checkout pins both the SDK version and installer revision. The first
configure needs internet access: it populates Emscripten's SDL2, zlib, PNG,
JPEG, Freetype, and SQLite ports. Luanti also builds the SHA-256-pinned zstd
1.5.7 source archive declared by the repository.

If the SDK is installed somewhere this user cannot modify, choose a writable
ports and system-library cache before configuring:

```bash
export EM_CACHE="$PWD/.cache/emscripten-6.0.3"
```

## Build and run

Configure and build with the checked-in preset:

```bash
cmake --preset Emscripten
cmake --build build-wasm --parallel 2
```

The preload-file list in `src/CMakeLists.txt` is the source of truth for the
read-only asset bundle. A successful build creates the engine bundle and
launcher/PWA companions:

```text
build-wasm/bin/luanti.html
build-wasm/bin/luanti.js
build-wasm/bin/luanti.wasm
build-wasm/bin/luanti.data
build-wasm/bin/launcher.js
build-wasm/bin/launcher.css
build-wasm/bin/launcher-config.js
build-wasm/bin/manifest.webmanifest
build-wasm/bin/service-worker.js
build-wasm/bin/luanti-web.svg
```

Serve the output with the repository helper:

```bash
python3 util/wasm/serve.py
```

Open <http://127.0.0.1:8000/luanti.html>. Do not open the HTML with a
`file://` URL or use a plain static server. Pthreads and shared WebAssembly
memory require a secure context (HTTPS, or localhost for development) and
these headers on every response:

```text
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```

The helper also sends `Cross-Origin-Resource-Policy: cross-origin` so an
isolated parent page can embed the demo, disables local caching, and serves
`.wasm` as `application/wasm`.

The page first prepares the asset bundle and persistent filesystem, then
enables the launcher. Start a local DevTest world or choose Join server. A
remote server additionally requires a configured WebSocket/UDP proxy.

To serve another build directory or accept connections from another machine:

```bash
python3 util/wasm/serve.py --directory build-wasm/bin --bind 0.0.0.0 --port 8000
```

Binding to all interfaces does not provide HTTPS. Use a TLS reverse proxy for
non-localhost access.

## Smoke tests

The generated-client test needs Playwright's Python package and an installed
Google Chrome:

```bash
python3 -m pip install --user playwright==1.59.0
python3 util/wasm/test_client_browser.py
```

It verifies that the page is cross-origin isolated, IndexedDB hydration is
ready before the launch button is enabled, networking starts disabled, a local
world can be launched, C++ runs on an application worker, browser-main timers
remain responsive, and real engine loading status reaches the launcher. This
is the automated CI smoke; it is not a visual regression test.

Before publishing a demo, perform this manual browser gate:

1. Confirm the main menu is visibly rendered, resizes with the window, and
   accepts mouse and keyboard input.
2. Create a DevTest world and start it. Confirm the loading screen advances
   into gameplay rather than leaving the tab or canvas frozen.
3. Exit to the menu, reload the page, and confirm the world remains available.
4. Check the browser console for WebGL, pthread, preload, or IndexedDB errors.

The current headless smoke does not replace this menu/world gate.

## CI and demo deployment

`.github/workflows/wasm.yml` runs one Release build on relevant pull requests,
default-branch pushes, and manual dispatches. It installs Emscripten 6.0.3,
runs the browser smoke, packages the result, and uploads a 14-day artifact.
Once stable, make the `wasm / Release build and browser smoke` check required
in branch protection.

Production deploys use a pre-created Cloudflare Pages Direct Upload project.
Set that project's production branch to this repository's default branch.
Configure these GitHub repository settings:

- Variable `WASM_DEMO_DEPLOY_ENABLED`: set to `true` only after the manual
  menu/world gate passes on the candidate hosting setup.
- Variable `CLOUDFLARE_PAGES_PROJECT`: the Pages project name.
- Secret `CLOUDFLARE_ACCOUNT_ID`: the owning Cloudflare account ID.
- Secret `CLOUDFLARE_API_TOKEN`: a token allowed to deploy that Pages project.

Unless the enable variable is exactly `true` and the project variable is set,
CI still builds, tests, and uploads the demo artifact but deliberately skips
external deployment. Cloudflare Pages reads the generated `_headers` file and
applies the required isolation headers to the static responses. Verify a
deployed build with:

```bash
curl -I https://PROJECT.pages.dev/
curl -I https://PROJECT.pages.dev/releases/BUILD_ID/luanti.wasm
```

Both responses must include COOP and COEP before the demo is announced.

## Versioning and caches

`util/wasm/package_demo.py` places every generated build under
`releases/<git-sha>/`. The engine bundle and launcher/PWA files therefore share
one immutable build namespace and cannot be mixed with companions from another
revision. Root `index.html` and `version.json` are served with `no-store`; the
build-scoped files are served with a one-year immutable cache policy. The
service-worker script is the exception and is revalidated so browsers can
discover an update; its cache is scoped to the immutable release URL.

Create the same layout locally with:

```bash
python3 util/wasm/package_demo.py \
  --version "$(git rev-parse HEAD)" --output wasm-demo
python3 util/wasm/serve.py --directory wasm-demo
```

The output directory must not already exist. A user who keeps an old tab open
continues to use that tab's coherent build. Opening the demo root again selects
the current build. If an older deployment was cached before this strategy was
introduced, close old tabs, clear site data, and hard-refresh once.

## Runtime constraints and common failures

- The current target uses `PROXY_TO_PTHREAD` and an offscreen framebuffer to
  keep the synchronous engine stack off the browser UI thread. It does not use
  Asyncify or `emscripten_set_main_loop()`.
- Initial memory is 256 MiB and may grow to 1 GiB. Mobile browsers and
  memory-constrained devices can still terminate the tab.
- An SDL version probe that reports SDL is too old can mask a failed linker
  probe. Inspect `build-wasm/CMakeFiles/CMakeConfigureLog.yaml`; a read-only
  SDK cache is fixed by setting `EM_CACHE` to a writable directory, then
  reconfiguring from a clean build directory or clearing the failed probe.
- A missing `SharedArrayBuffer` normally means HTTPS/localhost or COOP/COEP is
  wrong. Check both the document and subresource response headers.
- A 404 for `.data`, `.wasm`, or a launcher/PWA companion means the generated
  output was separated or stale HTML referenced another deployment. Deploy the
  packaged directory as one unit.
- Startup storage errors are fail-closed by design. The shell reports the
  IndexedDB error instead of silently starting with an ephemeral filesystem.
- Remote multiplayer additionally needs a configured WSS proxy; it is not
  required for the singleplayer build or CI smoke.

See `wasm_porting.md` for architecture details and the remaining browser MVP
work.

See [wasm-embedding.md](wasm-embedding.md) for deep links, proxy-region
configuration, iframe permissions, PWA behavior, and embedding limitations.
