# Week 1 engine test: results

**Gate:** under 5 seconds from opening the link to the title screen on a mid-range Android phone over 4G.

**Result: the title screen gate is met (0.1 s). Full playability takes 7.0 s on typical 4G.** Both numbers come from emulation, not yet a real phone.

## What changed

1. **Instant HTML title** (`client/web/shell.html`): the title screen is plain HTML/CSS with no downloads. It appears straight away and shows load progress while the engine downloads behind it. When the engine is ready it says "Press any button". That press also unlocks browser audio, and the game then skips its own title and opens the mode menu.
2. **Slim Godot web engine** (`tools/web_template_profile.py`, `tools/build_web_template.sh`): Godot 4.4.1 is compiled with 3D removed, plus physics, navigation, the advanced GUI, the large text engine (ICU/HarfBuzz) and about 40 other unused modules. It uses link-time optimization. CI builds it once and caches it.
   - It keeps GDScript, fonts, PNG/WebP/SVG images, Ogg/Vorbis + MP3 audio, and WebRTC + WebSocket for online play.
   - It uses the small fallback text engine, which covers Latin-script text only. Non-Latin text (Bengali, for example) would need the large text engine back, which adds about 1 MB.

## Download size (brotli, what Caddy serves)

| File | Stock Godot | Slim |
| --- | --- | --- |
| `index.wasm` (engine) | 6.41 MB | **3.77 MB** |
| `index.pck` (game code + data) | 0.09 MB | 0.09 MB |
| `index.js` (loader) | 0.07 MB | 0.07 MB |
| **Total** | 6.59 MB | **3.93 MB** |

## Times

These are emulated in desktop Chromium (Playwright, Chrome DevTools network and CPU throttling, cold cache). Reproduce with `tests/web/load_test.js`.

| Profile | Stock: title = playable | Slim + HTML title: title | Slim + HTML title: playable |
| --- | --- | --- | --- |
| Desktop, no throttling | 1.3 s | **0.02 s** | 1.2 s |
| 4G typical (10 Mbps, 70 ms RTT) + CPU 4x slower | 9.6 s | **0.11 s** | 7.0 s |
| 4G weak (4 Mbps, 100 ms RTT) + CPU 4x slower | 17.1 s | **0.14 s** | 11.9 s |

The player sees the title right away, and the playable time is when "Press any button" appears. On typical 4G, a player who reads the title and taps through the menus barely waits.

## Not done / still open

- [ ] **Real phone:** measure on a mid-range Android phone over real 4G (load, 60fps, memory under 400 MB). The fps in this container (about 16) is software WebGL with no GPU, so it says nothing about phones. The game speed stays correct regardless, because the sim runs a fixed 60 ticks/s.
- [ ] **Playable under 5 s on typical 4G** would need about 1.5 MB less. Options, in order of effort:
  - a feature build profile that strips unused engine classes (about 0.3–0.6 MB);
  - streaming compilation with the engine served as `application/wasm` (Caddy does this; my test server may not have);
  - a JavaScript + WebGL engine (about 0.2 MB, but a rewrite).

  Given an instant title, I don't think the rewrite is worth it.
- [ ] **Return visits:** with the installable app (service worker, Beta milestone), the engine loads from disk in about 1 s.

## Recommendation

Stay on Godot, with the slim engine and the instant title.
