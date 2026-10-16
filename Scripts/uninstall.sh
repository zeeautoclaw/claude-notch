#!/bin/bash
# Remove the hooks and restore settings.json to its pre-Claude-Notch state.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/ClaudeNotchApp"
[[ -x "$APP" ]] || { echo "Not found: $APP"; exit 1; }
"$APP" --uninstall-hooks
