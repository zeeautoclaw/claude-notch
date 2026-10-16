#!/bin/bash
# 构建 ClaudeNotchRelay 和 ClaudeNotchApp。
# 由于 Command Line Tools 不带 Platforms 目录,SwiftPM (swift build) 在 Swift 5.8 上会失败。
# 这里改用 swiftc 直接编译。

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
mkdir -p "$BUILD"

SHARED_SRC=( "$ROOT"/Sources/ClaudeNotchShared/*.swift )
RELAY_SRC=( "$ROOT"/Sources/ClaudeNotchRelay/*.swift )
APP_SRC=( "$ROOT"/Sources/ClaudeNotchApp/*.swift "$ROOT"/Sources/ClaudeNotchApp/UI/*.swift )

OPT_FLAGS="-O -wmo"
DEBUG_FLAGS="-Onone -g"
FLAGS="$OPT_FLAGS"

if [[ "${DEBUG:-0}" = "1" ]]; then
    FLAGS="$DEBUG_FLAGS"
fi

echo "==> 编译 ClaudeNotchRelay"
xcrun swiftc $FLAGS \
    -target arm64-apple-macos27.0 \
    -module-name ClaudeNotchRelay \
    -o "$BUILD/ClaudeNotchRelay" \
    "${SHARED_SRC[@]}" \
    "${RELAY_SRC[@]}"

echo "==> 编译 ClaudeNotchApp"
xcrun swiftc $FLAGS \
    -target arm64-apple-macos27.0 \
    -module-name ClaudeNotchApp \
    -framework AppKit \
    -framework SwiftUI \
    -framework Combine \
    -o "$BUILD/ClaudeNotchApp" \
    "${SHARED_SRC[@]}" \
    "${APP_SRC[@]}"

echo "==> 二进制大小:"
ls -lh "$BUILD/ClaudeNotchRelay" "$BUILD/ClaudeNotchApp" | awk '{print "    " $9 ": " $5}'

echo "==> 完成。"
