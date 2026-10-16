#!/bin/bash
# One-step redeploy: build + package + stop old instance + copy + launch
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "🔨 Building..."
"$ROOT/Scripts/build.sh"

echo ""
echo "📦 Packaging..."
"$ROOT/Scripts/package-app.sh"

echo ""
echo "🛑 Stopping old instance..."
pkill -f ClaudeNotchApp 2>/dev/null || true
sleep 0.5

echo ""
echo "📥 Installing to /Applications..."
rm -rf "/Applications/Claude Notch.app"
cp -R "$ROOT/build/Claude Notch.app" /Applications/

echo ""
echo "🚀 Launching..."
open "/Applications/Claude Notch.app"
sleep 1

if pgrep -f ClaudeNotchApp >/dev/null; then
    echo ""
    echo "✅ Done (PID $(pgrep -f ClaudeNotchApp))"
else
    echo ""
    echo "❌ Launch failed, see ~/Library/Logs/ClaudeNotch/app.log"
    exit 1
fi
