#!/bin/bash
# 一键重部署: build + 打包 + 杀旧 + 拷贝 + 启动
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "🔨 构建..."
"$ROOT/Scripts/build.sh"

echo ""
echo "📦 打包..."
"$ROOT/Scripts/package-app.sh"

echo ""
echo "🛑 停旧实例..."
pkill -f ClaudeNotchApp 2>/dev/null || true
sleep 0.5

echo ""
echo "📥 部署到 /Applications..."
rm -rf "/Applications/Claude Notch.app"
cp -R "$ROOT/build/Claude Notch.app" /Applications/

echo ""
echo "🚀 启动..."
open "/Applications/Claude Notch.app"
sleep 1

if pgrep -f ClaudeNotchApp >/dev/null; then
    echo ""
    echo "✅ 完成 (PID $(pgrep -f ClaudeNotchApp))"
else
    echo ""
    echo "❌ 启动失败,看 ~/Library/Logs/ClaudeNotch/app.log"
    exit 1
fi
