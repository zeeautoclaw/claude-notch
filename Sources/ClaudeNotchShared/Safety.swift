import Foundation

/// Dangerous command detection.
/// Only looks at the `command` field of the tool input (Bash and terminal tools) and matches whole words / command positions,
/// not plain substrings — previously "dd " matched the "add " in ordinary text.
public enum Safety {
    /// Where a command can start: beginning of line, or after whitespace / ; & | ( `.
    private static let cmdStart = #"(?:^|[\s;&|(`])"#

    /// Each rule is a regular expression matched against the lowercased command.
    static let dangerousPatterns: [String] = [
        cmdStart + #"sudo\b"#,
        cmdStart + #"dd\s+\S"#,
        cmdStart + #"mkfs(\.\w+)?\b"#,
        cmdStart + #"diskutil\b"#,
        #"\bgit\s+push\b[^;&|]*\s(--force\b|--force-with-lease\b|-f\b)"#,
        #"\bgit\s+reset\s+--hard\b"#,
        #"\bchmod\s+-r\s+777\b"#,
        #":\(\)\s*\{"#,
        #">\s*/dev/(r?disk|sd)"#,
    ]

    public static func isDangerous(_ event: HookEvent) -> Bool {
        guard let cmd = event.toolInput?["command"]?.stringValue else { return false }
        return isDangerousCommand(cmd)
    }

    public static func isDangerousCommand(_ raw: String) -> Bool {
        let cmd = raw.lowercased()
        if dangerousPatterns.contains(where: { matches(cmd, $0) }) { return true }
        if hasDangerousRm(cmd) { return true }
        if usesNetworkTool(cmd) && !isLocalhostOnly(cmd) { return true }
        return false
    }

    // MARK: - rm

    /// rm with both "recursive" and "force", or targeting the root / home folder itself.
    private static func hasDangerousRm(_ cmd: String) -> Bool {
        // Treat quotes, brackets and colons as spaces so "rm inside raw JSON text is still caught
        let cleaned = String(cmd.map { "\"'{}()[],:".contains($0) ? " " : $0 })
        for segment in commandSegments(cleaned) {
            let words = segment.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard let idx = words.firstIndex(where: { $0 == "rm" || $0.hasSuffix("/rm") }) else { continue }
            let args = words[(idx + 1)...]
            var recursive = false, force = false
            for a in args {
                if a == "--recursive" { recursive = true }
                else if a == "--force" { force = true }
                else if a.hasPrefix("-") && !a.hasPrefix("--") {
                    if a.contains("r") { recursive = true }
                    if a.contains("f") { force = true }
                }
                if ["/", "/*", "~", "~/", "~/*", "$home"].contains(a) { return true }
            }
            if recursive && force { return true }
        }
        return false
    }

    /// Split into sub-commands on ; && || |.
    private static func commandSegments(_ cmd: String) -> [String] {
        cmd.components(separatedBy: CharacterSet(charactersIn: ";&|\n"))
    }

    // MARK: - Network downloads

    private static func usesNetworkTool(_ cmd: String) -> Bool {
        matches(cmd, cmdStart + #"(curl|wget)\b"#)
    }

    /// Whether every download target is this machine.
    /// Targets = all http(s):// URLs + bare addresses starting with localhost / 127.0.0.1 etc.;
    /// if no target can be recognized (e.g. `curl example.com`) it does not count as local.
    private static func isLocalhostOnly(_ cmd: String) -> Bool {
        let localHosts: Set<String> = ["localhost", "127.0.0.1", "0.0.0.0", "::1", "[::1]"]
        var hosts: [String] = []

        let urlPattern = #"https?://([^/\s'\"]+)"#
        if let regex = try? NSRegularExpression(pattern: urlPattern) {
            for m in regex.matches(in: cmd, range: NSRange(cmd.startIndex..., in: cmd)) {
                if let r = Range(m.range(at: 1), in: cmd) { hosts.append(hostOnly(String(cmd[r]))) }
            }
        }
        for word in cmd.split(whereSeparator: { $0 == " " || $0 == "\t" }) {
            let w = word.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if w.hasPrefix("http://") || w.hasPrefix("https://") { continue }
            let host = hostOnly(String(w.split(separator: "/").first ?? ""))
            if localHosts.contains(host) { hosts.append(host) }
        }
        return !hosts.isEmpty && hosts.allSatisfy { localHosts.contains($0) }
    }

    /// "localhost:8787" → "localhost";"[::1]:80" → "[::1]"
    private static func hostOnly(_ hostPort: String) -> String {
        if hostPort.hasPrefix("[") , let end = hostPort.firstIndex(of: "]") {
            return String(hostPort[...end])
        }
        return hostPort.split(separator: ":").first.map(String.init) ?? hostPort
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }

    // MARK: - Rule helpers

    /// Extracts the "first word" of a bash command — used for fine-grained rules.
    /// "ls -la /tmp" → "ls";"/usr/bin/cat foo" → "cat"
    public static func firstWord(of cmd: String) -> String? {
        let trimmed = cmd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.split(separator: " ").first else { return nil }
        let s = String(first)
        if s.contains("/") {
            return String(s.split(separator: "/").last ?? Substring(s))
        }
        return s
    }

    /// Command prefixes that are always read-only and safe to Always Allow.
    public static let safeReadOnlyCommands: Set<String> = [
        "ls", "cat", "head", "tail", "grep", "rg", "find",
        "pwd", "echo", "wc", "stat", "file", "tree",
        "git status", "git diff", "git log", "git branch", "git show",
        "which", "type",
    ]
}
