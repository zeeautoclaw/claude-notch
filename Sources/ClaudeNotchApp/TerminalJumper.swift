import Foundation
import AppKit

/// 通过 AppleScript 把指定 terminal 拉到前台并跳到对应 session/tab。
public enum TerminalJumper {
    private static let logger = Logger(tag: "jumper")

    /// 根据 hook event 的 env 信息选择策略并执行。失败仅日志,不抛错。
    public static func jump(to event: HookEvent) {
        let termProgram = event.env["TERM_PROGRAM"] ?? ""
        switch termProgram {
        case "iTerm.app":
            jumpITerm(sessionID: event.env["ITERM_SESSION_ID"])
        case "Apple_Terminal":
            jumpAppleTerminal(sessionID: event.env["TERM_SESSION_ID"])
        default:
            logger.warn("unknown TERM_PROGRAM=\(termProgram), bringing iTerm forward as fallback")
            activate(bundleId: "com.googlecode.iterm2")
        }
    }

    // MARK: - iTerm2

    static func jumpITerm(sessionID: String?) {
        guard let sid = sessionID else {
            activate(bundleId: "com.googlecode.iterm2")
            return
        }
        // iTerm2 的 session 唯一 ID 包含 ITERM_SESSION_ID 环境变量值的最后一段
        let cleanSid = sid.split(separator: ":").last.map(String.init) ?? sid
        let script = """
        tell application "iTerm"
            activate
            try
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            try
                                if (unique id of s as string) contains "\(cleanSid)" then
                                    tell w to select
                                    tell t to select
                                    select s
                                    return "ok"
                                end if
                            end try
                        end repeat
                    end repeat
                end repeat
            end try
            return "not_found"
        end tell
        """
        runScript(script)
    }

    // MARK: - Terminal.app

    static func jumpAppleTerminal(sessionID: String?) {
        // Terminal.app 没暴露 session id 查询,仅 activate
        let script = """
        tell application "Terminal"
            activate
        end tell
        """
        runScript(script)
    }

    // MARK: - 通用

    private static func activate(bundleId: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            logger.warn("app not installed: \(bundleId)")
            return
        }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: cfg) { _, error in
            if let e = error { Self.logger.warn("activate failed: \(e)") }
        }
    }

    @discardableResult
    private static func runScript(_ source: String) -> String? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&error)
        if let err = error {
            logger.warn("AppleScript error: \(err)")
            return nil
        }
        return result.stringValue
    }

    // MARK: - 写入文本到 iTerm session (AskUserQuestion 自动作答)

    /// 把 text 写到 iTerm 指定 session(等价于在终端里手敲)。
    /// 如果不是 iTerm 或找不到 session,fallback 到剪贴板 + 提示用户粘贴。
    public static func type(text: String, into event: HookEvent) {
        // 我们手动发 \r (CR) 作为 Enter — Claude Code 的 TUI 需要 CR 才认。
        // AppleScript 字符串字面量转义: \, "
        // 真实 \n / \r 转义成 AppleScript 字面量 \r (Claude TUI 要 CR)。
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r\n", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\r")
            .replacingOccurrences(of: "\r", with: "\\r")

        if event.env["TERM_PROGRAM"] == "iTerm.app",
           let sid = event.env["ITERM_SESSION_ID"] {
            let cleanSid = sid.split(separator: ":").last.map(String.init) ?? sid
            // newline NO: 让我们自己控制,不让 iTerm 自动追加 \n
            let script = """
            tell application "iTerm"
                activate
                try
                    repeat with w in windows
                        repeat with t in tabs of w
                            repeat with s in sessions of t
                                try
                                    if (unique id of s as string) contains "\(cleanSid)" then
                                        tell w to select
                                        tell t to select
                                        select s
                                        tell s to write text "\(escaped)" newline NO
                                        return "ok"
                                    end if
                                end try
                            end repeat
                        end repeat
                    end repeat
                end try
                return "not_found"
            end tell
            """
            let r = runScript(script)
            if r != "ok" {
                logger.warn("iTerm type fallback to clipboard")
                fallbackClipboard(text)
            }
            return
        }
        // 其他终端 → 复制到剪贴板,提示用户 ⌘V + Enter
        fallbackClipboard(text)
    }

    private static func fallbackClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        logger.info("answer copied to clipboard: \(text.prefix(40))")
    }
}
