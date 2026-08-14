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
| `autostart=1` | Start after assets and storage are ready if all fields validate. |

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
proxy rather than failing later in the engine.

## Browser behavior

- Clicking the game lets SDL request pointer lock. Escape releases pointer
  lock or fullscreen; the resume overlay returns focus to the canvas.
- The service worker precaches the coherent HTML, JavaScript, Wasm, data pack,
  and launcher assets. Offline use is available after installation completes;
  multiplayer and the live public server list still require a network.
- Worlds and settings remain origin-scoped in IndexedDB. Embedding the same
  deployment URL preserves that storage; moving to another origin does not.
- Touch-only devices receive a warning. Browser touch controls remain roadmap
  work; use a keyboard and mouse for this MVP.

See [wasm.md](wasm.md) for building, serving, cache versioning, and deployment
headers.
