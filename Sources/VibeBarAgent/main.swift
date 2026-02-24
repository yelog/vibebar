import Darwin
import Foundation
import VibeBarCore

private struct AgentConfig {
    var socketPath: String = VibeBarPaths.agentSocketURL.path
    var verbose: Bool = false
    var printSocketPathOnly: Bool = false
}

private final class AgentServer {
    private let config: AgentConfig
    private let store = SessionFileStore()
    private let decoder: JSONDecoder
    private var listenFD: Int32 = -1

    init(config: AgentConfig) {
        self.config = config
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    func run() -> Int32 {
        signal(SIGPIPE, SIG_IGN)

        do {
            try VibeBarPaths.ensureDirectories()
        } catch {
            fputs("vibebar-agent: 无法创建目录: \(error.localizedDescription)\n", stderr)
            return 1
        }

        let socketPath = config.socketPath
        try? FileManager.default.removeItem(atPath: socketPath)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            fputs("vibebar-agent: 创建 socket 失败\n", stderr)
            return 1
        }
        listenFD = fd

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxPathLength = MemoryLayout.size(ofValue: addr.sun_path)
        let utf8Path = socketPath.utf8CString
        guard utf8Path.count <= maxPathLength else {
            fputs("vibebar-agent: socket 路径过长: \(socketPath)\n", stderr)
            close(fd)
            return 1
        }

        withUnsafeMutablePointer(to: &addr.sun_path) { sunPathPtr in
            _ = utf8Path.withUnsafeBufferPointer { pathPtr in
                memcpy(sunPathPtr, pathPtr.baseAddress, pathPtr.count)
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.stride))
            }
        }
        guard bindResult == 0 else {
            let message = String(cString: strerror(errno))
            fputs("vibebar-agent: bind 失败: \(message)\n", stderr)
            close(fd)
            return 1
        }

        guard listen(fd, 64) == 0 else {
            let message = String(cString: strerror(errno))
            fputs("vibebar-agent: listen 失败: \(message)\n", stderr)
            close(fd)
            return 1
        }

        if config.verbose {
            fputs("vibebar-agent: listening on \(socketPath)\n", stderr)
        }

        defer {
            if listenFD >= 0 {
                close(listenFD)
            }
            try? FileManager.default.removeItem(atPath: socketPath)
        }

        while true {
            let clientFD = accept(fd, nil, nil)
            if clientFD < 0 {
                if errno == EINTR { continue }
                let message = String(cString: strerror(errno))
                fputs("vibebar-agent: accept 失败: \(message)\n", stderr)
                continue
            }

            handleClient(fd: clientFD)
            close(clientFD)
        }
    }

    private func handleClient(fd: Int32) {
        var buffer = [UInt8](repeating: 0, count: 8192)
        var data = Data()

        while true {
            let count = read(fd, &buffer, buffer.count)
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                return
            }
            data.append(buffer, count: count)
        }

        guard !data.isEmpty else { return }
        guard let text = String(data: data, encoding: .utf8) else { return }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        for line in lines {
            handleLine(String(line))
        }
    }

    private func handleLine(_ line: String) {
        let raw = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        guard let data = raw.data(using: .utf8) else { return }

        do {
            let event = try decoder.decode(AgentEvent.self, from: data)
            apply(event: event)
        } catch {
            fputs("vibebar-agent: 无法解析事件: \(raw)\n", stderr)
        }
    }

    private func apply(event: AgentEvent) {
        let now = event.timestamp ?? Date()
        let sessionID = event.compositeSessionID
        let loweredType = event.eventType.lowercased()

        if isTerminalEventType(loweredType) {
            store.delete(sessionID: sessionID)
            return
        }

        let previous = store.load(sessionID: sessionID)
        let status = resolveStatus(event: event, previous: previous)

        var snapshot = previous ?? SessionSnapshot(
            id: sessionID,
            tool: event.tool,
            pid: event.pid ?? 0,
            parentPID: event.parentPID,
            status: status,
            source: .plugin,
            startedAt: now,
            updatedAt: now,
            lastOutputAt: nil,
            lastInputAt: nil,
            cwd: event.cwd,
            command: event.command ?? [event.tool.executable],
            notes: nil
        )

        snapshot.tool = event.tool
        snapshot.pid = event.pid ?? snapshot.pid
        snapshot.parentPID = event.parentPID ?? snapshot.parentPID
        snapshot.source = .plugin
        snapshot.status = status
        snapshot.updatedAt = now
        snapshot.cwd = event.cwd ?? snapshot.cwd
        snapshot.command = event.command ?? snapshot.command
        snapshot.notes = event.notes ?? "\(event.source.rawValue):\(event.eventType)"

        if status == .running {
            snapshot.lastOutputAt = now
        } else if status == .awaitingInput {
            snapshot.lastInputAt = now
        }

        do {
            try store.write(snapshot)
            // 同一 PID 可能因插件生成不同 sessionID 而存在旧文件，写入后清理。
            store.deleteOtherSessions(forPID: snapshot.pid, keeping: sessionID)
        } catch {
            fputs("vibebar-agent: 写入会话失败: \(error.localizedDescription)\n", stderr)
        }
    }

    private func resolveStatus(event: AgentEvent, previous: SessionSnapshot?) -> ToolActivityState {
        if let status = event.status {
            return status
        }

        let loweredType = event.eventType.lowercased()
        if loweredType.contains("permission") || loweredType.contains("await") || loweredType.contains("prompt") || loweredType.contains("approval") {
            return .awaitingInput
        }
        if loweredType.contains("idle") {
            return .idle
        }
        if loweredType.contains("run") || loweredType.contains("start") || loweredType.contains("tool") || loweredType.contains("progress") {
            return .running
        }
        return previous?.status ?? .running
    }

    private func isTerminalEventType(_ type: String) -> Bool {
        type.contains("end") || type.contains("exit") || type.contains("stop") || type.contains("terminate") || type.contains("close")
    }
}

private func parseConfig(arguments: [String]) -> AgentConfig? {
    var config = AgentConfig()
    var index = 1

    while index < arguments.count {
        let arg = arguments[index]
        switch arg {
        case "--socket-path":
            let next = index + 1
            guard next < arguments.count else { return nil }
            config.socketPath = arguments[next]
            index += 2
        case "--print-socket-path":
            config.printSocketPathOnly = true
            index += 1
        case "--verbose":
            config.verbose = true
            index += 1
        case "--help", "-h":
            return nil
        default:
            return nil
        }
    }

    return config
}

private func printUsage() {
    let usage = """
    用法:
      vibebar-agent [--socket-path <path>] [--verbose]
      vibebar-agent --print-socket-path
    """
    print(usage)
}

if let config = parseConfig(arguments: CommandLine.arguments) {
    if config.printSocketPathOnly {
        print(config.socketPath)
        exit(0)
    }
    let server = AgentServer(config: config)
    exit(server.run())
} else {
    printUsage()
    exit(2)
}
