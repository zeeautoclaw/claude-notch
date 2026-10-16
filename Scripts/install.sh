#!/bin/bash
# 注入 hook 到 ~/.claude/settings.json
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/ClaudeNotchApp"
[[ -x "$APP" ]] || { echo "需要先 ./Scripts/build.sh"; exit 1; }
"$APP" --install-hooks
echo ""
echo "下一步:"
echo "  1) 重启正在跑的 claude session (退出后重新 \`claude\`)"
echo "  2) 启动 Claude Notch:  open '$ROOT/build/Claude Notch.app'  (打包后)"
echo "     或直接跑二进制:      $APP &"
