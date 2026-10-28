# Online prototype (weeks 5–6): results

**Gate:** playable at 150 ms ping between Saint Paul and Dhaka, with no visible stutter.

**Status:** passes in automated browser tests at about 165 ms ping. In 60 seconds of play there were 0 desyncs, about 1 one-frame stall every 12 seconds per player, and rollbacks averaged under 3 frames. The real Saint Paul ↔ Dhaka test with two people hasn't been done yet. Only that test can judge "no visible stutter".

## How it works

```
 Browser A ── WebSocket ──┐                 ┌── WebSocket ── Browser B
   (Godot)                ▼                 ▼                 (Godot)
                     signaling server (FastAPI)
                     room codes · quick match · TURN credentials
   │                                                              │
   └──────────── WebRTC data channels (peer to peer) ─────────────┘
                 "inputs": unreliable, unordered (rollback packets)
                 "control": reliable (ready / start / rematch)
            coturn relays this traffic when a direct path fails
```

- **Matching:** `server/app.py` pairs players by quick match or a 4-letter room code (no I or O). It relays the WebRTC setup messages and hands out short-lived TURN credentials. It never sees a fight.
- **Connection:** `client/net/online.gd` handles the server connection, the WebRTC connection and its two channels. It pings 5 times before the fight; then both players send "ready" with their fighter, and the host sends "start" with the input delay.
- **Rollback:** `client/net/rollback.gd` is the rollback session.
  - Local input is delayed 1–5 frames, picked from the ping (3 frames at 150 ms).
  - The opponent's input is predicted. A wrong prediction restores the saved state and re-simulates, up to 10 frames back.
  - Each packet carries every unacknowledged input, so lost packets don't matter.
  - The player who is ahead skips an occasional tick so both stay level.
  - Every 30 confirmed frames both sides compare a state checksum, so a desync is caught right away.
- **Fight screen (`client/ui/fight_screen.gd`):** runs the fight through the session. Effects replayed by a rollback show only once. Pausing doesn't freeze an online fight, ping is shown under the timer, and F9 shows rollback stats.
- **Menus:** Online → pick a fighter → Quick match / Create room / Join room. After a match: Rematch, Change fighter, New opponent (all three asked for in the design doc), or Main menu.

## Test results

### Simulated network (`tests/sim/test_rollback.gd`, 2 sessions, 60 ticks/s exact)

| Conditions | Desyncs | Stalls | Avg / max rollback |
| --- | --- | --- | --- |
| LAN | 0 | 0 | 1.1 / 2 |
| 150 ms ±15 ms jitter, 1% loss, 60 s | 0 | 0 | 2.4 / 5 |
| 100 ms ±20 ms, 20% loss | 0 | 0 | 3.0 / 9 |
| 400 ms ±30 ms, 2% loss | 0 | 7 | 7.3 / 10 |

### Real browsers (`tests/web/online_test.js`)

Two headless Chromium browsers play each other with real WebRTC through the real server. Both mash random inputs for 60 s. Each side adds lag to its outgoing input packets (`?lag=50`) and drops 1% of them.

| Measured ping | Input delay | Desyncs | Stalls (per player, 60 s) | Avg / max rollback |
| --- | --- | --- | --- | --- |
| 163–171 ms | 4 | 0 (121 checked frames) | 4–5 | 2.6–2.9 / 10 |
| 232–238 ms | 4 | 0 | 6–9 | 3.2–3.3 / 10 |

Caveats:
- This container has no GPU. Each browser renders in software at about 46–58 fps, and network packets are only read once per rendered frame. That adds about 40 ms of ping on its own, plus jitter. Real phones and PCs at 60 fps add about 16 ms.
- A stall is a one-frame hitch: the game waits because it is more than 10 frames ahead of the opponent's last input. In this container about 1 in 700 frames stalled.

## Bugs found along the way

- **Title on phones:** the instant title's "pressed" check compared a number with true/false, so it was always false. Keyboard presses still worked because Godot sees them directly, but a tap on a phone would have left you stuck on the title. Fixed.
- **Rollback replays:** an event replayed after a rollback read the fighter's current move instead of the move named in the event. Fixed.

## Not done yet

- [ ] **Real two-person test:** Saint Paul ↔ Dhaka, which needs the stack deployed (see `infra/README.md`).
- [ ] **TURN relay** is configured but not yet exercised (it needs a public server).
- [x] **Desktop online:** the official WebRTC plugin (webrtc-native 1.2.2, desktop libraries only, 26 MB) is in `client/addons/webrtc_native`. In tests, desktop vs desktop and desktop vs browser both played with 0 desyncs.
- [ ] **Touch controls** are planned for the Beta milestone.
- [ ] **Ranked ladder / Postgres** isn't part of this milestone.
- [ ] **Possible tuning after real-device tests:**
  - adapt the input delay during a match;
  - make stalls smoother by slowing down slightly instead of skipping a frame.
