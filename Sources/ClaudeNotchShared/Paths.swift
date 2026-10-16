import Foundation

public enum Paths {
    /// IPC socket 路径 — relay 与主 app 之间的通信。
    public static var socket: String {
        if let p = ProcessInfo.processInfo.environment["CLAUDE_NOTCH_SOCKET"] {
            return p
        }
        let tmp = NSTemporaryDirectory()
        let uid = getuid()
        return "\(tmp)claude-notch-\(uid).sock"
    }

    /// Claude Code 配置文件。
    public static var claudeSettings: String {
        let home = NSHomeDirectory()
        return "\(home)/.claude/settings.json"
    }

    /// 配置文件备份(由 SettingsInjector 使用)。
    public static var claudeSettingsBackup: String {
        return claudeSettings + ".claude-notch.bak"
    }

    /// Always Allow 规则持久化路径。
    public static var rules: String {
        let home = NSHomeDirectory()
        let dir = "\(home)/Library/Application Support/ClaudeNotch"
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true
        )
        return "\(dir)/rules.json"
    }

    /// 日志路径。
    public static var logFile: String {
        let home = NSHomeDirectory()
        let dir = "\(home)/Library/Logs/ClaudeNotch"
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true
        )
        return "\(dir)/app.log"
    }
}
