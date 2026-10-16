import AppKit
import SwiftUI

/// Menu bar icon + popover (replaces the old NSMenu).
public final class MenuBarController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let injector: SettingsInjector
    private let sessions: SessionStore
    private let rules: RulesStore
    private let onDemo: () -> Void
    private let onQuit: () -> Void
    private let onJump: (SessionInfo) -> Void
    private let onKill: (SessionInfo) -> Void
    public weak var watcher: HookWatcher?

    public init(
        injector: SettingsInjector,
        sessions: SessionStore,
        rules: RulesStore,
        onDemo: @escaping () -> Void,
        onQuit: @escaping () -> Void,
        onJump: @escaping (SessionInfo) -> Void,
        onKill: @escaping (SessionInfo) -> Void
    ) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.injector = injector
        self.sessions = sessions
        self.rules = rules
        self.onDemo = onDemo
        self.onQuit = onQuit
        self.onJump = onJump
        self.onKill = onKill

        let pop = NSPopover()
        pop.behavior = .transient
        pop.animates = true
        self.popover = pop

        super.init()
        pop.delegate = self
        configure()
    }

    private func configure() {
        if let button = statusItem.button {
            if let img = NSImage(systemSymbolName: "rectangle.dashed",
                                 accessibilityDescription: "Claude Notch") {
                img.isTemplate = true
                button.image = img
            } else {
                button.title = "CN"
            }
            button.action = #selector(toggle)
            button.target = self
        }
    }

    @objc private func toggle() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        let installed = (try? injector.isInstalled()) ?? false
        let view = SessionListPanel(
            sessions: sessions,
            rules: rules,
            installed: installed,
            onInstall: { [weak self] in self?.installHooksFromMenu() },
            onUninstall: { [weak self] in self?.uninstallHooks() },
            onJump: { [weak self] info in
                self?.popover.performClose(nil)
                self?.onJump(info)
            },
            onKill: { [weak self] info in
                self?.popover.performClose(nil)
                self?.onKill(info)
            },
            onClearDone: { [weak self] in self?.sessions.clearDone() },
            onOpenLog: { NSWorkspace.shared.open(URL(fileURLWithPath: Paths.logFile)) },
            onTriggerDemo: { [weak self] in
                self?.popover.performClose(nil)
                self?.onDemo()
            },
            onQuit: { [weak self] in self?.onQuit() }
        )
        let host = NSHostingController(rootView: view)
        popover.contentViewController = host
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func installHooks() {
        do {
            try injector.install()
            alert(title: "Hooks installed",
                  info: "Restart any running claude session for them to take effect.")
        } catch {
            alert(title: "Install failed", info: "\(error)", style: .warning)
        }
        // Reopen the popover to refresh its state
        popover.performClose(nil)
    }

    private func uninstallHooks() {
        // Pause the watcher so it does not put the hooks straight back
        watcher?.enabled = false
        do {
            try injector.uninstall()
            alert(title: "Hooks removed",
                  info: "settings.json is back to how it was before Claude Notch. Hook self-healing is off (it will not reinstall them).")
        } catch {
            alert(title: "Uninstall failed", info: "\(error)", style: .warning)
            watcher?.enabled = true
        }
        popover.performClose(nil)
    }

    private func installHooksFromMenu() {
        // Reinstall → re-enable the watcher
        installHooks()
        watcher?.enabled = true
    }

    private func alert(title: String, info: String, style: NSAlert.Style = .informational) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = info
        a.alertStyle = style
        a.runModal()
    }
}
