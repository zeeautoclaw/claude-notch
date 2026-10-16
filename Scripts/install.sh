#!/bin/bash
# Inject the hooks into ~/.claude/settings.json
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/ClaudeNotchApp"
[[ -x "$APP" ]] || { echo "Run ./Scripts/build.sh first"; exit 1; }
"$APP" --install-hooks
echo ""
echo "Next steps:"
echo "  1) Restart any running claude session (quit and run \`claude\` again)"
echo "  2) Launch Claude Notch:  open '$ROOT/build/Claude Notch.app'  (after packaging)"
echo "     or run the binary:   $APP &"
