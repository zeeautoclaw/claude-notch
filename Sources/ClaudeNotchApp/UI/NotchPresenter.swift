import AppKit
import SwiftUI
import Combine

/// Floating panel centered at the top of the screen. Wraps an NSPanel with SwiftUI content.
public final class NotchPresenter: NSObject {
    private var panel: NSPanel?
    private var host: NSHostingView<NotchRootView>?
    private let queue: ApprovalQueue
    private let rules: RulesStore
    private var cancellable: AnyCancellable?
    private let logger = Logger(tag: "notch")

    public init(queue: ApprovalQueue, rules: RulesStore) {
        self.queue = queue
        self.rules = rules
        super.init()
        observe()
    }

    private func observe() {
        cancellable = queue.$queue
            .receive(on: DispatchQueue.main)
            .sink { [weak self] q in
                guard let self else { return }
                if q.isEmpty {
                    self.hide()
                } else {
                    self.show()
                }
            }
    }

    private func ensurePanel() {
        if panel != nil { return }
        let frame = Self.targetFrame()
        let p = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.isMovable = false
        p.alphaValue = 0
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = true

        let host = NSHostingView(
            rootView: NotchRootView(queue: queue, rules: rules,
                                    onJumpTerminal: { [weak self] in self?.handleJumpTerminal() })
        )
        host.frame = NSRect(origin: .zero, size: frame.size)
        host.autoresizingMask = [.width, .height]
        p.contentView = host

        self.host = host
        panel = p
    }

    public func show() {
        ensurePanel()
        guard let p = panel else { return }
        // Position for the current card size first; once SwiftUI has updated, position again at the real size
        p.setFrame(Self.targetFrame(for: fittingSize()), display: false)
        p.orderFrontRegardless()
        DispatchQueue.main.async { [weak self] in
            guard let self, let p = self.panel else { return }
            p.setFrame(Self.targetFrame(for: self.fittingSize()), display: true)
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            p.animator().alphaValue = 1.0
        }
    }

    public func hide() {
        guard let p = panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            p.animator().alphaValue = 0
        }, completionHandler: {
            p.orderOut(nil)
        })
    }

    public func handleJumpTerminal() {
        guard let req = queue.current else { return }
        TerminalJumper.jump(to: req.event)
    }

    /// Real size of the card (including the transparent margin); a default before there is content.
    private func fittingSize() -> NSSize {
        guard let host else { return Self.defaultSize }
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        return size.width > 1 && size.height > 1 ? size : Self.defaultSize
    }

    public static let defaultSize = NSSize(width: 428, height: 260)

    public static func targetFrame(for size: NSSize = defaultSize) -> NSRect {
        let width = size.width
        let height = size.height
        guard let screen = NSScreen.main else {
            return NSRect(x: 100, y: 100, width: width, height: height)
        }
        let visible = screen.visibleFrame
        let x = visible.midX - width / 2
        let y = visible.maxY - height
        return NSRect(x: x, y: y, width: width, height: height)
    }
}

/// SwiftUI root view — routes queue.first to the matching card.
struct NotchRootView: View {
    @ObservedObject var queue: ApprovalQueue
    @ObservedObject var rules: RulesStore
    let onJumpTerminal: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let req = queue.current {
                cardFor(req)
                    .transition(.scale(scale: 0.94, anchor: .top).combined(with: .opacity))
                    .id(req.id)
            }
        }
        .fixedSize()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.36, dampingFraction: 0.82), value: queue.current?.id)
    }

    @ViewBuilder
    private func cardFor(_ req: ApprovalRequest) -> some View {
        let waiting = queue.waiting
        let event = req.event

        if event.toolName == "ExitPlanMode" {
            PlanCard(
                request: req,
                waiting: waiting,
                onResolve: { queue.resolveCurrent(decision: $0) }
            )
        } else if event.toolName == "AskUserQuestion" {
            QuestionChoiceCard(
                request: req,
                waiting: waiting,
                onChoose: { answer in
                    // 1) Let PreToolUse through → AskUserQuestion starts and waits for input
                    queue.resolveCurrent(decision: .allow)
                    // 2) Wait 350 ms for the TUI to draw the options, then type the number + CR (the TUI needs \r for Enter)
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.35) {
                        TerminalJumper.type(text: answer + "\r", into: event)
                    }
                },
                onCancel: {
                    queue.resolveCurrent(decision: .deny, reason: "User canceled")
                },
                onJumpTerminal: {
                    queue.resolveCurrent(decision: .askUser)
                    TerminalJumper.jump(to: event)
                }
            )
        } else if event.eventType == .notification || event.eventType == .userPromptSubmit {
            QuestionCard(
                request: req,
                waiting: waiting,
                onResolve: { queue.resolveCurrent(decision: $0) },
                onJumpTerminal: onJumpTerminal
            )
        } else {
            ApprovalCard(
                request: req,
                waiting: waiting,
                rules: rules,
                onResolve: { queue.resolveCurrent(decision: $0) },
                onJumpTerminal: onJumpTerminal
            )
        }
    }
}
