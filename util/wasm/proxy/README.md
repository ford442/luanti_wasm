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
| `LUANTI_PROXY_ALLOWED_ORIGINS` | unset | Comma-separated page origins allowed to connect, e.g. `https://play.example.org,https://*.pages.dev`. **Required** when listening on a non-loopback address (use `*` to allow every origin, which makes the proxy a relay for any website). Unset on loopback means any origin, for local development. Connections with no `Origin` header are refused whenever a list is set |
| `LUANTI_PROXY_ALLOWED_TARGETS` | `127.0.0.1:30000` | Comma-separated exact IPv4 and UDP-port allowlist; always allowed, even if private |
| `LUANTI_PROXY_ALLOW_PUBLIC` | `0` | Set to `1` to also allow public IPv4 targets (see the next two rows) |
| `LUANTI_PROXY_ALLOWED_PORTS` | `30000-30010` | UDP ports a public target may use. Without this a public proxy is a general UDP reflector |
| `LUANTI_PROXY_SERVER_LIST_URL` | unset | A Luanti server list (e.g. `https://servers.luanti.org/list.json`). When set, public targets must be listed there (any port they registered) and the port range is not used. Hostnames are resolved on each refresh. Public targets are refused until the first successful load; a failed refresh keeps the last good list |
| `LUANTI_PROXY_SERVER_LIST_REFRESH_SECONDS` | `600` | Server list refresh interval |
| `LUANTI_PROXY_MAX_CONNECTIONS` | `256` | Concurrent WebSockets, all addresses (503 beyond it) |
| `LUANTI_PROXY_MAX_CONNECTIONS_PER_IP` | `8` | Concurrent WebSockets per source address (429 beyond it) |
| `LUANTI_PROXY_MAX_PACKETS_PER_SECOND` | `256` | Outbound datagram rate, **shared by all connections from one address** |
| `LUANTI_PROXY_MAX_BYTES_PER_SECOND` | `1048576` | Outbound byte rate, shared the same way |
| `LUANTI_PROXY_IDLE_TIMEOUT_SECONDS` | `120` | A session with no datagram in either direction for this long is closed. A connection that never completes the handshake is closed after `LUANTI_PROXY_HANDSHAKE_TIMEOUT_SECONDS` (10) |
| `LUANTI_PROXY_MAX_TARGETS_PER_SESSION` | `64` | Remembered reply sources per session (oldest forgotten first) |
| `LUANTI_PROXY_MAX_MAPPINGS_PER_SESSION` | `256` | `RESOLVE` mappings per session |
| `LUANTI_PROXY_TRUST_PROXY` | `0` | Set to `1` behind a reverse proxy that overwrites `X-Forwarded-For` (Caddy does): the last entry becomes the client address for the caps and the rate limit. Without it every client behind Caddy would share Caddy's address |
| `LUANTI_PROXY_METRICS_TOKEN` | unset | Bearer token for `/metrics`. Unset: only a direct loopback request (not via a reverse proxy) is served |

Private, loopback, link-local, multicast, and reserved targets remain denied by
the public-target mode unless an exact endpoint is explicitly allowlisted.

## Operating it

* **Logs:** one JSON object per line on stdout (`listening`, `session_opened`,
  `session_closed` with a `reason`, `connection_rejected`, `registry_*`). They
  include client addresses, because an abuse response needs them, and never
  datagram contents.
* **`GET /healthz`:** `{"status":"ok","connections":N}`, for load balancers and
  the container health check.
* **`GET /metrics`:** Prometheus text: `luanti_proxy_connections_total`,
  `..._connections_active`, `..._connections_rejected_total{reason}`,
  `..._sessions_closed_total{reason}`, `..._datagrams_forwarded_total`,
  `..._bytes_forwarded_total`, `..._datagrams_received_total`,
  `..._bytes_received_total`, `..._rate_limited_total`,
  `..._targets_denied_total`, `..._registry_targets`.
* **Docker + TLS:** `Dockerfile` builds the proxy; `deploy/docker-compose.yml`
  runs it behind Caddy, which gets the certificate, upgrades WebSockets and
  hides `/metrics`. Copy `deploy/.env.example` to `deploy/.env`, edit it, then
  `docker compose up -d --build` and enter `wss://<PROXY_DOMAIN>/` in the
  client. (The compose file has not been run in CI; the proxy itself is covered
  by `npm test`.)
* **Still needed on a public host:** operating-system egress controls, an
  abuse-response process, and a decision on whether to publish the proxy
  address at all. The proxy sees all unencrypted Luanti traffic.

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
