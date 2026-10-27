#!/usr/bin/env bash
# Runs the sim test suite headless. Usage: tests/run.sh [name-filter]
set -euo pipefail
cd "$(dirname "$0")/../client"
GODOT="${GODOT:-godot}"
# First run (or CI) needs the project imported so preloads resolve.
[ -d .godot ] || timeout 300 "$GODOT" --headless --editor --quit >/dev/null 2>&1 || true
OUT="$(mktemp)"
set +e
TEST_FILTER="${1:-}" timeout "${TEST_TIMEOUT:-600}" "$GODOT" --headless --path . -s ../tests/sim/run_tests.gd >"$OUT" 2>&1
CODE=$?
set -e
grep -v -e '^Godot Engine' -e '^$' "$OUT"
# GDScript runtime errors don't stop a test function, so treat any of them as a failure.
if grep -q -e 'SCRIPT ERROR' -e '^ERROR' "$OUT"; then
  echo "FAILED: script errors during the run (see above)"
  CODE=1
fi
rm -f "$OUT"
exit "$CODE"
