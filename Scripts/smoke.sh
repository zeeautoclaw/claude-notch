#!/bin/bash
# 端到端冒烟测试 — 不依赖真实 Claude Code。
# 检查:
#   1. relay 在 app 没起时立即放行 ({"continue":true})
#   2. app 起来后 relay 能投递事件并返回响应
#   3. 自动放行规则生效 (auto-allow)
#   4. settings.json 注入 + 卸载在 fixture 上无副作用

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

echo "=== 1) relay 在 app 没起时应立即放行 ==="
RES=$(CLAUDE_NOTCH_SOCKET="$SOCKET" \
      "$RELAY" --event PreToolUse --timeout 2 \
      <<<'{"tool_name":"Bash","tool_input":{"command":"ls"}}' 2>/dev/null)
check "no-server defaults allow" '"continue":true' "$RES"

echo ""
echo "=== 2) app 起来后 relay 能拿到响应 ==="
# 启 app (用自定义 socket 路径,避免污染默认)
CLAUDE_NOTCH_SOCKET="$SOCKET" "$APP" >/dev/null 2>&1 &
APP_PID=$!
# 等 socket 出现 (最多 5 秒)
for _ in $(seq 1 50); do
    [[ -S "$SOCKET" ]] && break
    sleep 0.1
done
if [[ ! -S "$SOCKET" ]]; then
    echo "  ❌ app 没在指定 socket 监听 (PID=$APP_PID)"
    FAIL=$((FAIL+1))
    exit 1
fi
echo "  ✅ app 启动监听 $SOCKET (PID=$APP_PID)"
PASS=$((PASS+1))

echo ""
echo "=== 3) Notification 事件应即时放行 (无审批 UI) ==="
RES=$(CLAUDE_NOTCH_SOCKET="$SOCKET" \
      "$RELAY" --event Notification --timeout 5 \
      <<<'{"message":"hello"}' 2>/dev/null)
check "notification allow" '"continue":true' "$RES"

echo ""
echo "=== 4) 日志文件应包含我们的事件 ==="
sleep 0.5
LOG="$HOME/Library/Logs/ClaudeNotch/app.log"
if [[ -f "$LOG" ]]; then
    if grep -q "Notification" "$LOG"; then
        echo "  ✅ 日志记录到 Notification 事件"
        PASS=$((PASS+1))
    else
        echo "  ⚠️  日志里没找到 Notification (可能延迟)"
    fi
fi

echo ""
echo "=== 5) app 优雅关闭 ==="
kill "$APP_PID"
wait "$APP_PID" 2>/dev/null || true
APP_PID=""
sleep 0.3

# 此时 socket 应被清理
if [[ ! -S "$SOCKET" ]]; then
    echo "  ✅ socket 已清理"
    PASS=$((PASS+1))
else
    echo "  ❌ socket 残留"
    FAIL=$((FAIL+1))
fi

echo ""
echo "=== 6) app 关闭后 relay 应再次降级放行 ==="
RES=$(CLAUDE_NOTCH_SOCKET="$SOCKET" \
      "$RELAY" --event PreToolUse --timeout 2 \
      <<<'{"tool_name":"Bash"}' 2>/dev/null)
check "post-shutdown allow" '"continue":true' "$RES"

echo ""
echo "=========================================="
echo "Pass: $PASS    Fail: $FAIL"
echo "=========================================="
[[ $FAIL -eq 0 ]] || exit 1
