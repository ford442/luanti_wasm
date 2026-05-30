# [WASM] Persistence MVP — Make world saves, player data, and settings reliably survive reloads and tab close

**Labels:** `wasm`, `persistence`, `P0`, `browser-mvp`

**Milestone:** Browser Client MVP (v0.1)

## Context & Why This Matters First

The single biggest open wound in the most complete prior art (paradust7/minetest-wasm, open issue #32 "No way to save game" still active years later) is that **players lose their worlds**.

We already have a good start:
- `src/porting_emscripten.cpp` + `porting_emscripten.h` mounts IDBFS at `/home/web_user/.luanti/`
- `emscripten_init_filesystem()` + `emscripten_sync_filesystem()`
- `src/porting.cpp` sets correct `path_user` / `path_share` under `__EMSCRIPTEN__`

But this is incomplete for a *playable* browser client:
- No automatic/strategic calls to `syncfs(false, ...)` after world saves, player logout, settings changes, or on `beforeunload`.
- No handling of async timing, errors, or quota exhaustion.
- No graceful degradation or user-visible feedback ("Saving world... don't close the tab").
- No consideration of OPFS (Origin Private File System) as a higher-performance / higher-quota alternative or complement to IDBFS.
- Interaction with WASMFS (we use `-sWASMFS=1` in the preset) needs validation.
- Singleplayer internal server + SQLite worlds + Lua `World` + mod storage all need to land on persistent storage.

Without rock-solid persistence, everything else (fancy networking, beautiful launcher) is just a tech demo.

## Goals for This Issue (MVP Definition of Done)

- [ ] Worlds created in singleplayer survive a full page reload (close tab, reopen, same world is there with blocks placed).
- [ ] Player position, inventory, and basic metadata persist.
- [ ] `minetest.conf` / user settings changes survive reload.
- [ ] Explicit, reliable calls to `emscripten_sync_filesystem()` (or equivalent WASMFS sync) at the right engine hook points:
  - After a world is saved by the engine.
  - On graceful client disconnect / logout.
  - Periodically during long play sessions (configurable, with backoff).
  - Best-effort `beforeunload` / `pagehide` handler in the launcher.
- [ ] Error handling + console + (optional) HUD toast for sync failures or quota warnings.
- [ ] Basic documentation in `wasm_porting.md` or a new persistence section.
- [ ] (Stretch) Simple "Export World" / "Import World" (.tar.zst or similar) UI in the web launcher for backup/portability.

## Non-Goals (for MVP)

- Full OPFS migration (can be a follow-up if IDBFS proves too slow or quota-limited).
- Cross-device sync or cloud saves.
- Perfect crash-safety (impossible in browser without heroic measures).
- Persistence for in-browser "hosted servers" (later milestone).

## Technical Notes & References

- Study paradust's `emloop_install_pack` + WASMFS patches for inspiration on FS robustness, but we want *engine-native* saves to just work.
- Current Luanti save points: `Server::save()`, `Player::save()`, `Settings` write paths, `mod_storage`, emerge threads, etc.
- We already call `emscripten_init_filesystem()` very early in `main.cpp`.
- The IDBFS mount + sync must complete before the engine starts writing worlds (we have a busy-wait today; consider a cleaner async initialization handshake with the launcher).
- Test matrix: Chrome/Edge/Firefox, incognito, low storage quota simulation, rapid reloads, mid-save tab close (best effort).

## Suggested Starting Points

1. Audit all write paths that should be durable (`src/server/server.cpp`, `src/server/player.cpp`, `src/settings.cpp`, `builtin/...` mod storage, etc.).
2. Add a small `porting::sync_persistent_storage()` helper that is a no-op on native and does the right thing on Emscripten.
3. Wire it into the engine at the obvious save points + add a periodic timer in the client.
4. Enhance the web launcher (or a new `preRun` / `Module` hook) to show saving status and handle `beforeunload`.
5. Add a torture test (create world, place 50 blocks in a pattern, reload 10 times, verify pattern survives).

## Dependencies / Blocks

- None for the basic version (we have the IDBFS mount already).
- Will make later networking + main-loop work feel real instead of throwaway.

**Owner:** TBD (web + engine integration skills helpful)
**Estimate:** 1–2 weeks for solid MVP (including testing across browsers).

---

**Related prior art:** paradust7/minetest-wasm #32, our `wasm_porting.md` sections on File System Strategy and IDBFS, `src/porting_emscripten.cpp`.

This is the foundation. Everything else can be a prototype until this lands.