import Foundation
import AppKit

/// Uses AppleScript to bring the terminal forward and jump to the matching session/tab.
public enum TerminalJumper {
    private static let logger = Logger(tag: "jumper")

    /// Picks a strategy from the hook event's env and runs it. Failures are only logged.
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
        // The iTerm2 session unique ID contains the last part of ITERM_SESSION_ID
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
        // Terminal.app does not expose session IDs, so only activate it
        let script = """
        tell application "Terminal"
            activate
        end tell
        """
        runScript(script)
    }

    // MARK: - Common

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

    // MARK: - Type text into an iTerm session (auto-answer AskUserQuestion)

    /// Types text into the given iTerm session (same as typing in the terminal).
    /// Falls back to the clipboard + a paste hint if it is not iTerm or the session is not found.
    public static func type(text: String, into event: HookEvent) {
        // We send \r (CR) ourselves as Enter — the Claude Code TUI needs CR.
        // Escape for an AppleScript string literal: \, "
        // Real \n / \r become the AppleScript literal \r (the Claude TUI wants CR).
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r\n", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\r")
            .replacingOccurrences(of: "\r", with: "\\r")

        if event.env["TERM_PROGRAM"] == "iTerm.app",
           let sid = event.env["ITERM_SESSION_ID"] {
            let cleanSid = sid.split(separator: ":").last.map(String.init) ?? sid
            // newline NO: we control line endings; do not let iTerm append \n
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
        // Other terminals → copy to clipboard and ask the user to press ⌘V + Enter
        fallbackClipboard(text)
    }

    private static func fallbackClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        logger.info("answer copied to clipboard: \(text.prefix(40))")
    }
}
