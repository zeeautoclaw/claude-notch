import Foundation

/// Claude Code hook event types — the subset we care about.
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

/// relay → app: full description of one hook call.
public struct HookEvent: Codable, Sendable {
    public let id: UUID
    public let event: String           // raw string, so unknown events can be forwarded
    public let payload: AnyCodable     // raw payload from Claude
    public let env: [String: String]   // ITERM_SESSION_ID, TERM_PROGRAM, PWD, etc.
    public let cwd: String
    public let timestamp: Date
    public let ppid: Int?              // relay's parent PID (≈ the claude process)

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

    // MARK: Parsing helpers

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

/// app → relay: the decision.
public enum Decision: String, Codable, Sendable {
    case allow      // equivalent to {"continue":true}
    case deny       // {"continue":false, "reason": ...}
    case denyTool   // block only this command; Claude gets the reason and can keep working (used for timeout auto-deny)
    case askUser    // the user is handling it in the terminal (clicked "Go to terminal")
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

    /// Converts to the stdout JSON Claude Code expects from a hook.
    /// PreToolUse needs hookSpecificOutput.permissionDecision to skip the native prompt.
    public func toClaudeJSON(eventName: String? = nil) -> String {
        let isPreToolUse = (eventName == "PreToolUse")
        switch decision {
        case .allow:
            if isPreToolUse {
                return #"{"continue":true,"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"Approved via Claude Notch"}}"#
            }
            return #"{"continue":true}"#
        case .askUser:
            // Let Claude Code continue with its own flow (the user is / will be in the terminal)
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

/// Encoding/decoding helpers.
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
