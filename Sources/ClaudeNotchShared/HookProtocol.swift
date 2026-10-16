import Foundation

/// Claude Code hook 事件类型。我们关心的子集。
public enum HookEventType: String, Codable, Sendable {
    case preToolUse = "PreToolUse"
    case postToolUse = "PostToolUse"
    case userPromptSubmit = "UserPromptSubmit"
    case notification = "Notification"
    case stop = "Stop"
    case sessionStart = "SessionStart"
    case sessionEnd = "SessionEnd"
    case unknown
}

/// relay → app: 一次 hook 调用的完整描述。
public struct HookEvent: Codable, Sendable {
    public let id: UUID
    public let event: String           // 原始字符串，便于转发未知事件
    public let payload: AnyCodable     // Claude 传来的原始 payload
    public let env: [String: String]   // ITERM_SESSION_ID, TERM_PROGRAM, PWD 等
    public let cwd: String
    public let timestamp: Date
    public let ppid: Int?              // relay 的父进程 PID (≈ claude 进程)

    public init(
        id: UUID = UUID(),
        event: String,
        payload: AnyCodable,
        env: [String: String],
        cwd: String,
        timestamp: Date = Date(),
        ppid: Int? = nil
    ) {
        self.id = id
        self.event = event
        self.payload = payload
        self.env = env
        self.cwd = cwd
        self.timestamp = timestamp
        self.ppid = ppid
    }

    public var eventType: HookEventType {
        HookEventType(rawValue: event) ?? .unknown
    }

    // MARK: 解析快捷方法

    public var toolName: String? {
        payload["tool_name"]?.stringValue ?? payload["tool"]?.stringValue
    }

    public var toolInput: AnyCodable? {
        payload["tool_input"] ?? payload["input"]
    }

    public var commandPreview: String {
        if let cmd = toolInput?["command"]?.stringValue { return cmd }
        if let path = toolInput?["file_path"]?.stringValue { return path }
        if let input = toolInput {
            return input.displayString
        }
        return ""
    }

    public var sessionFingerprint: String {
        env["ITERM_SESSION_ID"]
            ?? env["TERM_SESSION_ID"]
            ?? env["TMUX_PANE"]
            ?? "\(env["TERM_PROGRAM"] ?? "unknown"):\(cwd)"
    }
}

/// app → relay: 决策结果。
public enum Decision: String, Codable, Sendable {
    case allow      // 等价于 {"continue":true}
    case deny       // {"continue":false, "reason": ...}
    case denyTool   // 只拦下这一条命令,Claude 收到原因后可以继续干别的 (超时自动拒绝用)
    case askUser    // 用户已在终端处理（点了 Continue in Terminal）
}

public struct HookResponse: Codable, Sendable {
    public let id: UUID
    public let decision: Decision
    public let reason: String?

    public init(id: UUID, decision: Decision, reason: String? = nil) {
        self.id = id
        self.decision = decision
        self.reason = reason
    }

    /// 转换为 Claude Code hook 期望的 stdout JSON。
    /// PreToolUse 事件需要用 hookSpecificOutput.permissionDecision 才能跳过原生审批。
    public func toClaudeJSON(eventName: String? = nil) -> String {
        let isPreToolUse = (eventName == "PreToolUse")
        switch decision {
        case .allow:
            if isPreToolUse {
                return #"{"continue":true,"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"Approved via Claude Notch"}}"#
            }
            return #"{"continue":true}"#
        case .askUser:
            // 让 Claude Code 自己继续走原生流程 (用户已 / 将到终端处理)
            return #"{"continue":true}"#
        case .deny:
            let reasonStr = reason ?? "Denied by Claude Notch"
            let escaped = reasonStr
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
            if isPreToolUse {
                return "{\"continue\":false,\"stopReason\":\"\(escaped)\",\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"\(escaped)\"}}"
            }
            return "{\"continue\":false,\"stopReason\":\"\(escaped)\"}"
        case .denyTool:
            let escaped = (reason ?? "Denied by Claude Notch")
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
            if isPreToolUse {
                return "{\"continue\":true,\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"\(escaped)\"}}"
            }
            return #"{"continue":true}"#
        }
    }
}

/// 编/解码工具。
public enum HookCodec {
    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
