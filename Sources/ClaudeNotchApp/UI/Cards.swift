import SwiftUI

// =============================================================================
// MARK: - Design constants
// =============================================================================

/// Card size and corner radii. Inner radius = outer radius - padding, so corners stay concentric.
enum NotchMetrics {
    static let cardWidth: CGFloat = 380
    static let cardPadding: CGFloat = 18
    static let cardRadius: CGFloat = 28
    static let innerRadius: CGFloat = cardRadius - cardPadding + 4
    /// Transparent margin around the card for the glass highlight and shadow; the window grows by this so nothing gets clipped.
    static let shadowMargin: CGFloat = 28
}

// =============================================================================
// MARK: - Shared components
// =============================================================================

/// Card container — Liquid Glass material, optionally tinted (orange for risky actions).
struct NotchCardContainer<Content: View>: View {
    var tint: Color? = nil
    let content: Content

    init(tint: Color? = nil, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        content
            .padding(NotchMetrics.cardPadding)
            .frame(width: NotchMetrics.cardWidth)
            .glassEffect(glass, in: .rect(cornerRadius: NotchMetrics.cardRadius))
            .padding(EdgeInsets(top: 10, leading: NotchMetrics.shadowMargin,
                                bottom: NotchMetrics.shadowMargin + 8, trailing: NotchMetrics.shadowMargin))
    }

    private var glass: Glass {
        if let tint { return .regular.tint(tint.opacity(0.18)) }
        return .regular
    }
}

/// Card header — colored symbol + title + subtitle, optional badge on the right.
struct CardIconHeader: View {
    let symbol: String
    let title: String
    let tint: Color
    var subtitle: String? = nil
    var badge: String? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.14), in: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 8)

            if let badge {
                Text(badge)
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .glassEffect(.regular, in: .capsule)
            }
        }
    }
}

/// Primary action button — solid gradient capsule + glass highlight stroke.
/// Not glass-tinted: the panel never becomes the active window, and tinted glass or system buttons would render grey/inactive.
struct PrimaryActionButton: View {
    let title: String
    var icon: String? = nil
    let tint: Color
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            GlassButtonLabel(title: title, icon: icon, weight: .semibold)
                .foregroundStyle(.white)
                .background(tint.gradient, in: .capsule)
                .overlay(
                    Capsule().strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.05)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 0.8
                    )
                )
                .shadow(color: tint.opacity(hovering ? 0.45 : 0.28), radius: hovering ? 10 : 6, y: 3)
                .brightness(hovering ? 0.06 : 0)
                .animation(.easeOut(duration: 0.15), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Secondary action button — untinted glass capsule.
struct SecondaryActionButton: View {
    let title: String
    var icon: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GlassButtonLabel(title: title, icon: icon, weight: .medium)
                .foregroundStyle(.primary)
                .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
    }
}

/// Icon + text inside a glass button, filling the available width.
private struct GlassButtonLabel: View {
    let title: String
    let icon: String?
    let weight: Font.Weight

    var body: some View {
        HStack(spacing: 6) {
            if let icon { Image(systemName: icon).font(.system(size: 12, weight: .bold)) }
            Text(title)
        }
        .font(.system(size: 13, weight: weight))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .contentShape(.capsule)
    }
}

/// A row of primary/secondary buttons in one glass container so they render together.
struct ActionRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) { content }
        }
    }
}

/// Text action — borderless, used at the bottom of the card.
struct TextActionButton: View {
    let title: String
    var icon: String? = nil
    var enabled: Bool = true
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon).font(.system(size: 11, weight: .medium)) }
                Text(title)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(enabled ? (hovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                                     : AnyShapeStyle(.tertiary))
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(hovering && enabled ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: .capsule)
            .contentShape(.capsule)
            .animation(.easeOut(duration: 0.15), value: hovering)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovering = $0 }
    }
}

/// Command/argument preview — monospaced text on a subtle inset background.
struct CodeBlock: View {
    let text: String
    var lineLimit: Int = 3

    var body: some View {
        Text(text)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(.primary.opacity(0.85))
            .lineLimit(lineLimit)
            .truncationMode(.tail)
            .multilineTextAlignment(.leading)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.primary.opacity(0.06), in: .rect(cornerRadius: NotchMetrics.innerRadius))
    }
}

/// Turns tool names like "mcp__ccd_session__start_session" into a readable "ccd_session · start_session".
enum ToolName {
    static func pretty(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "Unknown" }
        guard raw.hasPrefix("mcp__") else { return raw }
        let parts = raw.dropFirst(5).components(separatedBy: "__")
        guard parts.count >= 2 else { return String(raw.dropFirst(5)) }
        return parts[0] + " · " + parts.dropFirst().joined(separator: "_")
    }
}

// =============================================================================
// MARK: - Approval card (PreToolUse)
// =============================================================================

struct ApprovalCard: View {
    let request: ApprovalRequest
    let waiting: Int
    @ObservedObject var rules: RulesStore
    let onResolve: (Decision) -> Void
    let onJumpTerminal: () -> Void

    var event: HookEvent { request.event }
    var isDangerous: Bool { Safety.isDangerous(event) }

    var body: some View {
        NotchCardContainer(tint: isDangerous ? .orange : nil) {
            VStack(alignment: .leading, spacing: 14) {
                CardIconHeader(
                    symbol: isDangerous ? "exclamationmark.shield.fill" : "checkmark.shield.fill",
                    title: isDangerous ? "Needs your OK · may be risky" : "Claude wants to run",
                    tint: isDangerous ? .orange : .blue,
                    subtitle: prettyCWD,
                    badge: waiting > 0 ? "+\(waiting)" : nil
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text(ToolName.pretty(event.toolName))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if !event.commandPreview.isEmpty {
                        CodeBlock(text: event.commandPreview)
                    }
                }

                // Primary actions
                ActionRow {
                    SecondaryActionButton(title: "Deny", icon: "xmark") {
                        onResolve(.deny)
                    }
                    PrimaryActionButton(
                        title: "Allow",
                        icon: "checkmark",
                        tint: isDangerous ? .orange : .blue
                    ) { onResolve(.allow) }
                }

                if isDangerous {
                    Label("If you do nothing, this is denied in about 50 seconds", systemImage: "timer")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                // Secondary actions
                HStack(spacing: 4) {
                    if event.toolName == "Bash", let firstWord = bashFirstWord, !isDangerous {
                        TextActionButton(
                            title: "Always allow \(firstWord)*",
                            icon: "checkmark.shield"
                        ) {
                            addCommandPrefixRule(firstWord)
                            onResolve(.allow)
                        }
                    } else if !isDangerous, event.toolName != nil {
                        TextActionButton(title: "Always allow this tool", icon: "checkmark.shield") {
                            addToolRule()
                            onResolve(.allow)
                        }
                    }

                    TextActionButton(title: "Go to terminal", icon: "command") {
                        onJumpTerminal()
                    }
                }
            }
        }
    }

    private var prettyCWD: String {
        let parts = event.cwd.split(separator: "/")
        let suffix = parts.suffix(2).joined(separator: "/")
        return "~/" + suffix
    }

    private var bashFirstWord: String? {
        Safety.firstWord(of: event.commandPreview)
    }

    private func addToolRule() {
        guard let tool = event.toolName else { return }
        rules.add(AllowRule(scope: .tool, value: tool, label: "All of \(tool)"))
    }

    private func addCommandPrefixRule(_ prefix: String) {
        guard let tool = event.toolName else { return }
        rules.add(AllowRule(
            scope: .toolWithCommand,
            value: "\(tool):\(prefix)",
            label: "\(tool) starting with \(prefix)"
        ))
    }
}

// =============================================================================
// MARK: - Question card (waiting triggered by Notification / UserPromptSubmit)
// =============================================================================

struct QuestionCard: View {
    let request: ApprovalRequest
    let waiting: Int
    let onResolve: (Decision) -> Void
    let onJumpTerminal: () -> Void

    var event: HookEvent { request.event }

    var body: some View {
        NotchCardContainer {
            VStack(alignment: .leading, spacing: 12) {
                CardIconHeader(
                    symbol: "questionmark",
                    title: "Claude is asking",
                    tint: .purple,
                    badge: waiting > 0 ? "+\(waiting)" : nil
                )

                Text(messageText)
                    .font(.system(size: 13))
                    .foregroundColor(.primary.opacity(0.92))
                    .lineLimit(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                ActionRow {
                    PrimaryActionButton(
                        title: "Answer in terminal",
                        icon: "command",
                        tint: .purple
                    ) {
                        onJumpTerminal()
                        onResolve(.askUser)
                    }
                    SecondaryActionButton(title: "Ignore") {
                        onResolve(.allow)
                    }
                }
            }
        }
    }

    private var messageText: String {
        if let s = event.payload["message"]?.stringValue { return s }
        if let s = event.payload["text"]?.stringValue { return s }
        return event.payload.displayString
    }
}

// =============================================================================
// MARK: - Choice card (PreToolUse · AskUserQuestion)
// =============================================================================

struct QuestionChoiceCard: View {
    let request: ApprovalRequest
    let waiting: Int
    let onChoose: (String) -> Void
    let onCancel: () -> Void
    let onJumpTerminal: () -> Void

    var event: HookEvent { request.event }

    private struct Option {
        let label: String
        let detail: String?
    }

    var body: some View {
        NotchCardContainer {
            VStack(alignment: .leading, spacing: 12) {
                CardIconHeader(
                    symbol: "questionmark",
                    title: "Claude is asking",
                    tint: .purple,
                    badge: optionCountBadge
                )

                Text(questionText)
                    .font(.system(size: 13))
                    .foregroundColor(.primary.opacity(0.92))
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 6) {
                    ForEach(Array(options.enumerated()), id: \.offset) { idx, opt in
                        QuestionOptionRow(
                            index: idx + 1,
                            label: opt.label,
                            detail: opt.detail,
                            tint: .purple,
                            action: { onChoose(String(idx + 1)) }
                        )
                    }
                }

                ActionRow {
                    SecondaryActionButton(title: "Answer in terminal", icon: "command") {
                        onJumpTerminal()
                    }
                    SecondaryActionButton(title: "Cancel") {
                        onCancel()
                    }
                }
            }
        }
    }

    private var optionCountBadge: String? {
        let c = options.count
        return c > 0 ? "\(c) options" : nil
    }

    private var questionText: String {
        let qs = event.toolInput?["questions"]?.arrayValue ?? []
        if let q = qs.first?["question"]?.stringValue { return q }
        if let q = event.toolInput?["question"]?.stringValue { return q }
        if let q = event.toolInput?["prompt"]?.stringValue { return q }
        return "Please choose"
    }

    private var options: [Option] {
        let qs = event.toolInput?["questions"]?.arrayValue ?? []
        if let firstOpts = qs.first?["options"]?.arrayValue {
            return firstOpts.map { parseOption($0) }
        }
        if let opts = (event.toolInput?["options"] ?? event.toolInput?["choices"])?.arrayValue {
            return opts.map { parseOption($0) }
        }
        return []
    }

    private func parseOption(_ raw: AnyCodable) -> Option {
        if let s = raw.stringValue {
            return Option(label: s, detail: nil)
        }
        if let obj = raw.objectValue {
            let label = obj["label"]?.stringValue
                ?? obj["text"]?.stringValue
                ?? obj["value"]?.stringValue
                ?? "?"
            let detail = obj["description"]?.stringValue ?? obj["detail"]?.stringValue
            return Option(label: label, detail: detail)
        }
        return Option(label: raw.displayString, detail: nil)
    }
}

private struct QuestionOptionRow: View {
    let index: Int
    let label: String
    let detail: String?
    let tint: Color
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Text("⌥\(index)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(hovering ? tint : .secondary)
                    .frame(width: 26, height: 18)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(hovering ? tint.opacity(0.18) : Color.primary.opacity(0.08))
                    )
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text(label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hovering ? tint.opacity(0.13) : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(hovering ? tint.opacity(0.45) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .keyboardShortcut(KeyEquivalent(Character("\(index)")), modifiers: .option)
    }
}

// =============================================================================
// MARK: - Plan card (ExitPlanMode)
// =============================================================================

struct PlanCard: View {
    let request: ApprovalRequest
    let waiting: Int
    let onResolve: (Decision) -> Void

    var event: HookEvent { request.event }

    var body: some View {
        NotchCardContainer {
            VStack(alignment: .leading, spacing: 12) {
                CardIconHeader(
                    symbol: "list.bullet",
                    title: "Claude's plan",
                    tint: .green,
                    badge: "1/1"
                )

                ScrollView {
                    SimpleMarkdown(planText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 220)

                ActionRow {
                    PrimaryActionButton(
                        title: "Approve and run",
                        icon: "play.fill",
                        tint: .green
                    ) { onResolve(.allow) }

                    SecondaryActionButton(title: "Send back", icon: "arrow.uturn.left") {
                        onResolve(.deny)
                    }
                }
            }
        }
    }

    private var planText: String {
        event.toolInput?["plan"]?.stringValue
            ?? event.toolInput?["plan_md"]?.stringValue
            ?? event.commandPreview
    }
}
