# [Content] Showcase pack for the web demo

**Labels:** `content`, `wasm`, `browser-mvp`, `P1`

**Epic:** #20 — covers #21, #24, #22, #27 and #28.

## Current Situation

Before this pack, the browser client booted `games/devtest`: a plain green tile
and a museum of drawtypes. That is exactly right for engine bring-up and exactly
wrong as the first thing a visitor sees in a shareable link.

`games/luanti_web` is now the default game in the launcher, in `shell.html` and
in the first-playable gate. `devtest` stays in the tree, stays preloaded, and is
still one entry down the dropdown — engine work should keep using it.

## What shipped

### #21 — slim `luanti_web` game

Not a copy of devtest's 34 QA mods. Four mods, written for the demo:

| Mod | What it owns |
|-----|--------------|
| `lw_nodes` | the 45-node palette and the mapgen aliases |
| `lw_core` | the hand, privileges, the palette inventory, the starter kit |
| `lw_theater` | screen nodes, seats, marquee, the remote, both theater tiers |
| `lw_world` | the authored world, stamped onto a singlenode mapgen |

`games/luanti_web/minetest.conf` sets the game-level defaults: `creative_mode`,
no damage, no PvP, `default_privs` with fly/fast/noclip/give/settime, and
`time_speed = 0` so the galleries look the same on every visit.

Devtest's `chest_of_everything` has no counterpart. `lw_core` replaces the
player's inventory formspec with a paged palette backed by a per-player detached
inventory, so pressing `i` is how a visitor gets blocks. Taking from it never
empties it.

### #24 — node palette

45 nodes, all carrying the `lw_palette` group:

* **Terrain** — stone, dirt, dirt with grass, sand, paving, animated water.
* **Structure** — stone brick, polished stone, planks, timber beam, glass, iron
  bars, gold trim.
* **Architecture** — stairs and slabs for two materials, column, fence, velvet
  curtain, carpet.
* **Lighting** — ceiling lamp, floor uplight, and an airlike hidden light for
  lighting a gallery without a visible fixture.
* **Exhibition** — pedestal, empty frame, poster, rope stanchion, animated LED
  ticker panel, campfire.
* **16 dyed cubes** — one greyscale weave tinted with `[multiply`, so the whole
  set costs a single 16x16 texture rather than sixteen.

No connected textures, no mesh nodes, no crafting recipes. Tiles are 16x16
(the poster is 32x32) and the animated ones are vertical filmstrips, which is
what WebGL handles without complaint.

### #22 — the showcase world

Authored, but **not** a committed map database. `lw_world/init.lua` holds a list
of axis-aligned box operations and stamps them into each chunk as it is
generated on a singlenode mapgen. The layout file is the source of truth: an
edit changes the landing world on the next fresh world, with no blob to
regenerate and commit, and no infinite mapgen as the landing experience.

```
             [ theater ]                 z = 34..62
                  |
 [ library ]--[ courtyard ]--[ gallery ]   z = 4..32
                  |
             [ plaza ]                    z = -18..4   (spawn at 0, 10, -14)
```

Everything is inside x = -36..36, z = -22..66, y = 0..30, walled by a moat, so
the loaded mapblock count stays bounded however far a visitor flies.

Two details worth knowing when editing it:

* `walls()` draws the four sides of a *room*. For a rectangle inside one wall
  plane use `outline_z()` — `walls()` with `z0 == z1` collapses into a filled
  slab and will quietly cover whatever it was supposed to frame.
* Luanti is left-handed with +x east and +z north, so text on a wall only reads
  correctly for a viewer on one particular side. `write_text()` takes the axis
  *and* a direction for that reason.

The material library is built from the `lw_palette` group rather than a
hardcoded list, so a new palette node gets a labelled pedestal for free.

### #27 — theater Tier A

The screen is a wall of 6x4 nodes. Each node owns one 32x32 cell of the picture
and animates through that cell's own filmstrip, so the wall shows one large
moving image instead of 24 copies of a thumbnail. That costs one node type per
cell per reel (49 registrations, generated in a loop) and buys a cinema screen
that works on a native build with no JavaScript anywhere.

Two reels ship: a broadcast test pattern with a sweeping bar, and a sunrise loop
with parallax hills and a cart. The remote (left click) cycles
`off -> bars -> show -> off` and moves `timeofday` with it, so the house lights
come up when the screen goes dark. Switching a reel is 24 `swap_node` calls, not
an ABM.

### #28 — theater Tier B

The signature web-port feature: desktop Luanti cannot play an MP4 on a node, but
the WASM client's page owns a real `<video>`.

* `core.set_web_video{clip, title, loop, muted}` and `core.clear_web_video()`
  are registered in `ModApiUtil::Initialize` **only** under `__EMSCRIPTEN__`, so
  a mod feature-detects with `if core.set_web_video then`.
* `porting::emscripten_show_video_overlay()` validates the clip name and calls
  `Module.luantiTheater.show()` through `MAIN_THREAD_EM_ASM_INT`, the same
  proxying the persistence and status bridges already use.
* `client/web/theater.js` owns the element: it releases pointer lock so its own
  controls are clickable, starts muted with an Unmute button (autoplay policy),
  and re-acquires pointer lock on close.

Clip names are restricted to `[A-Za-z0-9][A-Za-z0-9._-]*`, no `..`, no slashes,
128 characters or fewer — checked in C++ *and* again in JS. The launcher
resolves the name inside its own `media/` directory, so a mod cannot aim the
overlay at another origin. Clips are fetched at runtime and are deliberately not
in `luanti.data`.

Every failure path degrades to Tier A: no API (native build or a remote server),
no overlay (an embedder replaced the shell), no clip on disk, or a codec the
browser refuses. `show()` returning false is a normal outcome, not an error.

## Verification

* `util/content/generate_luanti_web_textures.py` is deterministic: rerunning it
  on an unchanged tree produces an empty diff. 90 files, ~67 KiB total.
* The world builder was run headless against a stubbed `core` and the resulting
  voxels rendered as a plan and as cross-sections, which is how the seating rake
  (running the wrong way), the aisle (a stack of carpets) and the gallery
  artworks (taller than the room) were caught before any build.
* `src/script/lua_api/l_util.cpp` and `src/porting_emscripten.cpp` compile clean
  both with and without `__EMSCRIPTEN__`.
* `util/wasm/test_first_playable.py` now takes `--game` and defaults to
  `luanti_web`; `--game devtest` runs the same gate against the bare sandbox,
  which is the comparison to reach for when a failure might be content-specific.

Not verified here: no Emscripten toolchain is available in this environment, so
the pack has not been run in a browser. The gate in
`docs/wasm-issues/06-first-playable-gate-results.md` is the place to record that
run.

## Budget

`games/luanti_web` is 476 KB on disk against devtest's 3.8 MB; the generated art
is under 80 KB of it. The rest of the content budget — what to bundle and what
not to — is in `wasm_porting.md` under "Content Budget".

## Not covered

From the epic, still open: #26 (only the screen remote exists of the tool
set), #29 (Tier C), #30 (the policy is written into `wasm_porting.md`, but the
PR checklist item is not), #31 (themed maps). #23 (schematic pipeline) and
#25 (kinetic courtyard: animated tiles, entities, node timers, living-building
loop, and filmstrip authoring docs) shipped after the original pack.
