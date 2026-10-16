import Foundation

/// 危险命令检测。
/// 只看工具输入里的 `command` 字段 (Bash、终端类工具),按整词/命令位置匹配,
/// 不再用简单子串 — 以前 "dd " 会命中普通英文里的 "add "。
public enum Safety {
    /// 命令分隔位置:行首,或空白 / ; & | ( ` 之后。
    private static let cmdStart = #"(?:^|[\s;&|(`])"#

    /// 每条规则是一段正则 (对小写后的命令匹配)。
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

    /// rm 同时带"递归"和"强制",或者目标是根目录 / 家目录本身。
    private static func hasDangerousRm(_ cmd: String) -> Bool {
        // 引号、括号、冒号当空白,这样原始 JSON 文本里的 "rm 也能认出来
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

    /// 按 ; && || | 切成一条条子命令。
    private static func commandSegments(_ cmd: String) -> [String] {
        cmd.components(separatedBy: CharacterSet(charactersIn: ";&|\n"))
    }

    // MARK: - 网络下载

    private static func usesNetworkTool(_ cmd: String) -> Bool {
        matches(cmd, cmdStart + #"(curl|wget)\b"#)
    }

    /// 下载目标是否全部是本机。
    /// 目标 = 所有 http(s):// 地址 + 以 localhost / 127.0.0.1 等开头的裸地址;
    /// 一个目标都认不出 (比如 `curl example.com`) 时不算本机。
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

    // MARK: - 规则辅助

    /// 提取 bash 命令的"第一个词" — 用于细粒度规则。
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

    /// 一些总是只读、可放心 Always Allow 的命令前缀建议。
    public static let safeReadOnlyCommands: Set<String> = [
        "ls", "cat", "head", "tail", "grep", "rg", "find",
        "pwd", "echo", "wc", "stat", "file", "tree",
        "git status", "git diff", "git log", "git branch", "git show",
        "which", "type",
    ]
}
