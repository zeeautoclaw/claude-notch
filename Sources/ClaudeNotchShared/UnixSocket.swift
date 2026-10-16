import Foundation
import Darwin

public enum UnixSocketError: Error, CustomStringConvertible {
    case createFailed(Int32)
    case bindFailed(Int32)
    case listenFailed(Int32)
    case connectFailed(Int32)
    case sendFailed(Int32)
    case recvFailed(Int32)
    case timeout
    case pathTooLong
    case invalidUTF8

    public var description: String {
        switch self {
        case .createFailed(let e):  return "socket create failed: errno=\(e) \(String(cString: strerror(e)))"
        case .bindFailed(let e):    return "bind failed: errno=\(e) \(String(cString: strerror(e)))"
        case .listenFailed(let e):  return "listen failed: errno=\(e) \(String(cString: strerror(e)))"
        case .connectFailed(let e): return "connect failed: errno=\(e) \(String(cString: strerror(e)))"
        case .sendFailed(let e):    return "send failed: errno=\(e) \(String(cString: strerror(e)))"
        case .recvFailed(let e):    return "recv failed: errno=\(e) \(String(cString: strerror(e)))"
        case .timeout:              return "socket timeout"
        case .pathTooLong:          return "socket path too long"
        case .invalidUTF8:          return "invalid utf8 in path"
        }
    }
}

/// Prepares a sockaddr_un.
private func makeUnixAddr(path: String) throws -> (sockaddr_un, socklen_t) {
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = Array(path.utf8)
    let maxLen = MemoryLayout.size(ofValue: addr.sun_path) - 1
    guard pathBytes.count <= maxLen else { throw UnixSocketError.pathTooLong }

    withUnsafeMutableBytes(of: &addr.sun_path) { rawBuf in
        let bytePtr = rawBuf.bindMemory(to: UInt8.self)
        for (i, b) in pathBytes.enumerated() {
            bytePtr[i] = b
        }
        bytePtr[pathBytes.count] = 0
    }

    let len = socklen_t(MemoryLayout<sockaddr_un>.size)
    return (addr, len)
}

// MARK: - Server

/// Unix socket server. One connection = one newline-delimited JSON request/response.
public final class UnixSocketServer: @unchecked Sendable {
    public typealias Handler = (Data) -> Data

    private let path: String
    public var handler: Handler
    private var listenFD: Int32 = -1
    private let serverQueue = DispatchQueue(label: "claude-notch.socket.server")
    private var running = false

    public init(path: String, handler: @escaping Handler) {
        self.path = path
        self.handler = handler
    }

    public func start() throws {
        // Remove any stale socket file
        try? FileManager.default.removeItem(atPath: path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw UnixSocketError.createFailed(errno) }

        var (addr, len) = try makeUnixAddr(path: path)
        let bindRet = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.bind(fd, sa, len)
            }
        }
        guard bindRet == 0 else {
            close(fd)
            throw UnixSocketError.bindFailed(errno)
        }

        guard Darwin.listen(fd, 16) == 0 else {
            close(fd)
            throw UnixSocketError.listenFailed(errno)
        }

        listenFD = fd
        running = true

        serverQueue.async { [weak self] in
            self?.acceptLoop()
        }
    }

    private func acceptLoop() {
        while running, listenFD >= 0 {
            let conn = accept(listenFD, nil, nil)
            if conn < 0 {
                if errno == EINTR { continue }
                if !running { break }
                Thread.sleep(forTimeInterval: 0.05)
                continue
            }
            // Each connection gets its own thread
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.handle(connection: conn)
            }
        }
    }

    private func handle(connection: Int32) {
        defer { close(connection) }

        // Read up to \n
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        var found = false
        while !found {
            let n = recv(connection, &chunk, chunk.count, 0)
            if n <= 0 { return }
            buffer.append(chunk, count: n)
            if buffer.contains(0x0A) { found = true }
        }

        // Take the first line
        guard let nlIdx = buffer.firstIndex(of: 0x0A) else { return }
        let request = buffer.prefix(nlIdx)

        // Call the handler
        let response = handler(Data(request))

        // Write back + \n
        var resp = response
        resp.append(0x0A)
        var sent = 0
        resp.withUnsafeBytes { rawBuf in
            let basePtr = rawBuf.baseAddress!
            while sent < resp.count {
                let n = send(connection, basePtr.advanced(by: sent), resp.count - sent, 0)
                if n <= 0 { break }
                sent += n
            }
        }
    }

    public func stop() {
        running = false
        if listenFD >= 0 {
            close(listenFD)
            listenFD = -1
        }
        try? FileManager.default.removeItem(atPath: path)
    }
}

// MARK: - Client

public enum UnixSocketClient {
    /// Synchronously send + receive one newline-delimited JSON message.
    public static func sendAndReceive(
        path: String,
        message: Data,
        timeout: TimeInterval
    ) throws -> Data {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw UnixSocketError.createFailed(errno) }
        defer { close(fd) }

        // Set send/recv timeouts
        let secs = Int(timeout)
        let usecs = Int32((timeout - Double(secs)) * 1_000_000)
        var tv = timeval(tv_sec: secs, tv_usec: usecs)
        let tvSize = socklen_t(MemoryLayout<timeval>.size)
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, tvSize)
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, tvSize)

        var (addr, len) = try makeUnixAddr(path: path)
        let connectRet = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.connect(fd, sa, len)
            }
        }
        guard connectRet == 0 else {
            throw UnixSocketError.connectFailed(errno)
        }

        // Send message + \n
        var payload = message
        payload.append(0x0A)
        var sent = 0
        try payload.withUnsafeBytes { rawBuf in
            let basePtr = rawBuf.baseAddress!
            while sent < payload.count {
                let n = send(fd, basePtr.advanced(by: sent), payload.count - sent, 0)
                if n < 0 {
                    if errno == EAGAIN || errno == EWOULDBLOCK {
                        throw UnixSocketError.timeout
                    }
                    throw UnixSocketError.sendFailed(errno)
                }
                if n == 0 { break }
                sent += n
            }
        }

        // Read up to \n
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = recv(fd, &chunk, chunk.count, 0)
            if n < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    throw UnixSocketError.timeout
                }
                throw UnixSocketError.recvFailed(errno)
            }
            if n == 0 { break }
            buffer.append(chunk, count: n)
            if buffer.contains(0x0A) { break }
        }

        if let nlIdx = buffer.firstIndex(of: 0x0A) {
            return Data(buffer.prefix(nlIdx))
        }
        return buffer
    }
}
