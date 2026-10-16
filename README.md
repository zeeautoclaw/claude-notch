# Claude Notch

> Approve Claude Code tool calls from a floating Liquid Glass card at the top of your Mac screen — no switching back to the terminal.

<p>
  <img src="docs/card-normal.png" width="380" alt="Approval card">
  <img src="docs/card-risky.png" width="380" alt="Risky command card">
</p>

A personal side project, provided as is, with no promise of maintenance.

## What it does

- When Claude Code wants to use a tool, a card appears at the top of the screen: **Deny / Allow / Always allow this tool / Go to terminal**.
- **Risky commands get special treatment**: `sudo`, `rm -rf`, `git push --force`, `git reset --hard`, `dd`, `mkfs`, `diskutil`, `curl`/`wget` to non-local addresses, and similar:
  - a card always appears, even if you set "Always allow" for that tool;
  - the card is orange and cannot be "always allowed";
  - if nobody answers within about 50 seconds it is **denied automatically**. Only that one command is blocked; Claude is told why and the session keeps going.
- Ordinary commands that nobody answers are allowed after about 50 seconds, so work does not stall while you are away.
- Plans (plan mode) and `AskUserQuestion` choices can also be handled from the card.

## Requirements

- Apple Silicon Mac, macOS 27
- Full Xcode (needed to compile SwiftUI; the Command Line Tools alone are not enough)
- Claude Code CLI

## Install

```bash
git clone https://github.com/zeeautoclaw/claude-notch.git
cd claude-notch
./Scripts/build.sh          # compile
./Scripts/package-app.sh    # package as a .app (ad-hoc signed)
mv "build/Claude Notch.app" /Applications/
open "/Applications/Claude Notch.app"
```

Build with `Scripts/build.sh`; `swift build` is not supported (the sources are organized as a single module).

The app is not signed with an Apple Developer ID. If macOS blocks it the first time, right-click it in Finder → Open, and confirm once.

Then click the menu bar icon → **Install Hooks**. This:

- backs up `~/.claude/settings.json` to `~/.claude/settings.json.claude-notch.bak`
- adds only its own 4 hooks (PreToolUse / Notification / Stop / UserPromptSubmit) and leaves everything else alone

Restart any running `claude` session afterwards so it picks up the new hooks.

### Launch at login (optional)

```bash
cat > ~/Library/LaunchAgents/local.claudenotch.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>local.claudenotch</string>
  <key>ProgramArguments</key><array>
    <string>/usr/bin/open</string><string>-a</string><string>/Applications/Claude Notch.app</string>
  </array>
  <key>RunAtLoad</key><true/>
</dict></plist>
EOF
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/local.claudenotch.plist
```

## How it works

```
Claude Code fires a hook
  → the command in ~/.claude/settings.json starts ClaudeNotchRelay
  → the relay sends the event to ClaudeNotchApp over a Unix socket
  → the app decides: matches "Always allow" and not risky → allow; otherwise show a card
  → you click (or it times out) → the decision goes back to Claude Code
```

**It is designed not to block your work**: if the app is not running, the socket fails, or the relay waits more than 60 seconds, the relay allows the call and Claude Code's own permission settings take over.

The risk check is a fixed list of patterns in [`Safety.swift`](Sources/ClaudeNotchShared/Safety.swift) — plain code, no AI and no network. It is an extra reminder layer, not a security boundary: a command written to avoid the patterns will not be flagged.

## "Always allow" rules

Stored in `~/Library/Application Support/ClaudeNotch/rules.json`; you can edit the file directly. Risky commands ignore these rules.

## Jump to terminal

| Terminal | Support |
|---|---|
| iTerm2 | Jumps to the matching session (via `ITERM_SESSION_ID`) |
| Terminal.app | Brings the window forward only |

Needs macOS Automation permission: System Settings → Privacy & Security → Automation.

## Tests

```bash
# unit tests
xcrun swiftc -O -target arm64-apple-macos27.0 -o build/TestRunner \
    Sources/ClaudeNotchShared/*.swift Tests/Runner/main.swift
./build/TestRunner

# end-to-end smoke test (no real Claude needed)
./Scripts/smoke.sh
```

## Troubleshooting

| Symptom | Fix |
|---|---|
| No cards appear | Check the menu bar shows "Hooks installed"; restart the `claude` session; read `~/Library/Logs/ClaudeNotch/app.log` |
| "Go to terminal" does nothing | Check the Automation permission |
| macOS says the app is damaged | `xattr -dr com.apple.quarantine "/Applications/Claude Notch.app"` |
| Redeploy after changing code | `./Scripts/redeploy.sh` |

## Uninstall

```bash
"/Applications/Claude Notch.app/Contents/MacOS/ClaudeNotchApp" --uninstall-hooks
rm -rf "/Applications/Claude Notch.app"
rm -rf ~/Library/Application\ Support/ClaudeNotch ~/Library/Logs/ClaudeNotch
```

## Similar projects

There are several more mature open-source tools in this space that support more coding agents — worth comparing:
[Casement](https://github.com/aviralgarg05/casement),
[Coucou](https://github.com/Louis-CFM/coucou),
[Vibe Notch](https://github.com/farouqaldori/vibe-notch),
[notch-for-claude-code](https://github.com/deDavil/notch-for-claude-code).

## License

MIT — see [LICENSE](LICENSE). Not affiliated with Anthropic.
