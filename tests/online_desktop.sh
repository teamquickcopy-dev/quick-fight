#!/usr/bin/env bash
# Two desktop Godot processes play online against each other via the local signaling server.
# Usage: tests/online_desktop.sh [seconds]
set -uo pipefail
cd "$(dirname "$0")/.."
SECONDS_TO_PLAY="${1:-20}"
GODOT="${GODOT:-godot}"
TMP="$(mktemp -d)"
(cd server && python3 -m uvicorn app:app --host 127.0.0.1 --port 8000 --log-level warning) > "$TMP/server.log" 2>&1 &
SERVER=$!
trap 'kill $SERVER 2>/dev/null; rm -rf "$TMP"' EXIT
for i in $(seq 1 30); do curl -s -m 1 127.0.0.1:8000/healthz >/dev/null && break; sleep 0.5; done
cd client
"$GODOT" --headless --path . -s ../tests/online_desktop.gd -- host "$TMP/code" "$SECONDS_TO_PLAY" > "$TMP/host.log" 2>&1 &
HOST=$!
"$GODOT" --headless --path . -s ../tests/online_desktop.gd -- guest "$TMP/code" "$SECONDS_TO_PLAY" > "$TMP/guest.log" 2>&1 &
GUEST=$!
wait $HOST; H=$?
wait $GUEST; G=$?
for r in host guest; do echo "--- $r"; grep -v -e '^Godot Engine' -e '^$' "$TMP/$r.log" | tail -8; done
if [ $H -ne 0 ] || [ $G -ne 0 ] || grep -q 'SCRIPT ERROR' "$TMP/host.log" "$TMP/guest.log"; then
  echo "FAILED"; exit 1
fi
echo "PASSED"
