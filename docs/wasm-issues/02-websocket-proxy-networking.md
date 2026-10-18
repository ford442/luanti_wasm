# [WASM] WebSocket Proxy Transport for Multiplayer

**Labels:** `wasm`, `networking`, `P0`, `browser-mvp`

**Milestone:** Browser Client MVP (v0.1)

**Status:** Transport and self-hostable proxy implemented; public-server browser
acceptance remains outstanding.

## Implemented MVP

- [x] The Emscripten `UDPSocket` implementation keeps localhost traffic in an
  in-process queue for singleplayer and sends remote IPv4 datagrams through the
  browser bridge. Native socket behavior is unchanged.
- [x] `client/web/network.js` is linked as `--pre-js`. It owns WebSocket
  negotiation, framing, DNS mappings, connection state, counters, and proxy RTT.
- [x] The generated shell accepts a proxy URL. The same value can be supplied as
  `?proxy=wss%3A%2F%2Fproxy.example.org%2F`, `Module.luantiProxyUrl`, or the
  persisted `luanti.proxyUrl` local-storage entry.
- [x] `util/wasm/proxy/` contains a small Node.js WebSocket-to-UDP server with an
  exact-target allowlist, optional public-IPv4 mode, per-client rate limits, and
  self-hosting instructions.
- [x] Focused tests cover framing, handshake validation, resolver validation,
  browser bridge behavior, and a real WebSocket-to-UDP echo round trip.
- [ ] Run the complete generated Luanti client against a deployed `wss://`
  proxy and a public Luanti server, then record latency and play acceptance.

## Architecture

Luanti's existing reliable-UDP `Connection` remains unchanged. Only the
platform implementation below it differs:

```text
Luanti Connection / UDPSocket
  |- 127.0.0.0/8 -> shared-memory datagram queue (internal server)
  `- remote IPv4 -> client/web/network.js -> WebSocket -> Node proxy -> UDP server
```

The application still runs on the Emscripten pthread. Synchronous main-thread
bridge calls create links and copy outgoing datagrams. Incoming WebSocket data
calls the one retained `EMSCRIPTEN_KEEPALIVE` receive function, which queues the
datagram and wakes the normal blocking receiver. Shared ownership prevents a
late browser callback from racing socket destruction.

Emscripten may return synthetic IPv4 values for DNS names. `Address::Resolve()`
registers the synthetic-address-to-hostname relationship with the browser. The
browser sends that relationship as a `RESOLVE` command, and the proxy serializes
control and data processing so the following packet cannot overtake DNS lookup.

IPv6 is disabled by default in browser builds. The transport rejects IPv6
rather than silently routing it incorrectly.

## Protocol Version 1

The browser opens one WebSocket for each remote Luanti UDP socket and sends:

```text
PROXY IPV4 UDP 1
```

The server responds with `PROXY OK 1`. Each later binary message contains one
datagram and a 12-byte, network-byte-order header:

| Offset | Size | Field |
|---:|---:|---|
| 0 | 4 | Magic `0x778B4CF3` |
| 4 | 4 | Destination IPv4; source IPv4 on replies |
| 8 | 2 | Destination port; source port on replies |
| 10 | 2 | Payload length |

Control messages are `RESOLVE <virtual-ip> <hostname>` and
`PING <id> <timestamp>` / `PONG <id> <timestamp>`. The versioned handshake is a
Luanti WASM extension of paradust's proven format. The server also accepts the
legacy direct handshake `PROXY IPV4 UDP <ip> <port>` with raw binary packets.
VPN/browser-hosted-server mode is not implemented.

## Browser Contract and Telemetry

Quoted properties remain safe under JavaScript optimization:

```js
Module.luantiNetwork.setProxyUrl("wss://proxy.example.org/");
Module.luantiNetwork.getState();
```

The state snapshot and `luanti:network` window-event detail are:

```js
{
  state: "disabled" | "idle" | "connecting" | "ready" | "closed" | "error",
  url: string | null,
  rttMs: number | null,
  sentPackets: number,
  receivedPackets: number,
  droppedPackets: number,
  error: string | null
}
```

`droppedPackets` counts local queue overflow and malformed/unserviceable proxy
frames. WebSocket is a reliable byte stream, so the bridge cannot directly
observe downstream UDP loss; Luanti's existing reliable-UDP statistics remain
the authority for game-protocol retransmission and loss.

## Security, Privacy, and Deployment

The proxy sees destination servers and all unencrypted Luanti traffic, including
gameplay and chat. It does not add game-server authentication or confidentiality.
Use a trusted operator or self-host it.

The server binds to loopback and permits only `127.0.0.1:30000` by default.
Public-destination mode still rejects private, loopback, link-local, multicast,
and reserved IPv4 ranges unless an exact endpoint is explicitly allowlisted.
Operators also need TLS termination, OS/network egress controls, connection
limits, monitoring, and an abuse-response process. HTTPS clients require WSS.
See `util/wasm/proxy/README.md` for commands and environment variables.

## Verification

```bash
cd util/wasm/proxy
npm install
npm test
npm audit --audit-level=high
```

The Emscripten and native platform branches can be syntax-checked independently:

```bash
c++ -std=c++17 -Isrc -Iirr/include -Ilib/sha256 \
  -fsyntax-only src/network/socket.cpp src/network/address.cpp
em++ -std=c++17 -pthread -sSHARED_MEMORY=1 \
  -Isrc -Iirr/include -Ilib/sha256 \
  -fsyntax-only src/network/socket.cpp src/network/address.cpp
```

The complete WASM target now configures, links, and passes its generated-client
Chrome startup smoke. The transport also has a real browser-to-WebSocket-to-UDP
echo smoke:

```bash
python3 util/wasm/test_network_browser.py
python3 util/wasm/test_client_browser.py --build build-wasm
```

Final demo acceptance still requires a TLS-deployed proxy and a consenting
public test server. Verify direct hostname connection, walking, chat, reconnect,
at least ten minutes of play, and compare in-game latency with the proxy RTT
shown by the shell.

## Non-Goals

- Hosting a Luanti server from the browser tab or paradust VPN mode.
- Proxy authentication, automatic failover, anycast, or a hosted public proxy.
- WebTransport or WebRTC transport.
- Removing TCP/WebSocket head-of-line blocking.

## Prior Art

The wire-header magic and legacy direct handshake are interoperable with the
MIT-licensed [paradust7/webshims](https://github.com/paradust7/webshims) design.
The server is a fresh, narrowly scoped implementation informed by the
[paradust7/minetest-wasm-sample-proxy](https://github.com/paradust7/minetest-wasm-sample-proxy),
not a copy of its full emsocket or VPN stack.
