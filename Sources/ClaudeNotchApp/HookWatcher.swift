import Foundation

/// 监控 ~/.claude/settings.json,被其他工具改写后自动恢复我们的 hook。
///
/// 实现方式: 文件 mtime 轮询 (3 秒间隔) — FSEvents 在隐藏目录里时灵时不灵,
/// 简单的 mtime 检查更可靠且开销 < 1ms/次。
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

        // 文件没变 → 跳过
        if let last = lastSeenMtime, last == mtime {
            return
        }
        lastSeenMtime = mtime

        // cooldown — 自己刚写过
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
        // 60 秒后自动解禁
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
                // 更新 mtime 避免下一 tick 又触发
                lastSeenMtime = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate]) as? Date
            }
        } catch {
            logger.error("watcher check failed: \(error)")
        }
    }
}
