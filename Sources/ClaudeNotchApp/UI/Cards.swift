import SwiftUI

// =============================================================================
// MARK: - 设计常量
// =============================================================================

/// 卡片的尺寸和圆角。内层圆角 = 外层圆角 - 内边距,保持同心。
enum NotchMetrics {
    static let cardWidth: CGFloat = 380
    static let cardPadding: CGFloat = 18
    static let cardRadius: CGFloat = 28
    static let innerRadius: CGFloat = cardRadius - cardPadding + 4
    /// 卡片四周留给玻璃高光和阴影的透明边距,窗口按它放大,避免被方形窗口裁出暗框。
    static let shadowMargin: CGFloat = 28
}

// =============================================================================
// MARK: - 共享组件
// =============================================================================

/// 卡片容器 — Liquid Glass 材质,可选整体染色 (危险操作用橙色)。
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

/// 卡片头部 — 彩色符号 + 标题 + 副标题,右侧可选徽章。
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

/// 主要操作按钮 — 实色渐变胶囊 + 玻璃高光描边。
/// 不用玻璃染色:浮窗不会成为活动窗口,玻璃染色和系统按钮都会被画成灰色的"非活动"样子。
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

/// 次要操作按钮 — 不染色的玻璃胶囊。
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

/// 玻璃按钮里的图标 + 文字,撑满可用宽度。
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

/// 一行主/次按钮,放进同一个玻璃容器里,让两颗玻璃按钮一起渲染。
struct ActionRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) { content }
        }
    }
}

/// 文字行动项 — 无边框,卡片底部用。
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

/// 命令/参数预览块 — 等宽字体,浅色内凹底。
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

/// 把 "mcp__ccd_session__start_session" 这类工具名变成好读的 "ccd_session · start_session"。
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
// MARK: - 审批卡片 (PreToolUse)
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
                    title: isDangerous ? "需要你确认 · 可能有风险" : "Claude 想要执行",
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

                // 主操作行
                ActionRow {
                    SecondaryActionButton(title: "拒绝", icon: "xmark") {
                        onResolve(.deny)
                    }
                    PrimaryActionButton(
                        title: "允许",
                        icon: "checkmark",
                        tint: isDangerous ? .orange : .blue
                    ) { onResolve(.allow) }
                }

                if isDangerous {
                    Label("不处理的话,约 50 秒后会自动拒绝", systemImage: "timer")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                // 次要操作行
                HStack(spacing: 4) {
                    if event.toolName == "Bash", let firstWord = bashFirstWord, !isDangerous {
                        TextActionButton(
                            title: "总是允许 \(firstWord)*",
                            icon: "checkmark.shield"
                        ) {
                            addCommandPrefixRule(firstWord)
                            onResolve(.allow)
                        }
                    } else if !isDangerous, event.toolName != nil {
                        TextActionButton(title: "总是允许此工具", icon: "checkmark.shield") {
                            addToolRule()
                            onResolve(.allow)
                        }
                    }

                    TextActionButton(title: "到终端", icon: "command") {
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
        rules.add(AllowRule(scope: .tool, value: tool, label: "整个 \(tool) 工具"))
    }

    private func addCommandPrefixRule(_ prefix: String) {
        guard let tool = event.toolName else { return }
        rules.add(AllowRule(
            scope: .toolWithCommand,
            value: "\(tool):\(prefix)",
            label: "\(tool) 中以 \(prefix) 开头"
        ))
    }
}

// =============================================================================
// MARK: - 提问卡片 (Notification / UserPromptSubmit 触发的等待)
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
                    title: "Claude 在问",
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
                        title: "到终端回答",
                        icon: "command",
                        tint: .purple
                    ) {
                        onJumpTerminal()
                        onResolve(.askUser)
                    }
                    SecondaryActionButton(title: "忽略") {
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
// MARK: - 选项卡片 (PreToolUse · AskUserQuestion)
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
                    title: "Claude 在问",
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
                    SecondaryActionButton(title: "到终端手动答", icon: "command") {
                        onJumpTerminal()
                    }
                    SecondaryActionButton(title: "取消") {
                        onCancel()
                    }
                }
            }
        }
    }

    private var optionCountBadge: String? {
        let c = options.count
        return c > 0 ? "\(c) 个选项" : nil
    }

    private var questionText: String {
        let qs = event.toolInput?["questions"]?.arrayValue ?? []
        if let q = qs.first?["question"]?.stringValue { return q }
        if let q = event.toolInput?["question"]?.stringValue { return q }
        if let q = event.toolInput?["prompt"]?.stringValue { return q }
        return "请选择"
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
// MARK: - Plan 卡片 (ExitPlanMode)
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
                    title: "Claude 的计划",
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
                        title: "批准并执行",
                        icon: "play.fill",
                        tint: .green
                    ) { onResolve(.allow) }

                    SecondaryActionButton(title: "打回", icon: "arrow.uturn.left") {
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
