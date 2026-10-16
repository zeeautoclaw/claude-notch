import Foundation

/// Watches ~/.claude/settings.json and restores our hooks if another tool rewrites it.
///
/// Implementation: polls the file mtime every 3 seconds — FSEvents is unreliable in hidden folders,
/// and a simple mtime check is more reliable and costs < 1 ms per check.
public final class HookWatcher {
    private let injector: SettingsInjector
    private let logger = Logger(tag: "watcher")
    private var timer: DispatchSourceTimer?
    private var lastSeenMtime: Date?
    private var lastRestoreAt: Date?
    private var restoreCount: Int = 0
    private let cooldown: TimeInterval = 2
    private let rateLimitWindow: TimeInterval = 60
    private let rateLimitMax: Int = 5
    private var restoreTimes: [Date] = []
    private var rateLimited = false
    private let queue = DispatchQueue(label: "claude-notch.watcher")

    public var onRateLimited: (() -> Void)?

    public init(injector: SettingsInjector) {
        self.injector = injector
    }

    public var enabled: Bool = true

    public func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 0.5, repeating: 3.0)
        t.setEventHandler { [weak self] in
            self?.tick()
        }
        t.resume()
        timer = t
        logger.info("watcher started (poll every 3s)")
    }

    public func stop() {
        timer?.cancel()
        timer = nil
    }

    private func tick() {
        guard enabled else { return }

        let path = injector.settingsPath
        let mtime = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate]) as? Date

        // File unchanged → skip
        if let last = lastSeenMtime, last == mtime {
            return
        }
        lastSeenMtime = mtime

        // Cooldown — we just wrote it ourselves
        if let last = lastRestoreAt, Date().timeIntervalSince(last) < cooldown {
            return
        }

        // rate limit
        let now = Date()
        restoreTimes = restoreTimes.filter { now.timeIntervalSince($0) < rateLimitWindow }
        if restoreTimes.count >= rateLimitMax {
            if !rateLimited {
                rateLimited = true
                logger.warn("rate limited — disabling self-heal for \(rateLimitWindow)s")
                DispatchQueue.main.async { [weak self] in
                    self?.onRateLimited?()
                }
            }
            return
        }
        // Re-enable automatically after 60 seconds
        if rateLimited, let last = restoreTimes.last,
           now.timeIntervalSince(last) > rateLimitWindow {
            rateLimited = false
        }

        do {
            let installed = try injector.isInstalled()
            if !installed {
                logger.warn("hook missing, restoring")
                try injector.install()
                lastRestoreAt = Date()
                restoreTimes.append(Date())
                restoreCount += 1
                logger.info("hook restored (total: \(restoreCount))")
                // Update mtime so the next tick does not fire again
                lastSeenMtime = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate]) as? Date
            }
        } catch {
            logger.error("watcher check failed: \(error)")
        }
    }
}
