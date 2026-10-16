#!/bin/bash
# 移除 hook,settings.json 恢复 Claude Notch 之前的状态。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/ClaudeNotchApp"
[[ -x "$APP" ]] || { echo "找不到 $APP"; exit 1; }
"$APP" --uninstall-hooks
