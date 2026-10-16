import Foundation

/// 把 hook 请求路由给 ApprovalQueue / RulesStore / SessionStore。
public final class HookServer {
    private let server: UnixSocketServer
    private let queue: ApprovalQueue
    private let rules: RulesStore
    private let sessions: SessionStore
    private let timeout: TimeInterval
    private let logger = Logger(tag: "server")

    public init(
        socketPath: String = Paths.socket,
        queue: ApprovalQueue,
        rules: RulesStore,
        sessions: SessionStore,
        timeout: TimeInterval = 50
    ) {
        self.queue = queue
        self.rules = rules
        self.sessions = sessions
        self.timeout = timeout
        self.server = UnixSocketServer(path: socketPath, handler: { _ in Data() })
        self.server.handler = { [weak self] data in
            self?.handle(data) ?? Data(#"{"continue":true}"#.utf8)
        }
    }

    public func start() throws {
        try server.start()
        logger.info("server started at \(Paths.socket)")
    }

    public func stop() {
        server.stop()
    }

    private func handle(_ data: Data) -> Data {
        guard let event = try? HookCodec.decoder.decode(HookEvent.self, from: data) else {
            // 读不懂的请求:原文里像有危险命令就拒绝,否则放行,免得卡住正常工作
            let raw = String(decoding: data, as: UTF8.self)
            if Safety.isDangerousCommand(raw) {
                logger.warn("decode HookEvent failed, looks dangerous, denying")
                return encode(HookResponse(id: UUID(), decision: .deny, reason: "unreadable request with dangerous command"))
            }
            logger.warn("decode HookEvent failed, allowing")
            return defaultAllow(id: UUID())
        }

        logger.info("event=\(event.event) tool=\(event.toolName ?? "-") cmd=\(event.commandPreview.prefix(80))")

        switch event.eventType {
        case .preToolUse:
            let dangerous = Safety.isDangerous(event)
            // 命中规则 → 自动放行;危险命令永远不走自动放行,必须弹卡片
            if !dangerous && rules.matches(event) {
                logger.info("auto-allow by rule")
                sessions.ingest(event, isWaiting: false)
                return encode(HookResponse(id: event.id, decision: .allow, reason: "rule match"))
            }
            if dangerous && rules.matches(event) {
                logger.info("rule match ignored: dangerous command")
            }
            // 入队 = waiting 状态
            sessions.ingest(event, isWaiting: true)
            let req = ApprovalRequest(event: event)
            queue.enqueue(req)
            _ = req.wait(timeout: .now() + timeout)
            if !req.isResolved {
                // 没人点:危险命令默认拒绝,普通命令默认放行
                let decision: Decision = dangerous ? .denyTool : .allow
                let reason = dangerous
                    ? "这条命令有风险,用户约 50 秒内没有批准,已自动拒绝。不要重试同一条命令;换一种更安全的做法,或者先问用户。"
                    : "timeout"
                logger.warn("server timeout, \(dangerous ? "denying dangerous command" : "allowing")")
                req.complete(with: HookResponse(id: req.id, decision: decision, reason: reason))
                queue.resolve(id: req.id, decision: decision, reason: reason)
            }
            sessions.markResolved(event)
            // 用户恰好在超时那一刻点了按钮时,以用户的选择为准
            return encode(req.wait(timeout: .now()))

        case .userPromptSubmit, .stop, .sessionStart, .sessionEnd,
             .postToolUse, .notification, .unknown:
            sessions.ingest(event)
            return defaultAllow(id: event.id)
        }
    }

    private func encode(_ response: HookResponse) -> Data {
        (try? HookCodec.encoder.encode(response))
            ?? Data(#"{"continue":true}"#.utf8)
    }

    private func defaultAllow(id: UUID) -> Data {
        encode(HookResponse(id: id, decision: .allow))
    }
}
