import SwiftUI

/// 极简 markdown 渲染:支持标题/列表/段落 + inline `code` / **bold**。
public struct SimpleMarkdown: View {
    let text: String

    public init(_ text: String) { self.text = text }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(parseLines().enumerated()), id: \.offset) { _, line in
                renderLine(line)
            }
        }
    }

    enum Line {
        case heading(level: Int, text: String)
        case bullet(text: String)
        case numbered(index: String, text: String)
        case code(text: String)
        case paragraph(text: String)
        case blank
    }

    func parseLines() -> [Line] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { sub in
            let s = String(sub)
            let trimmed = s.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return .blank }
            if trimmed.hasPrefix("###") {
                return .heading(level: 3, text: String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces))
            }
            if trimmed.hasPrefix("##") {
                return .heading(level: 2, text: String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces))
            }
            if trimmed.hasPrefix("#") {
                return .heading(level: 1, text: String(trimmed.dropFirst(1)).trimmingCharacters(in: .whitespaces))
            }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                return .bullet(text: String(trimmed.dropFirst(2)))
            }
            if let dotIdx = trimmed.firstIndex(of: "."),
               trimmed[..<dotIdx].allSatisfy(\.isNumber),
               !trimmed[..<dotIdx].isEmpty {
                let num = String(trimmed[..<dotIdx])
                let rest = trimmed[trimmed.index(after: dotIdx)...].trimmingCharacters(in: .whitespaces)
                return .numbered(index: num, text: rest)
            }
            if trimmed.hasPrefix("```") {
                return .code(text: trimmed.replacingOccurrences(of: "```", with: ""))
            }
            return .paragraph(text: trimmed)
        }
    }

    @ViewBuilder
    func renderLine(_ line: Line) -> some View {
        switch line {
        case .heading(let lvl, let t):
            Text(MarkdownInline.attributed(t))
                .font(headingFont(level: lvl))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)

        case .bullet(let t):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                    .foregroundColor(.green)
                    .font(.system(size: 13, weight: .bold))
                Text(MarkdownInline.attributed(t))
                    .font(.system(size: 13))
                    .foregroundColor(.primary.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .numbered(let i, let t):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(i).")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundColor(.green)
                Text(MarkdownInline.attributed(t))
                    .font(.system(size: 13))
                    .foregroundColor(.primary.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .code(let t):
            Text(t)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.primary.opacity(0.92))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))

        case .paragraph(let t):
            Text(MarkdownInline.attributed(t))
                .font(.system(size: 13))
                .foregroundColor(.primary.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)

        case .blank:
            Spacer().frame(height: 4)
        }
    }

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1: return .system(size: 16, weight: .bold)
        case 2: return .system(size: 15, weight: .semibold)
        default: return .system(size: 14, weight: .semibold)
        }
    }
}

/// inline 转换工具 — 把 `code` 和 **bold** 变成 AttributedString。
enum MarkdownInline {
    static func attributed(_ src: String) -> AttributedString {
        var attr = AttributedString(src)
        applyBackticks(&attr)
        applyBold(&attr)
        return attr
    }

    private static func applyBackticks(_ attr: inout AttributedString) {
        // 找成对的 ` ... ` 段落,设 monospace + 浅色背景
        while let openRange = attr.range(of: "`") {
            let after = openRange.upperBound
            guard let closeRange = attr[after...].range(of: "`") else { break }
            // 先去 close,再去 open,避免索引漂移
            attr.removeSubrange(closeRange)
            // 注意: open 的 range 没变,但 after 之后的字符串现在缩短了
            // 重新计算被包的范围
            let codeRange = openRange.upperBound..<closeRange.lowerBound
            // 应用样式
            var container = AttributeContainer()
            container.font = .system(size: 12, design: .monospaced)
            container.backgroundColor = .gray.opacity(0.18)
            attr[codeRange].mergeAttributes(container)
            attr.removeSubrange(openRange)
        }
    }

    private static func applyBold(_ attr: inout AttributedString) {
        while let openRange = attr.range(of: "**") {
            let after = openRange.upperBound
            guard let closeRange = attr[after...].range(of: "**") else { break }
            attr.removeSubrange(closeRange)
            let boldRange = openRange.upperBound..<closeRange.lowerBound
            var container = AttributeContainer()
            container.font = .system(size: 13, weight: .semibold)
            attr[boldRange].mergeAttributes(container)
            attr.removeSubrange(openRange)
        }
    }
}
