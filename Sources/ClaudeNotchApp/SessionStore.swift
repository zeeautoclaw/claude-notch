import Foundation
import SwiftUI

public enum SessionStatus: String, Codable {
    case running
    case waiting   // PreToolUse 等待用户审批
    case done
}

public struct SessionInfo: Identifiable, Equatable {
    public var id: String                 // sessionFingerprint
    public var title: String              // 项目目录名 / 用户标题
    public var lastUserPrompt: String     // 最近一次 UserPromptSubmit
    public var lastToolName: String?      // 最近一次工具名
    public var lastToolPreview: String?   // 最近一次命令片段
    public var status: SessionStatus
    public var startedAt: Date
    public var lastActivityAt: Date
    public var doneAt: Date?
    public var termProgram: String
    public var cwd: String
    public var env: [String: String]      // 留 ITERM_SESSION_ID 等用于跳转
    public var claudePID: Int?            // relay 的 ppid,用来 SIGTERM

    public var isDone: Bool { status == .done }
}

/// 跨 session 状态总览。HookServer 把所有事件喂进来,UI 订阅展示。
public final class SessionStore: ObservableObject {
    @Published public private(set) var sessions: [String: SessionInfo] = [:]
    private let logger = Logger(tag: "sessions")

    /// 完成 30 分钟后自动从列表移除。
    public var doneRetention: TimeInterval = 30 * 60

    public init() {
        // 定时清理已完成、已超期的 session
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.gc()
        }
    }

    public var sortedActive: [SessionInfo] {
        sessions.values
            .sorted { lhs, rhs in
                // running > waiting > done; 同状态按 lastActivityAt 降序
                if lhs.status != rhs.status {
                    return rank(lhs.status) < rank(rhs.status)
                }
                return lhs.lastActivityAt > rhs.lastActivityAt
            }
    }

    private func rank(_ s: SessionStatus) -> Int {
        switch s {
        case .waiting: return 0
        case .running: return 1
        case .done:    return 2
        }
    }

    // MARK: - 事件入口

    public func ingest(_ event: HookEvent, isWaiting: Bool = false) {
        DispatchQueue.main.async {
            self._ingest(event, isWaiting: isWaiting)
        }
    }

    private func _ingest(_ event: HookEvent, isWaiting: Bool) {
        let id = event.sessionFingerprint
        let now = Date()

        var info = sessions[id] ?? SessionInfo(
            id: id,
            title: defaultTitle(cwd: event.cwd),
            lastUserPrompt: "",
            lastToolName: nil,
            lastToolPreview: nil,
            status: .running,
            startedAt: now,
            lastActivityAt: now,
            doneAt: nil,
            termProgram: event.env["TERM_PROGRAM"] ?? "Unknown",
            cwd: event.cwd,
            env: event.env,
            claudePID: event.ppid
        )
        info.lastActivityAt = now
        info.env = event.env  // 持续刷新 (TERM_SESSION_ID 可能变)
        info.cwd = event.cwd
        if info.termProgram == "Unknown" {
            info.termProgram = event.env["TERM_PROGRAM"] ?? "Unknown"
        }
        if let p = event.ppid { info.claudePID = p }

        switch event.eventType {
        case .sessionStart:
            info.status = .running
            info.startedAt = now
            info.doneAt = nil
        case .userPromptSubmit:
            if let prompt = event.payload["prompt"]?.stringValue {
                info.lastUserPrompt = prompt
            } else if let prompt = event.payload["text"]?.stringValue {
                info.lastUserPrompt = prompt
            }
            info.status = .running
        case .preToolUse:
            info.lastToolName = event.toolName
            info.lastToolPreview = event.commandPreview
            info.status = isWaiting ? .waiting : .running
        case .postToolUse:
            info.status = .running
        case .stop, .sessionEnd:
            info.status = .done
            info.doneAt = now
        case .notification, .unknown:
            break
        }

        sessions[id] = info
    }

    /// 标记一次 PreToolUse 等待状态结束(收到决策时)。
    public func markResolved(_ event: HookEvent) {
        DispatchQueue.main.async {
            guard var info = self.sessions[event.sessionFingerprint] else { return }
            if info.status == .waiting {
                info.status = .running
                info.lastActivityAt = Date()
                self.sessions[event.sessionFingerprint] = info
            }
        }
    }

    public func remove(id: String) {
        DispatchQueue.main.async {
            self.sessions.removeValue(forKey: id)
        }
    }

    public func clearDone() {
        DispatchQueue.main.async {
            self.sessions = self.sessions.filter { $0.value.status != .done }
        }
    }

    private func gc() {
        DispatchQueue.main.async {
            let now = Date()
            self.sessions = self.sessions.filter { _, info in
                if let doneAt = info.doneAt {
                    return now.timeIntervalSince(doneAt) < self.doneRetention
                }
                return true
            }
        }
    }

    // MARK: - 标题推断

    private func defaultTitle(cwd: String) -> String {
        let parts = cwd.split(separator: "/")
        if let last = parts.last { return String(last) }
        return cwd
    }
}

// MARK: - 时长格式化

public enum DurationFormatter {
    public static func short(_ interval: TimeInterval) -> String {
        let s = Int(interval)
        if s < 60 { return "\(s)s" }
        let m = s / 60
        if m < 60 { return "\(m)m" }
        let h = m / 60
        if h < 24 { return "\(h)h" }
        let d = h / 24
        return "\(d)d"
    }
}
