# [WASM] Non-Blocking Main Loop & Browser Yielding (MainLoop Adapter)

**Labels:** `wasm`, `core-engine`, `P0`, `browser-mvp`

**Milestone:** Browser Client MVP (v0.1)

## The Problem

Luanti's core game loop (and the internal server) is written as blocking `while (m_rendering_engine->run()) { ... }` loops in:

- `src/client/clientlauncher.cpp`
- `src/client/game.cpp`
- Various server/emerge threads

In a browser, a long-running blocking loop **freezes the tab**, blocks event handlers, prevents pointerlock requests from working reliably, starves the JS event loop, and triggers "page unresponsive" warnings.

Emscripten offers two main escape hatches:
- `-sASYNCIFY` (automatic yield points at `emscripten_sleep` / certain calls) — convenient but has code-size and perf cost, and can be surprising.
- `emscripten_set_main_loop()` + explicit `step()` extraction — more control, better perf, but requires refactoring the loop state out of local variables into class members or a state machine.

paradust7 solved this with a sophisticated custom `mainloop.cpp` (helper pthread, `emloop_pause`/`unpause`, `RunAsyncThenResume`, blessed reentry, rAF coordination). It works, but is invasive (new file + changes across the engine + many exported cwrap functions).

## Goals for This Issue

- [ ] The WASM client runs with a **responsive browser tab** (animation, input, console, and UI overlays all work while the game is "running").
- [ ] No hard-freeze on long operations (mapgen, initial load, heavy Lua, etc.).
- [ ] Clean, minimal, maintainable integration:
  - Prefer a small number of new guarded files or a single `EmscriptenMainLoop` helper.
  - Avoid scattering `EM_ASM` and cwraps throughout the engine.
  - Keep native behavior 100% unchanged.
- [ ] At minimum, the main menu is fully interactive and a singleplayer world can be created/loaded and played for 10+ minutes without the tab becoming unresponsive.
- [ ] Pointerlock requests from Irrlicht (mouse capture for look) work reliably after a user gesture.
- [ ] (Stretch) A visible "pause" / background tab behavior that doesn't waste CPU.

## Recommended Technical Direction (Hybrid)

We should **not** copy paradust's `mainloop.cpp` verbatim — it is too entangled.

Better options, in rough priority for a clean long-term solution:

1. **Extract a `step()` / `frame()` method** from the hot loops in `Game` and `ClientLauncher`. Store cross-frame state as members. Then use `emscripten_set_main_loop(game_step, 0, true)` (or the newer `emscripten_set_main_loop_arg`).
2. Use a **controlled, minimal ASYNCIFY** surface (only around known blocking points: network recv in certain modes, initial asset load, mapgen chunks) + `emscripten_sleep(0)` or `emscripten_yield()`. This can be a quick bridge while the refactor happens.
3. Keep a very small "browser platform driver" (similar to our existing `porting_emscripten`) that owns the main loop contract and calls back into the engine.

Study paradust's approach for the *semantics* (especially the helper thread for truly blocking IO that must not freeze the main thread, and the pause/unpause for rAF-driven yielding), but implement a narrower version.

Expose only the smallest possible surface to JS:
- `emloop_request_animation_frame()` (or equivalent)
- Maybe a couple of pause/unpause hooks for the launcher overlay
- Pointerlock coordination (already partially in Irrlicht SDL path)

## Definition of Done

- Load the client in a browser tab.
- Open the main menu, click buttons, type in chat fields — everything feels native-web responsive.
- Create a world, load it, move around, open inventory, chat — tab never freezes.
- DevTools Performance tab shows reasonable frame times with the engine yielding regularly.
- No change in behavior or performance on native Linux/Windows/macOS builds (verified by CI).

## Risks

- Refactoring the game loop is error-prone (state that used to be on the stack must become durable across yields).
- ASYNCIFY can bloat the .wasm dramatically if applied too broadly.
- Threading + async + Emscripten sleep interactions are subtle (we already have pthreads + SHARED_MEMORY requirements).

## Suggested Approach Order

1. Add the Emscripten main loop hook in `main.cpp` / `ClientLauncher` behind `#ifdef __EMSCRIPTEN__` (small spike to prove responsiveness).
2. Land the minimal `step()` extraction for the menu + basic gameplay loop.
3. Add the helper-thread / async task pattern only where truly needed (network connect, heavy FS ops, etc.).
4. Wire up pointerlock + rAF request hooks.
5. Measure and tune (some operations may still need to be moved off the "game" thread).

## Dependencies

- Works well with the persistence work (syncs must be non-blocking or properly yielded).
- Networking proxy work will benefit hugely (the proxy JS lives on the main thread / worker and needs the engine to yield).

---

**References:** `wasm_porting.md` "Phase 3: Async Main Loop", paradust7's `src/mainloop.cpp` (for ideas, not code), Emscripten docs on `emscripten_set_main_loop` and ASYNCIFY, current blocking loops in `clientlauncher.cpp:181` and `game.cpp`.

This is one of the three P0 pillars (with persistence and networking) that makes a browser client feel like a real web application instead of a ported native binary.