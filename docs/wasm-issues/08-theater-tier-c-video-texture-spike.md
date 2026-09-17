# [Engine] Theater Tier C — video-frame-to-texture spike

**Tracks:** #29 · **Parent:** #20 (closed) · **Gate:** #12 (closed, shaders
stable), Tier B playable (#28, shipped in #37) — both prerequisites #29 named
are now met.

This is the spike issue #29 asked for: one quad, browser-decoded frames,
uploaded onto a named engine texture, no audio, WASM-only. It is **not**
wired into any showcase content and does not replace Tier A/B for the public
demo (see issue #29's non-goals).

## What shipped

- `core.set_web_video_texture{clip, texture, width, height, fps}` /
  `core.clear_web_video_texture()` — new WASM-only Lua API in
  `src/script/lua_api/l_util.cpp`, registered the same way as Tier B's
  `set_web_video`/`clear_web_video` (undefined outside Emscripten, so a mod
  feature-detects it).
- `porting::emscripten_start_video_texture()` / `emscripten_stop_video_texture()`
  / `emscripten_poll_video_texture_frame()` in `src/porting_emscripten.h/.cpp`
  — the thin Emscripten hook. Frames cross from the browser main thread (which
  owns the `<video>`/`<canvas>` decode) to the application worker (the only
  thread allowed to touch `ITextureSource`) through a double-buffered static
  array in shared Wasm memory plus an atomic generation counter, the same
  cross-thread pattern the persistence sync callbacks already use.
- `client/web/videotexture.js` — decodes the clip into an offscreen
  `<video>` + `<canvas>`, using `requestVideoFrameCallback` where available
  and an fps-throttled `requestAnimationFrame` fallback otherwise. Swaps
  R/B on the way into the Wasm heap (canvas `ImageData` is RGBA;
  `ECF_A8R8G8B8` is BGRA in memory, see `irr/include/SColor.h`).
- `Client::serviceVideoTextureSpike()` in `src/client/client.cpp`, called once
  per frame from `Client::step()`: polls for a new frame and, if one is
  waiting, builds a `video::IImage` and calls
  `m_tsrc->insertSourceImage(texture_name, image)`.

## "IrrlichtMt or a thin Emscripten hook?" — thin hook, no IrrlichtMt changes

`TextureSource::insertSourceImage()` (`src/client/texturesource.cpp`) already
does exactly what the issue's sketch asked for: when a texture of the same
size and format already exists under that name, `rebuildTexture()` takes the
`lock(ETLM_WRITE_ONLY)` / `memcpy` / `unlock()` / `regenerateMipMapLevels()`
path in place — that unlock is IrrlichtMt's own `glTexSubImage2D` upload for
the GLES2/WebGL driver. This is the same mechanism the minimap and dynamic
media images already rely on. No IrrlichtMt source under `irr/` was touched;
everything new lives in WASM-only code paths (`#ifdef __EMSCRIPTEN__`) plus
one small, always-compiled hook call in `Client::step()`.

## Spike limits (matching the issue's ask)

- `VIDEO_TEXTURE_SPIKE_MAX_WIDTH` / `_HEIGHT` = 320×180, `_MAX_FPS` = 24
  (`src/porting_emscripten.h`). `emscripten_start_video_texture()` clamps to
  these regardless of what a mod requests.
- One active clip at a time — starting a new one implicitly reuses the same
  double buffer; there is no multi-texture fan-out.
- No audio path. The offscreen `<video>` element is always muted.
- Native builds are unaffected: every new symbol outside
  `src/client/client.cpp`'s one hook call is behind `#ifdef __EMSCRIPTEN__`,
  and the inline stubs in `porting_emscripten.h` keep the header usable
  un-guarded.

## What is NOT yet measured

Nobody has run this in a browser. Like PR #37 before it, this was built with
no Emscripten toolchain in the environment it was written in — validated with
a native Debug build (`cmake --build build`, `BUILD_CLIENT=TRUE`,
`ENABLE_SOUND=0`) to catch compile errors in the always-built code paths, but
the `__EMSCRIPTEN__` branches themselves are unexercised. Someone with
`emsdk` and a browser needs to:

1. Build `build-wasm` with this branch and confirm `videotexture.js` is copied
   next to `luanti.html` (wired into `src/CMakeLists.txt`'s
   `POST_BUILD`/`LINK_DEPENDS` the same way as `theater.js`).
2. Call `core.set_web_video_texture{clip=<a real clip>, texture=<an existing
   node tile's texture name>}` from a devtest/luanti_web mod and confirm the
   node's tile actually updates frame to frame.
3. **Measure frame-time impact on the application worker** (the issue's
   explicit ask) — record it here or in a follow-up to #29 once run.
4. Confirm the R/B swap in `videotexture.js` produced correct colors rather
   than assuming the `ECF_A8R8G8B8` byte-order note in `SColor.h` is being
   read correctly.

Until that happens this stays a spike: functionally wired end to end, not
verified in a browser, and not linked into any showcase content.
