# Luanti WebSocket UDP proxy

This directory contains the self-hostable server for Luanti WASM multiplayer.
It accepts the browser's WebSocket connection and forwards authorized datagrams
to native IPv4 Luanti servers over UDP.

## Run locally

Node.js 20 or newer is recommended.

```bash
cd util/wasm/proxy
npm install
LUANTI_PROXY_ALLOWED_TARGETS=127.0.0.1:30000 npm start
```

Enter `ws://127.0.0.1:8080` in the generated Luanti page's Proxy field. An
HTTPS-hosted client must use a TLS-terminated `wss://` endpoint. Put the Node
process behind Caddy, nginx, or another reverse proxy for TLS; ensure WebSocket
upgrade headers are forwarded.

The server binds to loopback and permits only `127.0.0.1:30000` by default.
Configuration is through environment variables:

| Variable | Default | Meaning |
|---|---:|---|
| `LUANTI_PROXY_HOST` | `127.0.0.1` | WebSocket listen address |
| `LUANTI_PROXY_PORT` | `8080` | WebSocket listen port |
| `LUANTI_PROXY_ALLOWED_TARGETS` | `127.0.0.1:30000` | Comma-separated exact IPv4 and UDP-port allowlist |
| `LUANTI_PROXY_ALLOW_PUBLIC` | `0` | Set to `1` to allow arbitrary public IPv4 targets |
| `LUANTI_PROXY_MAX_PACKETS_PER_SECOND` | `256` | Per-client outbound datagram rate |
| `LUANTI_PROXY_MAX_BYTES_PER_SECOND` | `1048576` | Per-client outbound byte rate |

Private, loopback, link-local, multicast, and reserved targets remain denied by
the public-target mode unless an exact endpoint is explicitly allowlisted.
Run a public proxy only with operating-system/network egress controls, TLS,
connection limits, monitoring, and an abuse-response process.

## Protocol

The browser begins with the UTF-8 text handshake:

```text
PROXY IPV4 UDP 1
```

The server replies `PROXY OK 1`. Subsequent binary messages carry one UDP
datagram with this network-byte-order header:

| Offset | Size | Field |
|---:|---:|---|
| 0 | 4 | Magic `0x778B4CF3` |
| 4 | 4 | Destination IPv4; source IPv4 on replies |
| 8 | 2 | Destination UDP port; source port on replies |
| 10 | 2 | Payload length |

Emscripten uses synthetic IPv4 addresses for DNS names. The browser announces
those mappings with `RESOLVE <virtual-ip> <hostname>` text messages before the
associated datagrams. `PING <id> <timestamp>` / `PONG` measures proxy-link RTT.

For compatibility with paradust's direct-client mode, the server also accepts
`PROXY IPV4 UDP <ip> <port>`, replies `PROXY OK`, and then forwards raw binary
datagrams to that one target.

The proxy sees target servers and all unencrypted Luanti UDP traffic, including
gameplay and chat. It does not provide confidentiality or server authentication.
Use a trusted operator or self-host it.
