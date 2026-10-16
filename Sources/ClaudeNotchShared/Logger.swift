import Foundation

/// 简单的文件 + stderr logger。线程安全。
public final class Logger: @unchecked Sendable {
    public static let shared = Logger(tag: "app")

    private let tag: String
    private let queue = DispatchQueue(label: "claude-notch.logger")
    private let formatter: DateFormatter

    public init(tag: String) {
        self.tag = tag
        self.formatter = DateFormatter()
        self.formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    }

    public func log(_ message: String, level: String = "INFO") {
        queue.async { [self] in
            let line = "[\(formatter.string(from: Date()))] [\(level)] [\(tag)] \(message)\n"

            // stderr
            FileHandle.standardError.write(Data(line.utf8))

            // 文件
            let path = Paths.logFile
            if !FileManager.default.fileExists(atPath: path) {
                FileManager.default.createFile(atPath: path, contents: nil)
            }
            if let h = FileHandle(forWritingAtPath: path) {
                defer { try? h.close() }
                _ = try? h.seekToEnd()
                try? h.write(contentsOf: Data(line.utf8))
            }
        }
    }

    public func info(_ msg: String)  { log(msg, level: "INFO") }
    public func warn(_ msg: String)  { log(msg, level: "WARN") }
    public func error(_ msg: String) { log(msg, level: "ERROR") }
    public func debug(_ msg: String) { log(msg, level: "DEBUG") }
}
