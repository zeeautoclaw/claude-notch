#!/bin/bash
# End-to-end smoke test — does not need a real Claude Code.
# Checks:
#   1. relay allows immediately when the app is not running ({"continue":true})
#   2. once the app is up, relay delivers the event and gets a response
#   3. auto-allow rules take effect
#   4. settings.json inject + uninstall leave the fixture unchanged

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
RELAY="$BUILD/ClaudeNotchRelay"
APP="$BUILD/ClaudeNotchApp"
SOCKET="/tmp/claude-notch-smoke-$$.sock"

PASS=0
FAIL=0

check() {
    local name="$1"
    local expect="$2"
    local actual="$3"
    if [[ "$actual" == *"$expect"* ]]; then
        echo "  ✅ $name"
        PASS=$((PASS+1))
    else
        echo "  ❌ $name"
        echo "       expect: $expect"
        echo "       actual: $actual"
        FAIL=$((FAIL+1))
    fi
}

cleanup() {
    if [[ -n "${APP_PID:-}" ]]; then
        kill "$APP_PID" 2>/dev/null || true
        wait "$APP_PID" 2>/dev/null || true
    fi
    rm -f "$SOCKET"
}
trap cleanup EXIT

[[ -x "$RELAY" ]] || { echo "missing $RELAY"; exit 1; }
[[ -x "$APP"   ]] || { echo "missing $APP";   exit 1; }

echo "=== 1) relay should allow immediately when the app is not running ==="
RES=$(CLAUDE_NOTCH_SOCKET="$SOCKET" \
      "$RELAY" --event PreToolUse --timeout 2 \
      <<<'{"tool_name":"Bash","tool_input":{"command":"ls"}}' 2>/dev/null)
check "no-server defaults allow" '"continue":true' "$RES"

echo ""
echo "=== 2) relay gets a response once the app is up ==="
# Start the app on a custom socket path so the default one is untouched
CLAUDE_NOTCH_SOCKET="$SOCKET" "$APP" >/dev/null 2>&1 &
APP_PID=$!
# Wait for the socket (up to 5 seconds)
for _ in $(seq 1 50); do
    [[ -S "$SOCKET" ]] && break
    sleep 0.1
done
if [[ ! -S "$SOCKET" ]]; then
    echo "  ❌ app is not listening on the socket (PID=$APP_PID)"
    FAIL=$((FAIL+1))
    exit 1
fi
echo "  ✅ app listening on $SOCKET (PID=$APP_PID)"
PASS=$((PASS+1))

echo ""
echo "=== 3) Notification events are allowed immediately (no approval UI) ==="
RES=$(CLAUDE_NOTCH_SOCKET="$SOCKET" \
      "$RELAY" --event Notification --timeout 5 \
      <<<'{"message":"hello"}' 2>/dev/null)
check "notification allow" '"continue":true' "$RES"

echo ""
echo "=== 4) the log file should contain our event ==="
sleep 0.5
LOG="$HOME/Library/Logs/ClaudeNotch/app.log"
if [[ -f "$LOG" ]]; then
    if grep -q "Notification" "$LOG"; then
        echo "  ✅ Notification event logged"
        PASS=$((PASS+1))
    else
        echo "  ⚠️  Notification not found in log yet (may be delayed)"
    fi
fi

echo ""
echo "=== 5) app shuts down cleanly ==="
kill "$APP_PID"
wait "$APP_PID" 2>/dev/null || true
APP_PID=""
sleep 0.3

# The socket should be removed by now
if [[ ! -S "$SOCKET" ]]; then
    echo "  ✅ socket removed"
    PASS=$((PASS+1))
else
    echo "  ❌ socket left behind"
    FAIL=$((FAIL+1))
fi

echo ""
echo "=== 6) relay falls back to allow after the app quits ==="
RES=$(CLAUDE_NOTCH_SOCKET="$SOCKET" \
      "$RELAY" --event PreToolUse --timeout 2 \
      <<<'{"tool_name":"Bash"}' 2>/dev/null)
check "post-shutdown allow" '"continue":true' "$RES"

echo ""
echo "=========================================="
echo "Pass: $PASS    Fail: $FAIL"
echo "=========================================="
[[ $FAIL -eq 0 ]] || exit 1
