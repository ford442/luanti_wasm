# [WASM] Responsive Browser Main Loop

**Labels:** `wasm`, `core-engine`, `P0`, `browser-mvp`

**Milestone:** Browser Client MVP (v0.1)

## Implemented MVP architecture

The Emscripten target uses `-sPROXY_TO_PTHREAD=1`. Emscripten's small entry
stub starts Luanti's existing synchronous `main()` on an application worker,
so the browser main thread remains available for DOM events, the generated
shell, IndexedDB callbacks, pointer-lock processing, and the browser's own
rendering work.

This is a deliberate bridge, not an `emscripten_set_main_loop()` conversion.
The blocking stack is larger than the two visible render loops:

- `ClientLauncher` owns the outer menu/game lifecycle.
- `GUIEngine` runs its loop from construction.
- `Game::run()` keeps substantial frame state in local variables.
- startup, connect, content loading, server start, and shutdown also contain
  synchronous waits.

Converting only `Game::run()` would therefore leave several browser-blocking
paths and introduce unsafe object-lifetime transitions. The worker-main mode
keeps those native control-flow and lifetime rules intact and does not require
Asyncify.

## Build contract

The browser link uses:

```text
-pthread
-sSHARED_MEMORY=1
-sPROXY_TO_PTHREAD=1
-sOFFSCREEN_FRAMEBUFFER=1
```

Irrlicht creates its context through SDL/EGL. That path currently proxies GL to
the browser-owned canvas, so `OFFSCREEN_FRAMEBUFFER` supplies explicit frame
composition while the engine stays on its application worker. Directly
transferring `#canvas` with `OFFSCREENCANVAS_SUPPORT` is not enabled: Emscripten
6.0.3's SDL/EGL context creation is proxied to the main thread and cannot call
`getContext()` after that canvas has transferred. The application calls
`porting::emscripten_validate_main_loop()` before engine initialization and
aborts with a clear diagnostic if a build accidentally runs the synchronous
stack on the browser main thread.

Pthreads and shared WebAssembly memory require a secure context plus these
response headers on the HTML, JavaScript, Wasm, worker, data, and asset
responses:

```text
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```

The generated page and its subresources must remain same-origin or opt in to
the applicable cross-origin resource policy. A plain `file://` URL is not a
supported launch path.

## Frame and shutdown services

`RenderingEngine::run()` calls
`porting::emscripten_service_browser_frame()` once for every menu, launcher,
and gameplay frame. The first consumer is persistence: committed dirty
generations are forwarded to the browser main thread without blocking it on
`FS.syncfs()`.

During graceful application shutdown, the application worker may wait for the
urgent final persistence generation. The browser main thread remains live to
finish IndexedDB callbacks, update the visible status, and run retries. A
persistent storage error intentionally leaves the worker waiting with a sticky
error rather than silently exiting with unsaved data.

## Input and background behavior

Irrlicht's SDL device already installs mouse callbacks on `#canvas`. A canvas
mouse-down requests pointer lock when the game cursor is hidden, preserving
the required user-activation path. SDL/Emscripten routes those events to the
application worker.

Visibility and focus are also already centralized in the SDL device and
`FpsControl`: unfocused frames use `fps_max_unfocused`, and hidden-window draws
are skipped. Sleeps now block only the application worker rather than the
browser main thread.

## Verification

Run the focused smoke with Emscripten 6.0.3 and Playwright installed:

```bash
python3 util/wasm/test_async_main_loop.py
```

It builds a real pthread + SDL/WebGL probe using the production worker-main
and offscreen-framebuffer flags, serves it with COOP/COEP, and verifies in
Chromium that:

- C++ `main()` runs off the browser main thread;
- an SDL/EGL WebGL context is usable from the application worker;
- browser-main timers continue while the C++ stack deliberately stays in a
  blocking loop; and
- a canvas click reaches the worker-side mouse callback and acquires pointer
  lock.

The full acceptance pass still requires a complete engine build: use the main
menu, create/load a singleplayer world, play for at least ten minutes, exercise
inventory/chat/mouse look, and inspect browser performance traces in Chrome,
Edge, and Firefox.

## Known boundary and follow-up

Worker-main isolation prevents engine work from making the entire page
unresponsive. It cannot make the game canvas render while one long-running Lua
callback or engine operation monopolizes the application worker; input remains
queued and DOM overlays remain responsive until that operation returns.

If profiling shows unacceptable canvas stalls, move the specific operation to
an existing worker subsystem or perform a complete launcher/menu/game state
machine conversion. A future `emscripten_set_main_loop()` migration must cover
all lifecycle phases above, not only the hot gameplay loop. Broad Asyncify is
not part of the MVP.

---

**References:** `src/CMakeLists.txt`, `src/porting_emscripten.cpp`,
`src/client/renderingengine.h`, `irr/src/CIrrDeviceSDL.cpp`, and
`util/wasm/test_async_main_loop.py`.
