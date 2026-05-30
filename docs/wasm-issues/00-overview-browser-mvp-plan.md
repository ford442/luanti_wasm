# [WASM] Browser Client MVP Roadmap & Issue Overview

**Labels:** `wasm`, `meta`, `roadmap`

**Milestone:** Browser Client MVP (v0.1)

## Vision

A practical, high-quality Luanti client that runs in any modern browser tab:

- Zero install
- Good singleplayer persistence (worlds survive reloads)
- Real multiplayer via easy proxy (join public servers with friends)
- Responsive, non-freezing experience (feels like a web game, not a ported binary)
- Easy to embed and share ("here, play this world")
- Maintainable on top of upstream Luanti (minimal divergence)

We are **not** trying to replace the native client for hardcore players. We are trying to remove friction for casuals, educators, quick testing, content creators, and new players.

## The Three P0 Technical Pillars (Must Land for MVP)

1. **Persistence** — `01-persistence-mvp.md`  
   World saves, player data, and settings must reliably survive reload and tab close. (paradust7's #1 open wound after years.)

2. **Networking / Proxy Transport** — `02-websocket-proxy-networking.md`  
   Adapt the proven emsocket + encapsulation design so the client can join real servers (and eventually host).

3. **Non-Blocking Execution** — `03-async-main-loop.md`  
   The tab must stay responsive. No frozen UI, working pointerlock, no "page unresponsive" dialogs.

## Supporting Work (P1 for a *shippable* MVP)

- `04-modern-launcher-embedding.md` — The web UX layer (launcher, deep links, share buttons, basic PWA).
- `05-build-ci-demo.md` — Reproducible builds + public demo that outsiders can actually try.

## Later / Nice-to-Have (P2+)

- Runtime content pack loading (tar.zst via libarchive) for dynamic mods/games.
- In-browser server hosting (cool but lower priority than client-to-server).
- Mobile touch controls (big effort; Android port already exists for a reason).
- WebGPU path, WebTransport, better offline, mod browser integration, etc.
- Memory / perf tuning for lower-end devices.

## Key Decisions Already Made (from investigation)

- **Do not fork paradust7/minetest** (old 5.14-era base, high divergence risk).
- **Do selectively reuse** the proven parts:
  - Proxy networking *design & protocol* (emsocket + encapsulation over WS).
  - Main loop yielding patterns (helper thread + explicit pause/rAF, or clean `emscripten_set_main_loop` + step extraction).
  - WASMFS patches and pack loader ideas (if they solve real problems we hit).
- **Stay on clean upstream Luanti + minimal guarded platform layer** (`#ifdef __EMSCRIPTEN__` in porting, network, main loop, etc.).
- **Persistence is our #1 advantage** to get right (we already have IDBFS scaffolding; paradust never fully solved it).

## How to Use These Issues

Each issue file in this directory is a self-contained, postable GitHub issue with:
- Clear description + "why now"
- Definition of Done
- Technical notes & references to paradust work + our `wasm_porting.md`
- Suggested labels and milestone

**Suggested order of attack (for a small focused team or sequential agent work):**

1. Persistence MVP (unblocks real play)
2. Async main loop (unblocks real UX)
3. Proxy networking (unlocks the "play with others" story)
4. Build/CI + public demo (makes the above visible and testable by humans)
5. Launcher + embedding polish (turns the tech into something people love and share)

Parallel work is possible (e.g. launcher + proxy can advance while persistence lands).

## Success Criteria for "MVP"

A person who has never heard of Luanti can:
- Click a link
- Land in a playable singleplayer world within ~30s (first visit) or ~5s (repeat)
- Save, reload the tab the next day, and their world is still there
- Join a public multiplayer server and see other players with "acceptable for browser" latency
- Share a link with a friend who can join the same world without installing anything

If we hit that bar with a maintainable codebase, we have a winner.

---

**References (read these first when starting work):**
- This repo's `wasm_porting.md` (the master technical plan)
- `docs/wasm-investigation-paradust.md` (detailed analysis of prior art + reuse recommendations)
- The individual issue files in this directory

Let's build the thing. Questions or scope changes → discuss in the milestone or on the relevant issue.