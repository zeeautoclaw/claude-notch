import AppKit
import SwiftUI

@main
struct ClaudeNotchAppEntry {
    static func main() {
        let args = CommandLine.arguments
        if args.contains("--install-hooks") {
            cliInstall()
            exit(0)
        }
        if args.contains("--uninstall-hooks") {
            cliUninstall()
            exit(0)
        }
        if args.contains("--check-hooks") {
            cliCheck()
            return
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)

        // Catch SIGTERM/SIGINT and hand them to NSApp so cleanup runs
        installSignalHandler(SIGTERM)
        installSignalHandler(SIGINT)

        app.run()
    }

    static func defaultRelayPath() -> String {
        let exePath = Bundle.main.executablePath ?? CommandLine.arguments[0]
        let exeDir = (exePath as NSString).deletingLastPathComponent
        // .app/Contents/Helpers/ClaudeNotchRelay, or ClaudeNotchRelay next to the binary
        let helper = exeDir + "/../Helpers/ClaudeNotchRelay"
        if FileManager.default.fileExists(atPath: helper) {
            return URL(fileURLWithPath: helper).standardized.path
        }
        let sibling = exeDir + "/ClaudeNotchRelay"
        return sibling
    }

    static func cliInstall() {
        let inj = SettingsInjector(relayPath: defaultRelayPath())
        do {
            try inj.install()
            print("✅ Hooks installed in \(inj.settingsPath)")
            print("   relay: \(inj.relayPath)")
            print("   Backup: \(inj.backupPath)")
        } catch {
            FileHandle.standardError.write(Data("❌ Install failed: \(error)\n".utf8))
            exit(1)
        }
    }

    static func cliUninstall() {
        let inj = SettingsInjector(relayPath: defaultRelayPath())
        do {
            try inj.uninstall()
            print("✅ Hooks removed")
        } catch {
            FileHandle.standardError.write(Data("❌ Uninstall failed: \(error)\n".utf8))
            exit(1)
        }
    }

    static func cliCheck() {
        let inj = SettingsInjector(relayPath: defaultRelayPath())
        let installed = (try? inj.isInstalled()) ?? false
        print(installed ? "installed" : "not_installed")
        exit(installed ? 0 : 1)
    }

    private static func installSignalHandler(_ signo: Int32) {
        let src = DispatchSource.makeSignalSource(signal: signo, queue: .main)
        src.setEventHandler {
            NSApp.terminate(nil)
        }
        src.resume()
        // Keep the default handler from killing the process; dispatch handles it
        signal(signo, SIG_IGN)
        // Keep a reference to src — the DispatchSource stops when released
        SignalSourceKeeper.shared.add(src)
    }
}

private final class SignalSourceKeeper {
    static let shared = SignalSourceKeeper()
    private var sources: [DispatchSourceSignal] = []
    func add(_ s: DispatchSourceSignal) { sources.append(s) }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var server: HookServer?
    private var menuBar: MenuBarController?
    private var presenter: NotchPresenter?
    private var watcher: HookWatcher?
    let queue = ApprovalQueue()
    let rules = RulesStore()
    let sessions = SessionStore()
    private let logger = Logger(tag: "app")

    private var relayPath: String {
        // Prefer the relay inside the .app; otherwise use PATH
        let bundleHelper = Bundle.main.bundlePath + "/Contents/Helpers/ClaudeNotchRelay"
        if FileManager.default.fileExists(atPath: bundleHelper) {
            return bundleHelper
        }
        // Development: .build/release/ClaudeNotchRelay next to the binary
        let exePath = Bundle.main.executablePath ?? ""
        let exeDir = (exePath as NSString).deletingLastPathComponent
        let dev = "\(exeDir)/ClaudeNotchRelay"
        if FileManager.default.fileExists(atPath: dev) {
            return dev
        }
        return dev
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("===== Claude Notch starting =====")
        logger.info("relay path: \(relayPath)")
        logger.info("socket path: \(Paths.socket)")

        let injector = SettingsInjector(relayPath: relayPath)

        // Server
        let s = HookServer(queue: queue, rules: rules, sessions: sessions)
        do {
            try s.start()
            self.server = s
        } catch {
            logger.error("server start failed: \(error)")
            let a = NSAlert()
            a.messageText = "Claude Notch failed to start"
            a.informativeText = "Could not listen on the socket: \(error)"
            a.alertStyle = .critical
            a.runModal()
            NSApp.terminate(nil)
            return
        }

        // Notch UI
        presenter = NotchPresenter(queue: queue, rules: rules)

        // Hook self-healing watcher
        let w = HookWatcher(injector: injector)
        w.onRateLimited = {
            DispatchQueue.main.async {
                let a = NSAlert()
                a.messageText = "Hooks keep getting overwritten"
                a.informativeText = "Another tool keeps changing the hooks. Self-healing is paused. Check ~/.claude/settings.json, or uninstall and reinstall from the menu bar."
                a.alertStyle = .warning
                a.runModal()
            }
        }
        w.start()
        self.watcher = w

        // Menu bar + popover
        let mb = MenuBarController(
            injector: injector,
            sessions: sessions,
            rules: rules,
            onDemo: { [weak self] in self?.triggerDemo() },
            onQuit: { [weak self] in self?.shutdown() },
            onJump: { info in
                let fakeEvent = HookEvent(
                    event: "Notification",
                    payload: .object([:]),
                    env: info.env,
                    cwd: info.cwd
                )
                TerminalJumper.jump(to: fakeEvent)
            },
            onKill: { [weak self] info in
                self?.killSession(info)
            }
        )
        mb.watcher = w
        self.menuBar = mb

        logger.info("ready.")
    }

    func applicationWillTerminate(_ notification: Notification) {
        watcher?.stop()
        server?.stop()
    }

    func shutdown() {
        server?.stop()
        NSApp.terminate(nil)
    }

    func killSession(_ info: SessionInfo) {
        guard let pid = info.claudePID else {
            let a = NSAlert()
            a.messageText = "Cannot end session"
            a.informativeText = "No PID recorded — the session may be too old, or it never triggered a hook."
            a.alertStyle = .warning
            a.runModal()
            return
        }

        let alert = NSAlert()
        alert.messageText = "End this claude session?"
        alert.informativeText = """
        Sends SIGTERM to process \(pid).
        Session: \(info.title)
        Folder: \(info.cwd)
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "End (SIGTERM)")
        alert.addButton(withTitle: "Force End (SIGKILL)")
        alert.addButton(withTitle: "Cancel")

        let resp = alert.runModal()
        switch resp {
        case .alertFirstButtonReturn:
            send(signal: SIGTERM, to: pid, sessionID: info.id)
        case .alertSecondButtonReturn:
            send(signal: SIGKILL, to: pid, sessionID: info.id)
        default:
            return
        }
    }

    private func send(signal: Int32, to pid: Int, sessionID: String) {
        let r = kill(Int32(pid), signal)
        if r == 0 {
            logger.info("killed pid=\(pid) signal=\(signal)")
            sessions.remove(id: sessionID)
        } else {
            let err = String(cString: strerror(errno))
            logger.warn("kill failed pid=\(pid) signal=\(signal) errno=\(errno) (\(err))")
            let a = NSAlert()
            a.messageText = "Could not end session"
            a.informativeText = "PID \(pid): \(err)\n\nThe process may have already exited, or the PID points to a parent shell rather than claude itself."
            a.alertStyle = .warning
            a.runModal()
        }
    }

    func triggerDemo() {
        let demoEvent = HookEvent(
            event: "PreToolUse",
            payload: .object([
                "tool_name": .string("Bash"),
                "tool_input": .object([
                    "command": .string("Demo card: rm -rf /tmp/foo (this is only a demo)")
                ])
            ]),
            env: ["TERM_PROGRAM": "iTerm.app", "ITERM_SESSION_ID": "demo:demo"],
            cwd: "/Users/demo/projects/sample"
        )
        let req = ApprovalRequest(event: demoEvent)
        queue.enqueue(req)
        // Dismiss automatically after a while so the demo cannot block the queue
        DispatchQueue.global().asyncAfter(deadline: .now() + 25) { [weak self] in
            if !req.isResolved {
                self?.queue.resolve(id: req.id, decision: .allow, reason: "demo timeout")
            }
        }
    }
}
