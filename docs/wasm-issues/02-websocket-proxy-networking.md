# [WASM] WebSocket Proxy Transport for Multiplayer (Adapt paradust emsocket Design)

**Labels:** `wasm`, `networking`, `P0`, `browser-mvp`

**Milestone:** Browser Client MVP (v0.1)

## Context

Browsers cannot create raw UDP (or TCP) sockets. Our current `src/network/socket.cpp` under `__EMSCRIPTEN__` is a complete no-op stub. This means:

- Only the internal singleplayer server works (client + server in same WASM instance talking to itself via the stub).
- No joining real Luanti/Luanti servers on the internet.
- No "play with friends" story.

paradust7/minetest-wasm solved exactly this problem with a production-used system:
- Custom **emsocket** (userspace BSD sockets shim in C++).
- **proxy.js** (Web Worker) that speaks a simple text-then-binary protocol over WebSocket to regional proxies.
- Encapsulation format for UDP packets (12-byte header with magic, IP, port, length) so one WebSocket can carry traffic for many "virtual" UDP peers.
- "VPN" mode for when the client itself is acting as a server.
- Working regional proxies (`*.dustlabs.io/mtproxy`) and a sample self-hostable Node.js proxy.

This design is the only publicly proven way to get real multiplayer working in a browser today. WebTransport may reduce the need for a proxy in the future, but it is not universal enough yet.

## Goals (MVP)

- [ ] A clean, maintainable `WebSocketProxySocket` (or thin adapter over the existing `UDPSocket` interface) that implements the client side of paradust's encapsulation protocol.
- [ ] The C++ side lives in `src/network/` (or a new `src/network/wasm/`), heavily guarded, minimal diff to upstream socket/address code.
- [ ] A small, well-documented, self-hostable proxy server (start with a cleaned/adapted version of paradust's sample-proxy or a fresh implementation in Node/Go/Rust — whatever the team prefers). Must support:
  - Client → real server (UDP) forwarding.
  - (Stretch for MVP) In-browser hosted server mode.
- [ ] Configuration in the web launcher (or URL param / settings) for proxy URL (default to a community one we run, with easy override for self-hosters).
- [ ] End-to-end: From the WASM client, join a public Luanti server (e.g. via server list or direct address) and play with acceptable latency/jitter.
- [ ] Basic telemetry / console logging of proxy connection state, RTT, packet loss.
- [ ] Documentation + run instructions for the proxy.

## Non-Goals for This Milestone

- Full "host a server from the browser tab" UI and reliability (valuable later for LAN-party / creative sharing scenarios).
- Encryption / auth on the WS control channel (add later; current paradust design is cleartext after the initial WS upgrade).
- Automatic proxy failover or anycast DNS.
- WebTransport native path (future optimization).

## Technical Approach Recommendations

1. **Do not copy the entire emsocket/ directory verbatim** — it is a full reimplementation of sockets (hundreds of LOC, mutexes, wait lists, etc.). Instead:
   - Keep the *protocol* (encapsulation, handshake messages like `PROXY IPV4 UDP ...`, `VPN ... BIND`).
   - Implement a much thinner shim that only needs to satisfy what Luanti's `Connection` / `UDPSocket` actually calls for a *client*.
   - Or, if the full VirtualSocket model proves clean, adopt a modernized version behind a narrow interface.

2. Study these files from paradust (they are high quality for what they do):
   - `webshims/src/emsocket/proxy.js`
   - `webshims/src/emsocket/{ProxyLink.cpp, VirtualSocket.cpp, emsocket.cpp}`
   - `minetest-wasm-sample-proxy/{UDPProxy.js, vpn.js, main.js}`

3. The JS side should live in the web launcher / a separate `static/` or `client/web/` tree (not inside the C++ wasm).

4. Expose minimal `cwrap` / `EMSCRIPTEN_KEEPALIVE` functions only for what the proxy needs (set proxy URL, maybe VPN code later).

5. Add the proxy URL to the Emscripten `Module` or as a query param so the launcher can configure it before `main()`.

## Risks & Mitigations

- **Latency/jitter**: The proxy adds a hop. Mitigate with regional proxies + good geographic defaults in the launcher. Measure and document.
- **Proxy operator burden / privacy**: Anyone running the proxy sees all game traffic (positions, chat, etc.). Document this clearly. Offer easy self-host instructions.
- **Protocol stability**: Pin a versioned protocol or make the handshake discoverable.
- **Testing**: Need at least one always-on public proxy for the demo + CI smoke test (or mock in tests).

## Suggested Labels & Tracking

`wasm` `networking` `proxy` `P0`

## Dependencies

- None hard (can be developed in parallel with main-loop work).
- Will make the launcher feel complete once persistence also lands.

## Definition of Done (Demo-Ready)

A stranger can:
1. Open our hosted WASM client.
2. Pick a region / enter a public server address.
3. Join and walk around / chat with other players on a real Luanti server with "good enough" feel for a browser game.

---

**Prior art:** paradust7/minetest-wasm (the only working public implementation), our current no-op `src/network/socket.cpp:15` under EMSCRIPTEN, `wasm_porting.md` "Networking Deep Dive" and "Option B: WebRTC DataChannels" / "WebSocket Proxy" sections.

This is the feature that turns the port from "interesting tech demo" into "I can actually play with my friends right now."