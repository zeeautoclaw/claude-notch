import Foundation

public enum Paths {
    /// IPC socket path — communication between the relay and the main app.
    public static var socket: String {
        if let p = ProcessInfo.processInfo.environment["CLAUDE_NOTCH_SOCKET"] {
            return p
        }
        let tmp = NSTemporaryDirectory()
        let uid = getuid()
        return "\(tmp)claude-notch-\(uid).sock"
    }

    /// Claude Code settings file.
    public static var claudeSettings: String {
        let home = NSHomeDirectory()
        return "\(home)/.claude/settings.json"
    }

    /// Settings backup (used by SettingsInjector).
    public static var claudeSettingsBackup: String {
        return claudeSettings + ".claude-notch.bak"
    }

    /// Where Always Allow rules are stored.
    public static var rules: String {
        let home = NSHomeDirectory()
        let dir = "\(home)/Library/Application Support/ClaudeNotch"
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true
        )
        return "\(dir)/rules.json"
    }

    /// Log path.
    public static var logFile: String {
        let home = NSHomeDirectory()
        let dir = "\(home)/Library/Logs/ClaudeNotch"
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true
        )
        return "\(dir)/app.log"
    }
}
