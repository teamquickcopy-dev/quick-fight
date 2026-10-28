"""Quick Fight signaling + matchmaking server.

Pairs two players (quick match or a private 4-letter room code), relays their WebRTC
offer/answer/ICE messages, and hands out ICE servers, including short-lived TURN credentials
for the coturn relay. It never runs fights: once the peers connect, game traffic is
browser-to-browser.

One WebSocket per player at /ws. Messages are JSON objects with a "type":

  client -> server                     server -> client
  {"type": "create_room"}              {"type": "room_created", "code": "KQZT"}
  {"type": "join_room", "code": ..}    {"type": "matched", "role": "host"|"guest", "ice_servers": [...]}
  {"type": "quick_match"}              {"type": "queued"}
  {"type": "cancel"}                   {"type": "cancelled"}
  {"type": "signal", "data": {...}}    {"type": "signal", "data": {...}}   (relayed to the peer)
  {"type": "leave"}                    {"type": "peer_left"}
                                       {"type": "error", "reason": "..."}

The host creates the WebRTC offer. State is in memory (one server process); the design doc's
Redis comes in when there is more than one instance.
"""

from __future__ import annotations

import asyncio
import base64
import hashlib
import hmac
import json
import os
import secrets
import time
from dataclasses import dataclass, field

from fastapi import FastAPI, WebSocket, WebSocketDisconnect

PROTOCOL_VERSION = 1
CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ"  # no I or O: easy to read out loud
CODE_LENGTH = 4
ROOM_TTL_SECONDS = 15 * 60
MAX_MESSAGE_BYTES = 16 * 1024
TURN_CREDENTIAL_TTL = 6 * 3600


@dataclass
class Player:
    ws: WebSocket
    id: str = field(default_factory=lambda: secrets.token_hex(6))
    peer: "Player | None" = None
    room: str | None = None
    queued: bool = False

    async def send(self, msg: dict) -> None:
        try:
            await self.ws.send_text(json.dumps(msg))
        except Exception:
            pass  # the socket is closing; its own handler cleans up


class Lobby:
    """Rooms and the quick-match queue."""

    def __init__(self) -> None:
        self.rooms: dict[str, tuple[Player, float]] = {}
        self.queue: list[Player] = []
        self.lock = asyncio.Lock()

    def _new_code(self) -> str:
        while True:
            code = "".join(secrets.choice(CODE_ALPHABET) for _ in range(CODE_LENGTH))
            if code not in self.rooms:
                return code

    def _expire(self) -> None:
        now = time.monotonic()
        for code in [c for c, (_, t) in self.rooms.items() if now - t > ROOM_TTL_SECONDS]:
            self.rooms[code][0].room = None
            del self.rooms[code]

    async def create_room(self, p: Player) -> str:
        async with self.lock:
            self._expire()
            self._detach(p)
            code = self._new_code()
            self.rooms[code] = (p, time.monotonic())
            p.room = code
            return code

    async def join_room(self, p: Player, code: str) -> Player | None:
        code = code.strip().upper()
        async with self.lock:
            self._expire()
            entry = self.rooms.get(code)
            if entry is None or entry[0] is p:
                return None
            host = entry[0]
            del self.rooms[code]
            host.room = None
            self._detach(p)
            return host

    async def quick_match(self, p: Player) -> Player | None:
        async with self.lock:
            self._detach(p)
            if self.queue:
                return self.queue.pop(0)
            self.queue.append(p)
            p.queued = True
            return None

    async def cancel(self, p: Player) -> None:
        async with self.lock:
            self._detach(p)

    def _detach(self, p: Player) -> None:
        if p.queued and p in self.queue:
            self.queue.remove(p)
        p.queued = False
        if p.room and self.rooms.get(p.room, (None,))[0] is p:
            del self.rooms[p.room]
        p.room = None


def ice_servers(user_id: str) -> list[dict]:
    """STUN/TURN for the browser. TURN uses either fixed credentials (TURN_USERNAME/TURN_CREDENTIAL,
    for hosted services) or coturn's shared-secret REST credentials (TURN_SECRET, use-auth-secret):
    the username is "<expiry>:<id>", the password HMAC-SHA1(secret, username)."""
    servers: list[dict] = []
    stun = [u for u in os.environ.get("STUN_URLS", "").split(",") if u]
    if stun:
        servers.append({"urls": stun})
    turn = [u for u in os.environ.get("TURN_URLS", "").split(",") if u]
    secret = os.environ.get("TURN_SECRET", "")
    # Hosted TURN services (e.g. Metered) hand out a fixed username/password instead of a secret.
    if turn and os.environ.get("TURN_USERNAME") and os.environ.get("TURN_CREDENTIAL"):
        servers.append({"urls": turn, "username": os.environ["TURN_USERNAME"],
                        "credential": os.environ["TURN_CREDENTIAL"]})
    elif turn and secret:
        username = f"{int(time.time()) + TURN_CREDENTIAL_TTL}:{user_id}"
        digest = hmac.new(secret.encode(), username.encode(), hashlib.sha1).digest()
        servers.append({"urls": turn, "username": username, "credential": base64.b64encode(digest).decode()})
    return servers


app = FastAPI(title="Quick Fight signaling")
lobby = Lobby()


@app.get("/healthz")
async def healthz() -> dict:
    return {"ok": True, "version": PROTOCOL_VERSION, "rooms": len(lobby.rooms), "queued": len(lobby.queue)}


async def _pair(host: Player, guest: Player) -> None:
    host.peer, guest.peer = guest, host
    await host.send({"type": "matched", "role": "host", "ice_servers": ice_servers(host.id)})
    await guest.send({"type": "matched", "role": "guest", "ice_servers": ice_servers(guest.id)})


async def _unpair(p: Player, notify: bool) -> None:
    peer = p.peer
    p.peer = None
    if peer is not None:
        peer.peer = None
        if notify:
            await peer.send({"type": "peer_left"})


@app.websocket("/ws")
async def ws_endpoint(ws: WebSocket) -> None:
    await ws.accept()
    p = Player(ws)
    try:
        while True:
            raw = await ws.receive_text()
            if len(raw) > MAX_MESSAGE_BYTES:
                await p.send({"type": "error", "reason": "message_too_large"})
                continue
            try:
                msg = json.loads(raw)
                kind = msg["type"]
            except (ValueError, KeyError, TypeError):
                await p.send({"type": "error", "reason": "bad_message"})
                continue
            if kind == "create_room":
                await _unpair(p, notify=True)
                await p.send({"type": "room_created", "code": await lobby.create_room(p)})
            elif kind == "join_room":
                await _unpair(p, notify=True)
                host = await lobby.join_room(p, str(msg.get("code", "")))
                if host is None:
                    await p.send({"type": "error", "reason": "room_not_found"})
                else:
                    await _pair(host, p)
            elif kind == "quick_match":
                await _unpair(p, notify=True)
                other = await lobby.quick_match(p)
                if other is None:
                    await p.send({"type": "queued"})
                else:
                    await _pair(other, p)  # whoever waited longer hosts
            elif kind == "cancel":
                await lobby.cancel(p)
                await p.send({"type": "cancelled"})
            elif kind == "signal":
                if p.peer is not None:
                    await p.peer.send({"type": "signal", "data": msg.get("data")})
            elif kind == "leave":
                await _unpair(p, notify=True)
            else:
                await p.send({"type": "error", "reason": "unknown_type"})
    except WebSocketDisconnect:
        pass
    finally:
        await lobby.cancel(p)
        await _unpair(p, notify=True)
