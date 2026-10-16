import Foundation

/// 一次待审批/待回应的 hook 请求。
public final class ApprovalRequest: Identifiable, ObservableObject {
    public let id: UUID
    public let event: HookEvent
    private let semaphore = DispatchSemaphore(value: 0)
    private var response: HookResponse?
    private let lock = NSLock()
    private var resolved = false

    public init(event: HookEvent) {
        self.id = event.id
        self.event = event
    }

    /// 调用方在后台线程阻塞等待。
    public func wait(timeout: DispatchTime = .distantFuture) -> HookResponse {
        _ = semaphore.wait(timeout: timeout)
        lock.lock(); defer { lock.unlock() }
        return response ?? HookResponse(id: id, decision: .allow, reason: "fallback")
    }

    public func complete(with response: HookResponse) {
        lock.lock()
        if !resolved {
            self.response = response
            resolved = true
            semaphore.signal()
        }
        lock.unlock()
    }

    public var isResolved: Bool {
        lock.lock(); defer { lock.unlock() }
        return resolved
    }
}

/// 队列。UI 总是看 queue.first。
public final class ApprovalQueue: ObservableObject {
    @Published public private(set) var queue: [ApprovalRequest] = []

    public init() {}

    public var current: ApprovalRequest? { queue.first }
    public var waiting: Int { max(0, queue.count - 1) }

    public func enqueue(_ request: ApprovalRequest) {
        DispatchQueue.main.async {
            self.queue.append(request)
        }
    }

    public func resolveCurrent(decision: Decision, reason: String? = nil) {
        DispatchQueue.main.async {
            guard !self.queue.isEmpty else { return }
            let req = self.queue.removeFirst()
            Logger(tag: "queue").info("card resolved from UI: \(decision.rawValue) tool=\(req.event.toolName ?? "-") cmd=\(req.event.commandPreview.prefix(60))")
            req.complete(with: HookResponse(id: req.id, decision: decision, reason: reason))
        }
    }

    public func resolve(id: UUID, decision: Decision, reason: String? = nil) {
        DispatchQueue.main.async {
            if let idx = self.queue.firstIndex(where: { $0.id == id }) {
                let req = self.queue.remove(at: idx)
                req.complete(with: HookResponse(id: req.id, decision: decision, reason: reason))
            }
        }
    }
}
