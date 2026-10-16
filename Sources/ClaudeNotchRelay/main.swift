import Foundation

// ClaudeNotchRelay
// ----------------
// 由 Claude Code hook 系统调用的 CLI bridge:
//   1. 从 stdin 读 hook payload (JSON)
//   2. 包装成 HookEvent 通过 Unix socket 发给主 app
//   3. 等响应 (默认 60 秒)
//   4. 把 Claude Code 期望的 JSON 写到 stdout
//   5. 退出码永远 0 (避免 Claude Code 把 hook 当失败)
//
// 关键降级行为:
//   - app 没起 → 立即放行 ({"continue":true})
//   - 超时 → 放行
//   - 解析失败 → 放行
//
// 命令行: ClaudeNotchRelay --event PreToolUse [--timeout 60]

let logger = Logger(tag: "relay")

func parseArgs() -> (event: String, timeout: TimeInterval) {
    var event = "Unknown"
    var timeout: TimeInterval = 60
    var i = 1
    let args = CommandLine.arguments
    while i < args.count {
        let a = args[i]
        switch a {
        case "--event":
            if i + 1 < args.count { event = args[i + 1]; i += 2 } else { i += 1 }
        case "--timeout":
            if i + 1 < args.count, let t = TimeInterval(args[i + 1]) {
                timeout = t; i += 2
            } else { i += 1 }
        default:
            i += 1
        }
    }
    return (event, timeout)
}

func emit(_ json: String) -> Never {
    FileHandle.standardOutput.write(Data(json.utf8))
    FileHandle.standardOutput.write(Data("\n".utf8))
    exit(0)
}

let allowJSON = #"{"continue":true}"#

func main() {
    let (eventName, timeout) = parseArgs()
    logger.info("relay invoked: event=\(eventName) timeout=\(timeout)")

    // 读 stdin
    let stdinData = FileHandle.standardInput.readDataToEndOfFile()

    // 解析 payload
    let payload: AnyCodable
    if stdinData.isEmpty {
        payload = .object([:])
    } else if let parsed = try? HookCodec.decoder.decode(AnyCodable.self, from: stdinData) {
        payload = parsed
    } else {
        // 不是合法 JSON,作为 string 转发
        payload = .string(String(data: stdinData, encoding: .utf8) ?? "")
    }

    // 收集环境
    var env = ProcessInfo.processInfo.environment
    // 砍掉敏感/无关字段降低体积
    let keepKeys: Set<String> = [
        "ITERM_SESSION_ID", "TERM_SESSION_ID", "TERM_PROGRAM",
        "TERM_PROGRAM_VERSION", "TMUX_PANE", "TMUX",
        "PWD", "USER", "SHELL",
    ]
    env = env.filter { keepKeys.contains($0.key) }

    let cwd = ProcessInfo.processInfo.environment["PWD"]
        ?? FileManager.default.currentDirectoryPath

    let event = HookEvent(
        event: eventName,
        payload: payload,
        env: env,
        cwd: cwd,
        ppid: Int(getppid())
    )

    // 编码
    guard let requestData = try? HookCodec.encoder.encode(event) else {
        logger.warn("failed to encode HookEvent, defaulting to allow")
        emit(allowJSON)
    }

    // 发给主 app
    do {
        let respData = try UnixSocketClient.sendAndReceive(
            path: Paths.socket,
            message: requestData,
            timeout: timeout
        )
        let resp = try HookCodec.decoder.decode(HookResponse.self, from: respData)
        logger.info("got response: \(resp.decision.rawValue)")
        emit(resp.toClaudeJSON(eventName: eventName))
    } catch UnixSocketError.connectFailed(let e) {
        logger.warn("app not running (errno=\(e)), defaulting to allow")
        emit(allowJSON)
    } catch UnixSocketError.timeout {
        logger.warn("app timeout, defaulting to allow")
        emit(allowJSON)
    } catch {
        logger.warn("relay error: \(error), defaulting to allow")
        emit(allowJSON)
    }
}

main()
