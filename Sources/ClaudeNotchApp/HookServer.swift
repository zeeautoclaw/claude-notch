import Foundation

/// Routes hook requests to ApprovalQueue / RulesStore / SessionStore.
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
            // Unreadable request: deny if the raw text looks dangerous, otherwise allow so work is not blocked
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
            // Rule match → auto-allow; dangerous commands never auto-allow and always show a card
            if !dangerous && rules.matches(event) {
                logger.info("auto-allow by rule")
                sessions.ingest(event, isWaiting: false)
                return encode(HookResponse(id: event.id, decision: .allow, reason: "rule match"))
            }
            if dangerous && rules.matches(event) {
                logger.info("rule match ignored: dangerous command")
            }
            // Enqueue = waiting state
            sessions.ingest(event, isWaiting: true)
            let req = ApprovalRequest(event: event)
            queue.enqueue(req)
            _ = req.wait(timeout: .now() + timeout)
            if !req.isResolved {
                // Nobody answered: deny dangerous commands, allow everything else
                let decision: Decision = dangerous ? .denyTool : .allow
                let reason = dangerous
                    ? "This command looks risky and the user did not approve it within about 50 seconds, so it was denied automatically. Do not retry the same command; use a safer approach or ask the user first."
                    : "timeout"
                logger.warn("server timeout, \(dangerous ? "denying dangerous command" : "allowing")")
                req.complete(with: HookResponse(id: req.id, decision: decision, reason: reason))
                queue.resolve(id: req.id, decision: decision, reason: reason)
            }
            sessions.markResolved(event)
            // If the user clicked right at the timeout, their choice wins
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
