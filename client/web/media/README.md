<!--
Luanti
SPDX-License-Identifier: LGPL-2.1-or-later
Copyright (C) 2026 The Luanti Contributors
-->

# Theater clips (Tier B)

Short video clips for the showcase theater's browser overlay
(`client/web/theater.js`, issue #28). The build copies this directory next to
`luanti.html`, so a file dropped here is served from `media/<name>` on the same
origin as the page.

## Why these are not in `luanti.data`

`--preload-file` bakes its input into `luanti.data`, which every visitor
downloads before the engine starts. A 10 MB reel would add 10 MB to the time to
first frame whether or not anyone walks into the theater. Clips are fetched at
runtime instead, and the content budget in `wasm_porting.md` says to keep it
that way.

## Naming rules

The engine only passes a bare file name to the page
(`porting::emscripten_show_video_overlay`), and both the C++ and the JS reject
anything else:

* letters, digits, `.`, `_` and `-` only,
* no leading `.` or `-`, no `..`, no `/`,
* 128 characters or fewer.

That keeps the overlay inside this directory and on this origin. A mod cannot
point it at a third-party URL.

## What to put here

* 30–90 seconds, H.264 in `.mp4` or VP9/AV1 in `.webm`.
* 1280x720 or smaller — the overlay is letterboxed into the page.
* Something you have the right to redistribute. Nothing here ships by default;
  see the content policy (issue #30) before adding anything.

`games/luanti_web/mods/lw_theater/init.lua` asks for `showcase-reel.webm`. If
that file is absent the overlay says so and the animated-tile screen (Tier A)
keeps playing, so the demo is never broken by a missing clip.

An encode that works well:

```sh
ffmpeg -i source.mov -t 60 -vf "scale=1280:-2" -c:v libvpx-vp9 -crf 34 -b:v 0 \
       -c:a libopus -b:a 96k showcase-reel.webm
```

## Serving

Clips need the same COOP/COEP headers as the rest of the build
(`util/wasm/serve.py` and `client/web/.htaccess` already send them). Long
`Cache-Control` is fine: the file name is the version.
