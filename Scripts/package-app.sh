#!/bin/bash
# Package the binaries in build/ into a .app bundle and ad-hoc sign it.
# Output: build/Claude Notch.app
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
APP_NAME="Claude Notch"
BUNDLE="$BUILD/$APP_NAME.app"
EXEC_NAME="ClaudeNotchApp"

# Make sure the binaries are up to date
if [[ ! -x "$BUILD/ClaudeNotchApp" || ! -x "$BUILD/ClaudeNotchRelay" ]]; then
    echo "==> Binaries missing, building first..."
    "$ROOT/Scripts/build.sh"
fi

echo "==> Removing old $BUNDLE"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Helpers"
mkdir -p "$BUNDLE/Contents/Resources"

echo "==> Copying binaries"
cp "$BUILD/ClaudeNotchApp" "$BUNDLE/Contents/MacOS/$EXEC_NAME"
cp "$BUILD/ClaudeNotchRelay" "$BUNDLE/Contents/Helpers/ClaudeNotchRelay"

echo "==> Writing Info.plist"
cp "$ROOT/Resources/Info.plist" "$BUNDLE/Contents/Info.plist"

echo "==> Ad-hoc signing"
codesign --force --deep --sign - "$BUNDLE"

echo "==> Verifying signature"
codesign -dv "$BUNDLE" 2>&1 | head -3 || true

echo ""
echo "✅ Packaged: $BUNDLE"
echo ""
echo "Suggested next step:"
echo "  mv \"$BUNDLE\" /Applications/"
echo "  open \"/Applications/$APP_NAME.app\""
echo ""
echo "Or launch in place:"
echo "  open \"$BUNDLE\""
