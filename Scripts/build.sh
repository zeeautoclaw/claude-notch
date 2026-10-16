#!/bin/bash
# Build ClaudeNotchRelay and ClaudeNotchApp.
# SwiftPM (swift build) does not work for this layout, so we call swiftc directly.
# Requires full Xcode (SwiftUI macros are not in the Command Line Tools).

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

echo "==> Compiling ClaudeNotchRelay"
xcrun swiftc $FLAGS \
    -target arm64-apple-macos27.0 \
    -module-name ClaudeNotchRelay \
    -o "$BUILD/ClaudeNotchRelay" \
    "${SHARED_SRC[@]}" \
    "${RELAY_SRC[@]}"

echo "==> Compiling ClaudeNotchApp"
xcrun swiftc $FLAGS \
    -target arm64-apple-macos27.0 \
    -module-name ClaudeNotchApp \
    -framework AppKit \
    -framework SwiftUI \
    -framework Combine \
    -o "$BUILD/ClaudeNotchApp" \
    "${SHARED_SRC[@]}" \
    "${APP_SRC[@]}"

echo "==> Binary sizes:"
ls -lh "$BUILD/ClaudeNotchRelay" "$BUILD/ClaudeNotchApp" | awk '{print "    " $9 ": " $5}'

echo "==> Done."
