"""Server tests: python -m pytest server"""

import base64
import hashlib
import hmac

import pytest
from fastapi.testclient import TestClient

import app as server


@pytest.fixture()
def client():
    server.lobby = server.Lobby()
    return TestClient(server.app)


def test_healthz(client):
    r = client.get("/healthz")
    assert r.status_code == 200 and r.json()["ok"]


def test_room_code_pairs_two_players_and_relays_signals(client):
    with client.websocket_connect("/ws") as host, client.websocket_connect("/ws") as guest:
        host.send_json({"type": "create_room"})
        created = host.receive_json()
        assert created["type"] == "room_created"
        code = created["code"]
        assert len(code) == 4 and "I" not in code and "O" not in code

        guest.send_json({"type": "join_room", "code": code.lower()})  # case doesn't matter
        assert host.receive_json()["role"] == "host"
        assert guest.receive_json()["role"] == "guest"

        host.send_json({"type": "signal", "data": {"sdp": "offer"}})
        assert guest.receive_json() == {"type": "signal", "data": {"sdp": "offer"}}
        guest.send_json({"type": "signal", "data": {"sdp": "answer"}})
        assert host.receive_json() == {"type": "signal", "data": {"sdp": "answer"}}


def test_room_codes_are_single_use(client):
    with client.websocket_connect("/ws") as host, client.websocket_connect("/ws") as a, \
            client.websocket_connect("/ws") as b:
        host.send_json({"type": "create_room"})
        code = host.receive_json()["code"]
        a.send_json({"type": "join_room", "code": code})
        assert a.receive_json()["type"] == "matched"
        b.send_json({"type": "join_room", "code": code})
        assert b.receive_json() == {"type": "error", "reason": "room_not_found"}


def test_unknown_room(client):
    with client.websocket_connect("/ws") as p:
        p.send_json({"type": "join_room", "code": "ZZZZ"})
        assert p.receive_json() == {"type": "error", "reason": "room_not_found"}


def test_quick_match_pairs_in_order(client):
    with client.websocket_connect("/ws") as a, client.websocket_connect("/ws") as b:
        a.send_json({"type": "quick_match"})
        assert a.receive_json()["type"] == "queued"
        b.send_json({"type": "quick_match"})
        assert a.receive_json()["role"] == "host"
        assert b.receive_json()["role"] == "guest"


def test_cancel_leaves_queue(client):
    with client.websocket_connect("/ws") as a:
        a.send_json({"type": "quick_match"})
        a.receive_json()
        a.send_json({"type": "cancel"})
        assert a.receive_json()["type"] == "cancelled"
    assert server.lobby.queue == []


def test_disconnect_tells_the_peer(client):
    with client.websocket_connect("/ws") as a:
        with client.websocket_connect("/ws") as b:
            a.send_json({"type": "quick_match"})
            a.receive_json()
            b.send_json({"type": "quick_match"})
            a.receive_json()
            b.receive_json()
        assert a.receive_json() == {"type": "peer_left"}


def test_disconnected_host_frees_room(client):
    with client.websocket_connect("/ws") as host:
        host.send_json({"type": "create_room"})
        code = host.receive_json()["code"]
    assert code not in server.lobby.rooms


def test_bad_messages(client):
    with client.websocket_connect("/ws") as p:
        p.send_text("not json")
        assert p.receive_json()["reason"] == "bad_message"
        p.send_json({"type": "nope"})
        assert p.receive_json()["reason"] == "unknown_type"
        p.send_text("x" * (server.MAX_MESSAGE_BYTES + 1))
        assert p.receive_json()["reason"] == "message_too_large"


def test_turn_credentials_match_coturn_scheme(monkeypatch):
    monkeypatch.setenv("STUN_URLS", "stun:turn.example.com:3478")
    monkeypatch.setenv("TURN_URLS", "turn:turn.example.com:3478?transport=udp")
    monkeypatch.setenv("TURN_SECRET", "s3cret")
    servers = server.ice_servers("abc")
    assert servers[0] == {"urls": ["stun:turn.example.com:3478"]}
    turn = servers[1]
    expiry, user = turn["username"].split(":")
    assert user == "abc" and int(expiry) > 0
    expected = base64.b64encode(hmac.new(b"s3cret", turn["username"].encode(), hashlib.sha1).digest()).decode()
    assert turn["credential"] == expected


def test_no_turn_without_secret(monkeypatch):
    monkeypatch.delenv("TURN_SECRET", raising=False)
    monkeypatch.setenv("TURN_URLS", "turn:x")
    monkeypatch.delenv("STUN_URLS", raising=False)
    assert server.ice_servers("abc") == []
