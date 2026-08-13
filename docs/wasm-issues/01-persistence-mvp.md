# [WASM] Reliable browser persistence

**Labels:** `wasm`, `persistence`, `P0`, `browser-mvp`

**Milestone:** Browser Client MVP (v0.1)

## Implementation

Luanti uses Emscripten's legacy JavaScript filesystem and mounts IDBFS at
`/home/web_user/.luanti`. The link explicitly retains IDBFS with `-lidbfs.js`;
this issue does not introduce WASMFS or OPFS.

`client/web/persistence.js` runs as `--pre-js`. Its `Module.preRun` hook:

1. adds a run dependency;
2. creates and mounts the user-data path;
3. hydrates the in-memory filesystem with asynchronous `FS.syncfs(true)`;
4. creates the required user subdirectories; and
5. removes the dependency only after all steps succeed.

This makes saved data available before C++ `main()`. A mount or hydration error
is fatal: the dependency remains held, the canvas is hidden, and the shell shows
the storage error. The engine must not start against an empty temporary
filesystem and overwrite a user's durable data.

At runtime, committed engine writes increment an atomic dirty generation. Save
threads never call JavaScript. The application worker services the latest
generation through `RenderingEngine::run()` and forwards it to the browser main
thread. Ordinary flush starts are separated by at least ten seconds; disconnect
and shutdown requests bypass that delay.
JavaScript permits one `FS.syncfs(false)` at a time and coalesces writes observed
during a flush into one follow-up. Failed writes remain dirty and retry after
1, 5, and then 30 seconds, capped at 30 seconds until a save succeeds.
The engine's existing `server_map_save_interval` setting controls the periodic
world/mod-storage commit cadence; the ten-second layer only coalesces browser
durability work after those commits.

Dirty hooks cover committed server map transactions, player saves, environment
metadata, server and client mod storage, successful global settings writes, and
completed game teardown. They deliberately do not flush once per map block.

`visibilitychange` while hidden, `pagehide`, and `beforeunload` request an urgent
best-effort sync.
These events can only persist filesystem writes the engine has already committed.
Browsers may terminate a page before asynchronous work completes, so closing a
tab can never be presented as a guaranteed save point. Graceful disconnect
requests an immediate sync. Graceful application shutdown waits on the
application worker until the urgent final generation succeeds; the browser main
thread remains available for callbacks, visible errors, and retries.

## Browser integration contract

The following quoted properties are safe to use from a launcher or embedding
page, including optimized builds:

```js
await Module.luantiPersistence.requestSync({
  reason: "external",
  urgent: true,
});

const snapshot = Module.luantiPersistence.getState();
window.addEventListener("luanti:persistence", event => {
  console.log(event.detail);
});
```

The snapshot and `luanti:persistence` event detail have this shape:

```js
{
  state: "loading" | "ready" | "saving" | "saved" | "error",
  reason: "startup" | "periodic" | "settings" | "disconnect"
        | "shutdown" | "pagehide" | "retry" | "external",
  pending: boolean,
  fatal: boolean,
  error: string | null,
}
```

Startup errors have `fatal: true` and gate `main()`. Runtime errors reject the
current `requestSync()` promise, remain visible while data is unsaved, and clear
only after a background retry succeeds. `client/web/shell.html` maps these states
to loading, saving, saved, and sticky error messages.

## Storage and hosting limits

- IndexedDB storage is scoped to the page origin: scheme, host, and port must be
  stable. Moving between development ports or HTTP and HTTPS creates a different
  store.
- Clearing site data deletes saved worlds and settings. There is no cloud copy.
- Private/incognito profiles may offer a smaller quota and typically discard the
  origin's data when the private session ends. The UI must not call that durable
  cross-session storage.
- Quota, permission, IndexedDB, and browser policy failures are expected runtime
  conditions and are reported through the contract above.
- The pthread build must be served with secure-context-compatible hosting and
  `Cross-Origin-Opener-Policy: same-origin` plus
  `Cross-Origin-Embedder-Policy: require-corp`. Static file hosting must also
  serve `.wasm` with `application/wasm`.

Emscripten documents that non-MEMFS filesystems must be linked explicitly and
that IDBFS durability is driven by asynchronous `FS.syncfs()` calls:
[Filesystem API](https://emscripten.org/docs/api_reference/Filesystem-API.html).
Startup configuration belongs in `Module.preRun`:
[Module lifecycle](https://emscripten.org/docs/api_reference/module.html).

## Verification

The focused smoke is:

```bash
node util/wasm/test_persistence.mjs
python3 util/wasm/test_persistence_browser.py
```

The Node test checks single-flight burst coalescing, fail-closed hydration, and
quota failure with retained dirty state and retry recovery. The Playwright test
links the production pre-js and IDBFS backend into a real Emscripten pthread
probe, verifies `ready` before worker `main()`, flushes a sentinel on a fresh
origin, checks the generated-shell state, reloads, and verifies hydration
restores it.

The repaired Emscripten dependency path now configures and links the generated
client, and the browser startup smoke verifies IDBFS reaches `ready` before the
application worker starts. Release acceptance still requires:

- in Chrome/Edge and Firefox, persist a recognizable world, player position,
  inventory, and setting through ten hard reloads and a browser-profile restart;
- verify urgent disconnect and shutdown completion; and
- repeat in private mode while describing its limitations accurately.

## Out of scope

OPFS and WASMFS migration, cloud synchronization, world import/export, a full
launcher UI, and a complete rAF-driven engine state-machine conversion are
separate work.
