# Week 1 engine test: results

**Gate:** under 5 seconds from opening the link to the title screen on a mid-range Android phone over 4G.

**Result so far: the stock Godot 4.4 web export fails the gate on 4G.** The game itself is tiny. The engine download is not.

## What gets downloaded

| File | Raw | Brotli (what Caddy serves) |
| --- | --- | --- |
| `index.wasm` (Godot engine, stock template) | 43.7 MB | **6.41 MB** |
| `index.pck` (all game code + fighter data) | 0.10 MB | 0.09 MB |
| `index.js` (loader) | 0.32 MB | 0.07 MB |
| **Total** | | **6.59 MB** |

## Time to title screen

These figures are emulated in desktop Chromium (Playwright, Chrome DevTools network and CPU throttling, cold cache), not measured on a real phone. Reproduce with `tests/web/load_test.js`.

| Profile | Time to title |
| --- | --- |
| Desktop, no throttling | 1.3 s |
| 4G typical (10 Mbps, 70 ms RTT) + CPU 4x slower | **9.6 s** |
| 4G weak (4 Mbps, 100 ms RTT) + CPU 4x slower | **17.1 s** |

Nearly all of that time is downloading and compiling the 6.4 MB engine.

## Ways to hit 5 seconds (still Godot)

1. **Custom slim web template:** compile Godot with 3D, physics, navigation and unused modules disabled (`disable_3d=yes`, `optimize=size`, custom build profile). Godot's documentation reports this kind of build at roughly half the stock size, so about 3 MB brotli, which is about 3–4 s on typical 4G. This takes about an hour of setup in CI, then it's automatic. It is the recommended next step.
2. **Instant HTML title:** show a lightweight HTML/CSS title screen ("Press to play") immediately, while the engine downloads in the background. The player sees the title in well under a second, and by the time they pick a mode the engine is ready. This doesn't make the download smaller, but it is what the player actually feels.
3. **Return visits:** with the installable app (service worker cache, Beta milestone), the second visit loads from disk in about 1 s.

The best answer is probably 1 + 2 together. If the slim template still can't get under 5 s on typical 4G, that's the case for the plain JavaScript + WebGL alternative (about 0.2 MB). That would mean rewriting the engine code that exists now (the `engine/` folder is about 1,300 lines of GDScript).

## Other numbers

- **Sim cost:** about 20 µs per tick headless (budget for rollback: under 1 ms, so replaying 8 frames costs under 0.2 ms).
- **Fps in this test:** 18 fps. The container has no GPU, so Chromium used software WebGL (SwiftShader). This number is **not** a phone measurement. The game speed stays correct anyway, because the sim runs a fixed 60 ticks/s and catches up independently of the frame rate. The 60fps gate needs a real mid-range Android phone.
- **Memory:** not measured yet. Godot release builds don't report it, so it needs Chrome DevTools on the phone.

## Still to do for this gate

- [ ] Build the slim template and re-measure.
- [ ] Try the HTML instant title.
- [ ] Measure on a real mid-range Android phone (load time, fps, memory).
