import Foundation

// ClaudeNotchRelay
// ----------------
// CLI bridge called by the Claude Code hook system:
//   1. Read the hook payload (JSON) from stdin
//   2. Wrap it in a HookEvent and send it to the main app over a Unix socket
//   3. Wait for the response (60 seconds by default)
//   4. Write the JSON Claude Code expects to stdout
//   5. Always exit 0 (so Claude Code never treats the hook as failed)
//
// Fallback behavior:
//   - app not running → allow immediately ({"continue":true})
//   - timeout → allow
//   - parse failure → allow
//
// Usage: ClaudeNotchRelay --event PreToolUse [--timeout 60]

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

    // Read stdin
    let stdinData = FileHandle.standardInput.readDataToEndOfFile()

    // Parse the payload
    let payload: AnyCodable
    if stdinData.isEmpty {
        payload = .object([:])
    } else if let parsed = try? HookCodec.decoder.decode(AnyCodable.self, from: stdinData) {
        payload = parsed
    } else {
        // Not valid JSON — forward it as a string
        payload = .string(String(data: stdinData, encoding: .utf8) ?? "")
    }

    // Collect the environment
    var env = ProcessInfo.processInfo.environment
    // Drop sensitive/irrelevant fields to keep it small
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

    // Encode
    guard let requestData = try? HookCodec.encoder.encode(event) else {
        logger.warn("failed to encode HookEvent, defaulting to allow")
        emit(allowJSON)
    }

    // Send to the main app
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
