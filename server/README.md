# Signaling + matchmaking server

FastAPI + WebSockets. It pairs two players by quick match or a 4-letter room code, relays their
WebRTC setup messages, and hands out STUN/TURN servers with short-lived coturn credentials.
It never runs fights: game traffic goes browser to browser. The protocol is described at the top of `app.py`.

```sh
pip install -r requirements.txt -r requirements-dev.txt
python -m pytest            # tests
uvicorn app:app --port 8000 # run locally; the game connects to ws://127.0.0.1:8000/ws
```

| Env var | Meaning |
| --- | --- |
| `STUN_URLS` | Comma-separated STUN URLs, e.g. `stun:turn.example.com:3478` |
| `TURN_URLS` | Comma-separated TURN URLs, e.g. `turn:turn.example.com:3478?transport=udp,turn:turn.example.com:3478?transport=tcp` |
| `TURN_SECRET` | Same as coturn's `static-auth-secret` |

State lives in memory, so run a single instance. Moving rooms and the queue to Redis (from the design doc) is what allows more than one.
