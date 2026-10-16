import SwiftUI

/// Session list + simple settings inside the menu bar popover.
public struct SessionListPanel: View {
    @ObservedObject var sessions: SessionStore
    @ObservedObject var rules: RulesStore
    let installed: Bool
    let onInstall: () -> Void
    let onUninstall: () -> Void
    let onJump: (SessionInfo) -> Void
    let onKill: (SessionInfo) -> Void
    let onClearDone: () -> Void
    let onOpenLog: () -> Void
    let onTriggerDemo: () -> Void
    let onQuit: () -> Void

    @State private var nowTick = Date()
    @State private var showRules = false
    private let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    public var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if sessions.sortedActive.isEmpty {
                emptyState
            } else {
                List(sessions.sortedActive, id: \.id) { s in
                    SessionRow(
                        info: s,
                        now: nowTick,
                        onJump: { onJump(s) },
                        onKill: { onKill(s) }
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .frame(minHeight: 80, maxHeight: 280)
            }

            if !rules.rules.isEmpty || showRules {
                Divider()
                rulesSection
            }

            Divider()
            footer
        }
        .frame(width: 380)
        .onReceive(timer) { _ in
            nowTick = Date()
        }
    }

    private var rulesSection: some View {
        DisclosureGroup(isExpanded: $showRules) {
            VStack(alignment: .leading, spacing: 4) {
                if rules.rules.isEmpty {
                    Text("No rules yet. Tap \"Always allow...\" on an approval card to add one.")
                        .font(.caption).foregroundColor(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(rules.rules) { rule in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.label).font(.caption.bold())
                                Text(scopeText(rule)).font(.caption2).foregroundColor(.secondary)
                            }
                            Spacer()
                            Button {
                                rules.remove(id: rule.id)
                            } label: {
                                Image(systemName: "trash").font(.caption)
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 4)
        } label: {
            HStack {
                Image(systemName: "checkmark.shield")
                Text("Always Allow rules (\(rules.rules.count))")
                    .font(.subheadline)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    private func scopeText(_ rule: AllowRule) -> String {
        switch rule.scope {
        case .tool:            return "Whole tool: \(rule.value)"
        case .toolWithCommand: return "Command prefix: \(rule.value)"
        case .project:         return "Project: \(rule.value)"
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "rectangle.dashed")
                .foregroundColor(.accentColor)
            Text("Claude Notch")
                .font(.headline)
            Spacer()
            Text(installed ? "Hooks installed" : "Hooks not installed")
                .font(.caption)
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(installed ? Color.green.opacity(0.18) : Color.orange.opacity(0.2))
                .foregroundColor(installed ? .green : .orange)
                .clipShape(Capsule())
        }
        .padding(12)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "moon.zzz")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("No active sessions")
                .font(.subheadline).foregroundColor(.secondary)
            Text("Run \(Text("claude").font(.system(.subheadline, design: .monospaced))) in a terminal and it shows up here")
                .font(.caption).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if installed {
                Button("Uninstall Hooks", action: onUninstall).buttonStyle(.borderless)
            } else {
                Button("Install Hooks", action: onInstall).buttonStyle(.borderless)
            }
            Spacer()
            Menu {
                Button("Show Demo Card", action: onTriggerDemo)
                Button("Open Log", action: onOpenLog)
                Button("Clear Finished", action: onClearDone)
                    .disabled(sessions.sortedActive.allSatisfy { !$0.isDone })
                Divider()
                Button("Quit Claude Notch", action: onQuit)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}

private struct SessionRow: View {
    let info: SessionInfo
    let now: Date
    let onJump: () -> Void
    let onKill: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            statusDot
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(info.title)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                    Spacer()
                    pill(info.shortTermLabel)
                    Text(durationLabel)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }

                if !info.lastUserPrompt.isEmpty {
                    Text("You: \(info.lastUserPrompt)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                statusLine
            }

            // Action buttons on the right: jump / end
            VStack(spacing: 6) {
                Button(action: onJump) {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Go to terminal")

                if info.claudePID != nil && info.status != .done {
                    Button(action: onKill) {
                        Image(systemName: "xmark.octagon.fill")
                            .font(.caption)
                            .foregroundColor(.red.opacity(0.75))
                    }
                    .buttonStyle(.borderless)
                    .help("End this claude process")
                }
            }
            .opacity(hovering ? 1.0 : 0.45)
        }
        .contentShape(Rectangle())
        .onTapGesture { onJump() }
        .onHover { hovering = $0 }
    }

    private var statusDot: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(dotColor.opacity(0.4), lineWidth: 4)
                    .frame(width: 14, height: 14)
                    .opacity(info.status == .running ? 0.8 : 0)
            )
    }

    private var dotColor: Color {
        switch info.status {
        case .running: return .blue
        case .waiting: return .orange
        case .done:    return .green
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch info.status {
        case .running:
            if let tool = info.lastToolName {
                Text("Running \(tool)\(info.lastToolPreview.map { ": \($0)" } ?? "")")
                    .font(.caption2.italic())
                    .foregroundColor(.blue.opacity(0.85))
                    .lineLimit(1)
            } else {
                Text("Running").font(.caption2.italic()).foregroundColor(.blue.opacity(0.85))
            }
        case .waiting:
            HStack(spacing: 4) {
                Image(systemName: "hand.raised.fill").font(.caption2)
                Text("Waiting for approval: \(info.lastToolName ?? "?")")
            }
            .font(.caption2.italic())
            .foregroundColor(.orange)
        case .done:
            Text("✓ Done — click to jump")
                .font(.caption2)
                .foregroundColor(.green)
        }
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Color.gray.opacity(0.2))
            .clipShape(Capsule())
    }

    private var durationLabel: String {
        let base = info.doneAt ?? info.lastActivityAt
        let delta: TimeInterval
        if info.status == .done, let doneAt = info.doneAt {
            delta = now.timeIntervalSince(doneAt)
        } else {
            delta = now.timeIntervalSince(info.startedAt)
            _ = base
        }
        return DurationFormatter.short(delta)
    }
}

private extension SessionInfo {
    var shortTermLabel: String {
        switch termProgram {
        case "iTerm.app":         return "iTerm"
        case "Apple_Terminal":    return "Terminal"
        case "vscode":            return "VSCode"
        case "ghostty":           return "Ghostty"
        case "WarpTerminal":      return "Warp"
        default:
            if termProgram == "Unknown" { return "?" }
            return termProgram
        }
    }
}
