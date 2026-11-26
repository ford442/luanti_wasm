# Embedding and configuring Luanti Web

The generated `luanti.html` is the supported web entry point. It owns the
launcher, Emscripten module, canvas, persistent filesystem, worker lifecycle,
and service worker. Embed that page rather than loading `luanti.js` directly;
the generated JavaScript is not a stable standalone component API.

## Minimal iframe

```html
<iframe
  src="https://play.example.org/?address=play.example.net&port=30000&game=devtest"
  title="Play Luanti" allow="fullscreen; cross-origin-isolated"
  style="width:100%;height:720px;border:0" allowfullscreen></iframe>
```

Because this build uses pthreads and `SharedArrayBuffer`, every document in the
frame chain must be cross-origin isolated. Serve both the embedding page and
Luanti responses with:

```text
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
Cross-Origin-Resource-Policy: cross-origin
```

Do not sandbox the iframe unless the sandbox includes at least
`allow-scripts allow-same-origin allow-pointer-lock`. Add `allow-forms` if the
host wraps the launcher in a form workflow. Fullscreen additionally needs the
iframe `allow`/`allowfullscreen` permission shown above. Confirm
`crossOriginIsolated === true` inside the child frame before debugging an
Emscripten pthread failure.

Cross-origin isolated top-level pages cannot freely embed unrelated third-party
content. If a forum, wiki, or education platform cannot adopt COOP/COEP for its
whole frame chain, link to the standalone demo in a new tab instead.

## Deep links

The launcher accepts these query parameters:

| Parameter | Meaning |
| --- | --- |
| `address` | Prefills a server hostname or IPv4 address and opens Join server. |
| `port` | Server UDP port, default `30000`. |
| `name` | Player name, limited to letters, digits, `_`, and `-`. |
| `game` | Local game ID, currently `devtest`. |
| `view` | View-distance preset: `60`, `100`, or `160`. |
| `language` | Engine locale code when the deployment includes locale packs. |
| `proxy` | Custom `ws://` or `wss://` UDP proxy URL. HTTPS pages require WSS. |
| `autostart=1` | Start after assets and storage are ready if all fields validate. Ignored with `world`. |
| `worldname` | Preselect a saved world by name (it must belong to `game`). |
| `world` | HTTPS (or same-origin) URL of a `.luantiworld` to offer. The launcher downloads it, shows its game, size and mods, and imports a copy only if the player confirms. The host must allow CORS. |

An ordinary shared server link should omit `name`, `proxy`, and `autostart` so
the recipient chooses their identity and uses the deployment's nearest proxy.
The in-game Copy invite link button follows that rule. URLs never include a
password.

## Hosted proxy regions

Edit `launcher-config.js` in the deployed output, or its source at
`client/web/launcher-config.js`, to publish deployment-owned proxy regions:

```js
window.LUANTI_WEB_CONFIG = {
  serverListUrl: "https://servers.luanti.org/list.json",
  defaultProxy: "wss://eu-proxy.example.org/",
  proxies: [
    { id: "eu", label: "Europe", url: "wss://eu-proxy.example.org/" },
    { id: "na", label: "North America", url: "wss://na-proxy.example.org/" }
  ]
};
```

This file is public: do not put credentials in it. The launcher starts with
singleplayer-only networking when no hosted proxy is configured. Direct
connect and the public server list then explain that remote play needs a WSS
proxy rather than failing later in the engine. The repository ships with
`defaultProxy: ""` and no `proxies`; a deployment sets them when it deploys,
and no proxy address belongs in the client source.

A proxy that is not on the player's own machine (not `localhost`, `127.x` or
`::1`) can read the game: Luanti's protocol is unencrypted, so the proxy sees
gameplay and chat in the clear. The **Join server** panel says so whenever the
selected proxy is not loopback.

When the proxy refuses a join or cannot be reached, the launcher reports why
instead of a generic connection error. `Module.luantiLauncher.getState().proxy`
holds `{state, url, message, reason, closeCode}`: `message` is the sentence
shown to the player (for example that the proxy does not allow this page's
origin, is full, will not forward to that server, or could not be reached),
and `reason` is the tag the proxy closed with (`origin`, `per_ip_limit`,
`global_limit`, `target_denied`, `rate_limited`, ...; `null` when it said
nothing). The same text is in `Module.luantiNetwork.getState().error` and the
`luanti:network` event. The close reasons are listed in
`util/wasm/proxy/README.md`.

## Launcher scripts

The page is plain classic JavaScript on purpose. The engine's `--pre-js` files
are concatenated into `luanti.js` in link order and run before `main`; they are
not ES modules, and a bundler or a TypeScript build step would fight that
order. The launcher on top of them follows the same rule: one script per
concern, loaded by `shell.html` before `luanti.js`, in a fixed order. Each one
talks to one object and nothing else.

| Script | Owns | Talks to |
| --- | --- | --- |
| `launcher.js` | Shared state and element lookups (`window.luantiShell`), the loading panel, status line, runtime log, the Local / Join server tabs, the in-game toolbar, and `Module.luantiLauncher` | the engine (`reportEngineStatus`, `setPaused`, ...) |
| `launcher-connect.js` | Multiplayer proxy picker, its privacy notice, the public server list | `Module.luantiNetwork` |
| `launcher-library.js` | World list and menu, New / Rename / Delete / Import dialogs, export, `?world=` offers, world thumbnails | `Module.luantiWorlds` |
| `launcher-input.js` | Pointer-lock resume panel, audio unlock, canvas size before the engine owns it, the touch/pointer probe | `Module.luantiInput`, `audio_unlock.js` |
| `launcher-glloss.js` | WebGL context-loss overlay; adds `getGLState` and `notifyContext*` to `Module.luantiLauncher` | `Module.luantiPersistence` |
| `launcher-update.js` | Service-worker registration and the "new version" toast | `service-worker.js` |
| `launcher-start.js` | The launch form: validation, the game's asset package, `callMain` | all of the above |

The order matters: `launcher.js` creates `window.luantiShell` and every later
script adds to it, `launcher-glloss.js` extends the `Module.luantiLauncher`
that `launcher.js` made, and `launcher-start.js` needs the three scripts before
it (`connect`, `library`, `input`). A script that loads out of order throws a
one-line error naming what it needs. `shell.html` lists them like this, and
`util/wasm/test_demo_tools.py` fails if that list, the CMake copy list,
`packages.json`, `package_demo.py` or `deploy_1ink.py` disagree:

```text
launcher.js
launcher-connect.js
launcher-library.js
launcher-input.js
launcher-glloss.js
launcher-update.js
launcher-start.js
```

`worlds.js` is a `--pre-js` that owns storage; `launcher-library.js` only
renders what `Module.luantiWorlds` returns.

### Where new code goes

- New **engine** behaviour is C++ under `#ifdef __EMSCRIPTEN__`. It reaches the
  page through the existing `Module.luanti*` objects, not through a new
  `EM_JS` launcher in `CIrrDeviceSDL.cpp`.
- New **browser** behaviour goes in the script that owns the object it talks
  to, or in a new script of its own (add it to every list above).
- Every new `Module.luanti*` member is declared in
  `client/web/emscripten-module.d.ts` in the same change as the C++ call and
  the JavaScript that implements it. `LuantiModule` has no index signature, so
  a script that reads an undeclared member fails `npm run typecheck`, and
  `util/wasm/check_module_contract.mjs` (also run by it) fails when C++ reads a
  `Module` member that is not declared. What the launcher scripts share among
  themselves is typed in `client/web/launcher-shell.d.ts`; that is not part of
  the engine contract.
- Add `// @ts-check` to new scripts. `client/web` is checked with
  `noImplicitAny`; `npm run lint` and `npm run typecheck` are the gate
  (`npm test` is the proxy suite only).

## Browser behavior

- Clicking the game lets SDL request pointer lock. Escape releases pointer
  lock or fullscreen; the resume overlay returns focus to the canvas.
- The service worker precaches the coherent HTML, JavaScript, Wasm, data pack,
  and launcher assets. Offline use is available after installation completes;
  multiplayer and the live public server list still require a network.
- Worlds and settings remain origin-scoped in IndexedDB. Embedding the same
  deployment URL preserves that storage; moving to another origin does not.
- The engine runs on its measured frame time, capped by `fps_max`. While the
  page is hidden (`document.hidden`) it runs at `fps_max_unfocused` (default
  10) instead, and the browser main thread stays free for the launcher.
- An embedder can stand the frame loop still with
  `Module.luantiLauncher.setPaused(true)` and resume it with
  `setPaused(false)`. The call is safe at any point of the page lifetime,
  including before the launcher has called `callMain`: it only writes a flag
  in shared memory, and a request made before the runtime exists is applied as
  soon as it does. Paused time is never passed to the simulation as
  one step. A singleplayer server thread keeps running; the client world,
  input and presents wait. `Module.luantiLauncher.getFrameClock()` returns
  `{frames, lastDtimeMs, paused}`.
  Players can export a world as a `.luantiworld` file and import it elsewhere.
  After the first save the launcher asks the browser for persistent storage
  (`navigator.storage.persist()`); browsers may grant it silently or not at all.

## World library API

`Module.luantiPersistence.library` (the same object as `Module.luantiWorlds`)
lets an embedder drive the world library the launcher uses. Every method
returns a promise, waits for storage to hydrate, and saves through the normal
persistence queue. Use it before the engine starts; once `callMain` has run the
engine owns the open world.

| Method | Result |
| --- | --- |
| `list()` | `[{name, game, size, files, created, lastPlayed, modified, creative, damage, hasThumbnail, path}]` |
| `create({name, game, seed?, creative?, damage?})` | The new world. `creative`/`damage` are left to the game when omitted. |
| `rename(from, to)`, `duplicate(from, to?)`, `remove(name)` | The changed world (`remove`: nothing). |
| `exportWorld(name, {writable?, onProgress?})` | A `Blob` (`application/zip`), or `null` after writing to a `FileSystemWritableFileStream`/`WritableStream`. |
| `inspectArchive(blob, {fileName?})` | What an import would do: `{name, game, gameAvailable, files, archiveBytes, uncompressedBytes, content, warnings, …}`. Writes nothing. |
| `importArchive(blob, {name?, fileName?, onProgress?})` | The imported world. Never overwrites; without `name` it picks a free one. |
| `fetchShared(url)` | `{blob, plan, host, …}` for a share link; does not import. |
| `games()`, `storage()`, `thumbnail(name)`, `limits()` | Available games, `{usage, quota, persisted}`, a JPEG `Blob` or `null`, the import caps. |

Failures reject with an `Error` whose `name` is `LuantiWorldError` and whose
`code` is one of `name`, `exists`, `missing`, `invalid`, `unsafe-path`,
`too-large`, `missing-game`, `quota`, `invalid-url`, `download`, `storage`.
The `message` is written for players.

Each completed change is announced with the existing `luanti:persistence`
window event: `event.detail` is the usual persistence state plus
`library: {operation, world, from?}`, where `operation` is `create`,
`rename`, `duplicate`, `delete`, `import`, `export` or `thumbnail`.
- Touch-only devices receive a warning. Browser touch controls remain roadmap
  work; use a keyboard and mouse for this MVP.

See [wasm.md](wasm.md) for building, serving, cache versioning, and deployment
headers.
