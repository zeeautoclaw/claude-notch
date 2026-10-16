#!/bin/bash
# 把 build/ 里的二进制打成 .app bundle 并 ad-hoc 自签名。
# 输出: build/Claude Notch.app
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
APP_NAME="Claude Notch"
BUNDLE="$BUILD/$APP_NAME.app"
EXEC_NAME="ClaudeNotchApp"

# 先确保有最新的二进制
if [[ ! -x "$BUILD/ClaudeNotchApp" || ! -x "$BUILD/ClaudeNotchRelay" ]]; then
    echo "==> 二进制不存在,先构建..."
    "$ROOT/Scripts/build.sh"
fi

echo "==> 清理旧的 $BUNDLE"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Helpers"
mkdir -p "$BUNDLE/Contents/Resources"

echo "==> 拷贝二进制"
cp "$BUILD/ClaudeNotchApp" "$BUNDLE/Contents/MacOS/$EXEC_NAME"
cp "$BUILD/ClaudeNotchRelay" "$BUNDLE/Contents/Helpers/ClaudeNotchRelay"

echo "==> 写 Info.plist"
cp "$ROOT/Resources/Info.plist" "$BUNDLE/Contents/Info.plist"

echo "==> 自签名 (ad-hoc)"
codesign --force --deep --sign - "$BUNDLE"

echo "==> 验证签名"
codesign -dv "$BUNDLE" 2>&1 | head -3 || true

echo ""
echo "✅ 打包完成: $BUNDLE"
echo ""
echo "推荐操作:"
echo "  mv \"$BUNDLE\" /Applications/"
echo "  open \"/Applications/$APP_NAME.app\""
echo ""
echo "或就地启动:"
echo "  open \"$BUNDLE\""
