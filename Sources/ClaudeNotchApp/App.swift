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

        // 捕获 SIGTERM/SIGINT,转给 NSApp 完成清理
        installSignalHandler(SIGTERM)
        installSignalHandler(SIGINT)

        app.run()
    }

    static func defaultRelayPath() -> String {
        let exePath = Bundle.main.executablePath ?? CommandLine.arguments[0]
        let exeDir = (exePath as NSString).deletingLastPathComponent
        // .app/Contents/Helpers/ClaudeNotchRelay 或 同目录的 ClaudeNotchRelay
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
            print("✅ Hook 已注入到 \(inj.settingsPath)")
            print("   relay: \(inj.relayPath)")
            print("   备份: \(inj.backupPath)")
        } catch {
            FileHandle.standardError.write(Data("❌ 注入失败: \(error)\n".utf8))
            exit(1)
        }
    }

    static func cliUninstall() {
        let inj = SettingsInjector(relayPath: defaultRelayPath())
        do {
            try inj.uninstall()
            print("✅ Hook 已移除")
        } catch {
            FileHandle.standardError.write(Data("❌ 移除失败: \(error)\n".utf8))
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
        // 让 system 不杀进程,交给 dispatch
        signal(signo, SIG_IGN)
        // 留住 src — DispatchSource 释放就停了
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
        // 优先使用 .app 内的 relay; 否则用 PATH
        let bundleHelper = Bundle.main.bundlePath + "/Contents/Helpers/ClaudeNotchRelay"
        if FileManager.default.fileExists(atPath: bundleHelper) {
            return bundleHelper
        }
        // 开发环境: 同目录的 .build/release/ClaudeNotchRelay
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
            a.messageText = "Claude Notch 启动失败"
            a.informativeText = "无法监听 socket: \(error)"
            a.alertStyle = .critical
            a.runModal()
            NSApp.terminate(nil)
            return
        }

        // Notch UI
        presenter = NotchPresenter(queue: queue, rules: rules)

        // Hook 自愈监视器
        let w = HookWatcher(injector: injector)
        w.onRateLimited = {
            DispatchQueue.main.async {
                let a = NSAlert()
                a.messageText = "Hook 反复被覆盖"
                a.informativeText = "短时间内 Hook 被外部工具反复修改。已暂停自愈。请手动检查 ~/.claude/settings.json,或菜单栏卸载 + 重装。"
                a.alertStyle = .warning
                a.runModal()
            }
        }
        w.start()
        self.watcher = w

        // 菜单栏 + popover
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
            a.messageText = "无法结束"
            a.informativeText = "没拿到 PID — 这个 session 可能太老,或者从来没触发过 hook。"
            a.alertStyle = .warning
            a.runModal()
            return
        }

        let alert = NSAlert()
        alert.messageText = "结束这个 claude session?"
        alert.informativeText = """
        会向进程 \(pid) 发 SIGTERM。
        Session: \(info.title)
        路径: \(info.cwd)
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "结束 (SIGTERM)")
        alert.addButton(withTitle: "强制结束 (SIGKILL)")
        alert.addButton(withTitle: "取消")

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
            a.messageText = "结束失败"
            a.informativeText = "PID \(pid): \(err)\n\n可能进程已经退出,或者 PID 实际指向 shell 的祖先而不是 claude 本身。"
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
                    "command": .string("演示卡片: rm -rf /tmp/foo (这是个演示)")
                ])
            ]),
            env: ["TERM_PROGRAM": "iTerm.app", "ITERM_SESSION_ID": "demo:demo"],
            cwd: "/Users/demo/projects/sample"
        )
        let req = ApprovalRequest(event: demoEvent)
        queue.enqueue(req)
        // 5 秒后自动消失 (避免演示卡死队列)
        DispatchQueue.global().asyncAfter(deadline: .now() + 25) { [weak self] in
            if !req.isResolved {
                self?.queue.resolve(id: req.id, decision: .allow, reason: "demo timeout")
            }
        }
    }
}
