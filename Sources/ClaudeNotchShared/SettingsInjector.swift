import Foundation

/// Injects / removes Claude Notch hook commands in ~/.claude/settings.json.
/// Follows the Claude Code hooks settings schema:
/// {
///   "hooks": {
///     "PreToolUse": [
///       { "matcher": "*", "hooks": [{"type":"command","command":"/path/to/relay ..."}] }
///     ],
///     ...
///   }
/// }
public final class SettingsInjector {
    public let settingsPath: String
    public let backupPath: String
    public let relayPath: String

    /// Event types we inject.
    public static let events: [String] = [
        "PreToolUse",
        "Notification",
        "Stop",
        "UserPromptSubmit",
    ]

    public init(
        settingsPath: String = Paths.claudeSettings,
        backupPath: String = Paths.claudeSettingsBackup,
        relayPath: String
    ) {
        self.settingsPath = settingsPath
        self.backupPath = backupPath
        self.relayPath = relayPath
    }

    // MARK: Public API

    public func install() throws {
        let parentDir = (settingsPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: parentDir, withIntermediateDirectories: true
        )

        var root = try loadSettings()

        // Back up the original file (only on the first install)
        if !FileManager.default.fileExists(atPath: backupPath),
           FileManager.default.fileExists(atPath: settingsPath) {
            try FileManager.default.copyItem(atPath: settingsPath, toPath: backupPath)
        }

        for event in Self.events {
            root = injectEvent(root: root, event: event)
        }

        try writeSettings(root)
    }

    public func uninstall() throws {
        guard FileManager.default.fileExists(atPath: settingsPath) else { return }
        var root = try loadSettings()
        for event in Self.events {
            root = removeEvent(root: root, event: event)
        }
        try writeSettings(root)
    }

    public func isInstalled() throws -> Bool {
        guard FileManager.default.fileExists(atPath: settingsPath) else { return false }
        let root = try loadSettings()
        guard let hooks = root["hooks"] as? [String: Any],
              let entries = hooks["PreToolUse"] as? [[String: Any]] else {
            return false
        }
        return entries.contains(where: entryBelongsToUs)
    }

    // MARK: Internal helpers

    func loadSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsPath),
              let data = FileManager.default.contents(atPath: settingsPath),
              !data.isEmpty else {
            return [:]
        }
        let obj = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return (obj as? [String: Any]) ?? [:]
    }

    func writeSettings(_ root: [String: Any]) throws {
        let data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )
        // JSONSerialization escapes `/` as `\/` by default, which is hard to read and Claude does not need it
        var raw = String(data: data, encoding: .utf8) ?? ""
        raw = raw.replacingOccurrences(of: "\\/", with: "/")
        try raw.write(to: URL(fileURLWithPath: settingsPath), atomically: true, encoding: .utf8)
    }

    func injectEvent(root: [String: Any], event: String) -> [String: Any] {
        var root = root
        var hooks = (root["hooks"] as? [String: Any]) ?? [:]
        var entries = (hooks[event] as? [[String: Any]]) ?? []

        // Remove old entries (matched by relayPath)
        entries.removeAll(where: entryBelongsToUs)

        // Add new ones
        let entry: [String: Any] = [
            "matcher": "*",
            "hooks": [
                [
                    "type": "command",
                    "command": "\"\(relayPath)\" --event \(event)",
                ]
            ],
        ]
        entries.append(entry)

        hooks[event] = entries
        root["hooks"] = hooks
        return root
    }

    func removeEvent(root: [String: Any], event: String) -> [String: Any] {
        var root = root
        guard var hooks = root["hooks"] as? [String: Any] else { return root }
        guard var entries = hooks[event] as? [[String: Any]] else { return root }
        entries.removeAll(where: entryBelongsToUs)
        if entries.isEmpty {
            hooks.removeValue(forKey: event)
        } else {
            hooks[event] = entries
        }
        if hooks.isEmpty {
            root.removeValue(forKey: "hooks")
        } else {
            root["hooks"] = hooks
        }
        return root
    }

    private func entryBelongsToUs(_ entry: [String: Any]) -> Bool {
        guard let inner = entry["hooks"] as? [[String: Any]] else { return false }
        return inner.contains { hook in
            guard let cmd = hook["command"] as? String else { return false }
            return cmd.contains(relayPath)
        }
    }
}
