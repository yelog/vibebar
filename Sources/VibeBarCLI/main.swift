import Darwin
import Foundation
import VibeBarCore

private struct CLIConfig {
    let tool: ToolKind
    let passthrough: [String]
}

private struct NotifyConfig {
    let tool: ToolKind
    let status: ToolActivityState?
    let eventType: String
    let sessionID: String
    let pid: Int32
    let parentPID: Int32
    let cwd: String
    let notes: String?
    let metadata: [String: String]
}

private struct TerminalRawMode {
    private var original = termios()
    private(set) var enabled = false

    mutating func enableIfPossible() {
        guard isatty(STDIN_FILENO) == 1 else { return }
        guard tcgetattr(STDIN_FILENO, &original) == 0 else { return }

        var raw = original
        cfmakeraw(&raw)
        if tcsetattr(STDIN_FILENO, TCSANOW, &raw) == 0 {
            enabled = true
        }
    }

    mutating func restore() {
        guard enabled else { return }
        var value = original
        _ = tcsetattr(STDIN_FILENO, TCSANOW, &value)
        enabled = false
    }
}

private struct PromptDetector {
    private let awaitRegex: NSRegularExpression
    private let resumeRegex: NSRegularExpression

    init(tool: ToolKind) {
        let awaitPattern: String
        let resumePattern: String
        switch tool {
        case .claudeCode:
            awaitPattern = #"(?i)(y/n|yes/no|press enter|allow|approve|permission|continue\?|do you want to|select an option|1\.\s*yes|2\.\s*yes|3\.\s*no)"#
            resumePattern = #"(?i)(thinking|exploring|analyz|running|execut|processing|searching|writing|updating|completed|done|tool use)"#
        case .codex:
            awaitPattern = #"(?i)(y/n|yes/no|press enter|approval|allow|confirm|continue\?|select an option)"#
            resumePattern = #"(?i)(thinking|exploring|analyz|running|execut|processing|searching|writing|updating|completed|done|tool use)"#
        case .opencode:
            awaitPattern = #"(?i)(y/n|yes/no|press enter|confirm|select|choose|continue\?|select an option)"#
            resumePattern = #"(?i)(thinking|exploring|analyz|running|execut|processing|searching|writing|updating|completed|done|tool use)"#
        case .aider:
            awaitPattern = #"(?i)(y/n|yes/no|press enter|continue\?|run this command\?|is this ok\?|apply.*\?|proceed\?)"#
            resumePattern = #"(?i)(thinking|analyz|running|execut|processing|searching|writing|updating|completed|done|tokens)"#
        case .gemini:
            awaitPattern = #"(?i)(y/n|yes/no|press enter|allow|approve|permission|continue\?|proceed\?|tool permission|action required)"#
            resumePattern = #"(?i)(thinking|planning|running|execut|processing|searching|writing|updating|tool|result|done)"#
        case .githubCopilot:
            awaitPattern = #"(?i)(y/n|yes/no|press enter|select an option|run this command|revise|explain|continue\?|confirm)"#
            resumePattern = #"(?i)(thinking|analyzing|searching|writing|running|execut|processing|updating|completed|done|suggesting)"#
        }

        self.awaitRegex = try! NSRegularExpression(pattern: awaitPattern, options: [])
        self.resumeRegex = try! NSRegularExpression(pattern: resumePattern, options: [])
    }

    func hasAwaitHint(in text: String) -> Bool {
        let range = NSRange(location: 0, length: (text as NSString).length)
        return awaitRegex.firstMatch(in: text, options: [], range: range) != nil
    }

    func hasResumeHint(in text: String) -> Bool {
        let range = NSRange(location: 0, length: (text as NSString).length)
        return resumeRegex.firstMatch(in: text, options: [], range: range) != nil
    }
}

private final class WrapperRunner {
    private let config: CLIConfig
    private let store = SessionFileStore()
    private let detector: PromptDetector
    private let wrappedArgs: [String]
    private let sessionID = UUID().uuidString.lowercased()

    private var snapshot: SessionSnapshot
    private var rawMode = TerminalRawMode()

    private var masterFD: Int32 = -1
    private var childPID: pid_t = 0

    private var lastOutputAt = Date()
    private var lastInputAt: Date?
    private var lastPersistAt = Date.distantPast
    private var promptWindow = ""
    private var awaitingInputLatched = false
    private var awaitingResumePending = false
    private var awaitingResumeProbeStartedAt: Date?
    private var awaitingResumeOutputChars = 0
    private var currentState: ToolActivityState = .running

    private var lastRows: UInt16 = 0
    private var lastCols: UInt16 = 0

    private let promptWindowLimit = 512
    private let resumeProbeMinOutputChars = 80
    private let resumeProbeWindowSeconds: TimeInterval = 2.5

    init(config: CLIConfig) {
        self.config = config
        self.detector = PromptDetector(tool: config.tool)
        self.wrappedArgs = WrapperRunner.buildWrappedArgs(config: config)

        let now = Date()
        self.snapshot = SessionSnapshot(
            id: sessionID,
            tool: config.tool,
            pid: 0,
            parentPID: getpid(),
            status: .running,
            source: .wrapper,
            startedAt: now,
            updatedAt: now,
            lastOutputAt: now,
            lastInputAt: nil,
            cwd: FileManager.default.currentDirectoryPath,
            command: [config.tool.executable] + wrappedArgs,
            notes: "pty-wrapper"
        )
    }

    func run() -> Int32 {
        signal(SIGPIPE, SIG_IGN)

        do {
            try VibeBarPaths.ensureDirectories()
        } catch {
            fputs("vibebar: 无法创建目录: \(error.localizedDescription)\n", stderr)
            return 1
        }

        guard launchChild() else { return 1 }
        defer {
            if masterFD >= 0 {
                _ = close(masterFD)
            }
            // 用户退出会话后立即移除状态文件，避免菜单栏保留已退出会话。
            store.delete(sessionID: sessionID)
        }

        rawMode.enableIfPossible()
        defer { rawMode.restore() }

        publishSnapshot(force: true)
        let exitCode = loop()
        return exitCode
    }

    private func launchChild() -> Bool {
        var size = winsize()
        if ioctl(STDIN_FILENO, TIOCGWINSZ, &size) != 0 {
            size.ws_row = 24
            size.ws_col = 80
        }

        var mfd: Int32 = -1
        let pid = forkpty(&mfd, nil, nil, &size)
        if pid < 0 {
            fputs("vibebar: forkpty 失败\n", stderr)
            return false
        }

        if pid == 0 {
            execTool()
        }

        childPID = pid
        masterFD = mfd
        snapshot.pid = pid
        snapshot.parentPID = getpid()
        lastRows = size.ws_row
        lastCols = size.ws_col
        return true
    }

    private func execTool() -> Never {
        let executable = config.tool.executable
        let argv = [executable] + wrappedArgs

        var cArgs: [UnsafeMutablePointer<CChar>?] = argv.map { strdup($0) }
        cArgs.append(nil)

        _ = cArgs.withUnsafeMutableBufferPointer { ptr in
            execvp(executable, ptr.baseAddress)
        }

        let message = String(cString: strerror(errno))
        fputs("vibebar: 无法启动 \(executable): \(message)\n", stderr)
        _exit(127)
    }

    private func loop() -> Int32 {
        var childStatus: Int32 = 0

        while true {
            forwardWindowSizeIfNeeded()

            var fds: [pollfd] = []
            if isatty(STDIN_FILENO) == 1 {
                fds.append(pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0))
            }
            fds.append(pollfd(fd: masterFD, events: Int16(POLLIN), revents: 0))

            let pollResult = fds.withUnsafeMutableBufferPointer { ptr in
                poll(ptr.baseAddress, nfds_t(ptr.count), 200)
            }

            let now = Date()

            if pollResult > 0 {
                for fd in fds {
                    if (fd.revents & Int16(POLLIN)) != 0 {
                        if fd.fd == STDIN_FILENO {
                            consumeStdin(now: now)
                        } else if fd.fd == masterFD {
                            let alive = consumeMaster(now: now)
                            if !alive {
                                _ = waitpid(childPID, &childStatus, 0)
                                return decodeExitCode(childStatus)
                            }
                        }
                    }

                    if (fd.revents & Int16(POLLHUP)) != 0 && fd.fd == masterFD {
                        _ = waitpid(childPID, &childStatus, 0)
                        return decodeExitCode(childStatus)
                    }
                }
            }

            recomputeState(now: now)
            publishSnapshot(force: false)

            let waitResult = waitpid(childPID, &childStatus, WNOHANG)
            if waitResult == childPID {
                return decodeExitCode(childStatus)
            }
        }
    }

    private func consumeStdin(now: Date) {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let readCount = read(STDIN_FILENO, &buffer, buffer.count)
        guard readCount > 0 else { return }

        let success = writeAll(fd: masterFD, bytes: buffer, count: readCount)
        if success {
            lastInputAt = now
            if awaitingInputLatched {
                awaitingResumePending = true
                awaitingResumeProbeStartedAt = now
                awaitingResumeOutputChars = 0
            }
            promptWindow = ""
            currentState = awaitingInputLatched ? .awaitingInput : .running
        }
    }

    private func consumeMaster(now: Date) -> Bool {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let readCount = read(masterFD, &buffer, buffer.count)
        if readCount == 0 {
            return false
        }
        if readCount < 0 {
            return errno == EAGAIN || errno == EINTR
        }

        let success = writeAll(fd: STDOUT_FILENO, bytes: buffer, count: readCount)
        if success {
            lastOutputAt = now
            currentState = .running
            updatePromptHint(with: buffer, count: readCount, now: now)
        }
        return true
    }

    private func updatePromptHint(with bytes: [UInt8], count: Int, now: Date) {
        let chunk = String(decoding: bytes.prefix(count), as: UTF8.self)
        let cleaned = sanitizeForPromptDetection(chunk)
        guard !cleaned.isEmpty else { return }

        promptWindow += cleaned
        if promptWindow.count > promptWindowLimit {
            promptWindow.removeFirst(promptWindow.count - promptWindowLimit)
        }

        if detector.hasAwaitHint(in: promptWindow) {
            awaitingInputLatched = true
            awaitingResumePending = false
            awaitingResumeProbeStartedAt = nil
            awaitingResumeOutputChars = 0
            return
        }

        if awaitingInputLatched && awaitingResumePending {
            awaitingResumeOutputChars += cleaned.count

            let probeElapsed = awaitingResumeProbeStartedAt.map { now.timeIntervalSince($0) } ?? 0
            let hasResumeSignal = detector.hasResumeHint(in: cleaned) || detector.hasResumeHint(in: promptWindow)
            let hasEnoughOutput = awaitingResumeOutputChars >= resumeProbeMinOutputChars
            let probeTimedOut = probeElapsed >= resumeProbeWindowSeconds

            if hasResumeSignal || (probeTimedOut && hasEnoughOutput) {
                awaitingInputLatched = false
                awaitingResumePending = false
                awaitingResumeProbeStartedAt = nil
                awaitingResumeOutputChars = 0
            }
        }
    }

    private func recomputeState(now: Date) {
        let outputLag = now.timeIntervalSince(lastOutputAt)

        let nextState: ToolActivityState
        if awaitingInputLatched {
            nextState = .awaitingInput
        } else if outputLag < 0.8 {
            nextState = .running
        } else {
            nextState = .idle
        }

        currentState = nextState
    }

    private func publishSnapshot(force: Bool) {
        let now = Date()
        if !force && now.timeIntervalSince(lastPersistAt) < 0.5 {
            return
        }

        snapshot.status = currentState
        snapshot.updatedAt = now
        snapshot.lastOutputAt = lastOutputAt
        snapshot.lastInputAt = lastInputAt

        do {
            try store.write(snapshot)
            lastPersistAt = now
        } catch {
            fputs("vibebar: 写会话状态失败: \(error.localizedDescription)\n", stderr)
        }
    }

    private func forwardWindowSizeIfNeeded() {
        guard isatty(STDIN_FILENO) == 1 else { return }
        var size = winsize()
        guard ioctl(STDIN_FILENO, TIOCGWINSZ, &size) == 0 else { return }
        guard size.ws_row != lastRows || size.ws_col != lastCols else { return }

        lastRows = size.ws_row
        lastCols = size.ws_col
        _ = ioctl(masterFD, TIOCSWINSZ, &size)
        _ = kill(childPID, SIGWINCH)
    }

    private func decodeExitCode(_ status: Int32) -> Int32 {
        let signal = status & 0x7F
        if signal == 0 {
            return (status >> 8) & 0xFF
        }
        if signal == 0x7F {
            return 128
        }
        return 128 + signal
    }

    private func writeAll(fd: Int32, bytes: [UInt8], count: Int) -> Bool {
        var written = 0
        while written < count {
            let chunkCount = bytes.withUnsafeBytes { ptr in
                let base = ptr.baseAddress!.assumingMemoryBound(to: UInt8.self)
                return write(fd, base.advanced(by: written), count - written)
            }
            if chunkCount < 0 {
                if errno == EINTR { continue }
                return false
            }
            written += chunkCount
        }
        return true
    }

    private func sanitizeForPromptDetection(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)

        var inEscapeSequence = false
        for scalar in text.unicodeScalars {
            let value = scalar.value

            if inEscapeSequence {
                if (0x40 ... 0x7E).contains(value) {
                    inEscapeSequence = false
                }
                continue
            }

            if value == 0x1B {
                inEscapeSequence = true
                continue
            }

            if value < 0x20 || value == 0x7F {
                if value == 0x0A || value == 0x0D || value == 0x09 {
                    result.append(" ")
                }
                continue
            }

            result.unicodeScalars.append(scalar)
        }

        return result
    }

    private static func buildWrappedArgs(config: CLIConfig) -> [String] {
        var args = config.passthrough
        guard config.tool == .gemini else {
            return args
        }
        if hasOutputFormatFlag(args) {
            return args
        }
        if shouldForceGeminiStreamJSON(args) {
            args.append(contentsOf: ["--output-format", "stream-json"])
        }
        return args
    }

    private static func hasOutputFormatFlag(_ args: [String]) -> Bool {
        for arg in args {
            if arg == "--output-format" || arg == "-o" {
                return true
            }
            if arg.hasPrefix("--output-format=") || arg.hasPrefix("-o=") {
                return true
            }
        }
        return false
    }

    private static func shouldForceGeminiStreamJSON(_ args: [String]) -> Bool {
        if isatty(STDIN_FILENO) != 1 {
            return true
        }
        for arg in args {
            if arg == "--stdin" || arg == "-p" || arg == "--prompt" {
                return true
            }
            if arg.hasPrefix("--prompt=") || arg.hasPrefix("-p=") {
                return true
            }
        }
        return false
    }
}

private func parseCLI(arguments: [String]) -> CLIConfig? {
    guard arguments.count >= 2 else { return nil }
    guard let tool = ToolKind.fromCLIArgument(arguments[1]) else { return nil }

    var rest = Array(arguments.dropFirst(2))
    if rest.first == "--" {
        rest.removeFirst()
    }

    return CLIConfig(tool: tool, passthrough: rest)
}

private func parseNotify(arguments: [String]) -> NotifyConfig? {
    guard arguments.count >= 4 else { return nil }
    guard arguments[1] == "notify" else { return nil }
    guard let tool = ToolKind.fromCLIArgument(arguments[2]) else { return nil }

    let rawState = arguments[3].lowercased()
    let status: ToolActivityState?
    let eventType: String

    switch rawState {
    case "running":
        status = .running
        eventType = "status_changed"
    case "awaiting_input", "awaiting-input", "awaiting", "input":
        status = .awaitingInput
        eventType = "status_changed"
    case "idle":
        status = .idle
        eventType = "status_changed"
    case "unknown":
        status = .unknown
        eventType = "status_changed"
    case "start", "started", "session_started":
        status = .running
        eventType = "session_started"
    case "end", "ended", "stop", "stopped", "session_end":
        status = nil
        eventType = "session_end"
    case "sessionstart", "session_start", "startup", "resume", "clear":
        status = .running
        eventType = "session_start"
    case "sessionend", "exit", "logout":
        status = nil
        eventType = "session_end"
    case "beforeagent", "before_agent", "beforemodel", "before_model", "beforetool", "before_tool", "beforetoolselection", "before_tool_selection", "aftermodel", "after_model", "aftertool", "after_tool":
        status = .running
        eventType = rawState
    case "afteragent", "after_agent", "notification", "toolpermission", "tool_permission":
        status = .awaitingInput
        eventType = rawState
    default:
        return nil
    }

    var metadata: [String: String] = [:]
    if arguments.count > 4 {
        for token in arguments.dropFirst(4) {
            guard let separator = token.firstIndex(of: "=") else { continue }
            let key = String(token[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(token[token.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty {
                metadata[key] = value
            }
        }
    }

    let parentPID = getppid()
    let pid = parentPID > 0 ? parentPID : getpid()
    let sessionID = metadata["session_id"] ?? "\(tool.rawValue)-\(pid)"
    let notes = metadata["hook_event_name"] ?? "vibebar-notify"

    return NotifyConfig(
        tool: tool,
        status: status,
        eventType: eventType,
        sessionID: sessionID,
        pid: pid,
        parentPID: getpid(),
        cwd: FileManager.default.currentDirectoryPath,
        notes: notes,
        metadata: metadata
    )
}

private func agentSocketPath() -> String {
    if let custom = ProcessInfo.processInfo.environment["VIBEBAR_AGENT_SOCKET"]?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
        return custom
    }
    return VibeBarPaths.agentSocketURL.path
}

private func sendEventToAgent(_ event: AgentEvent, socketPath: String) -> Bool {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601

    guard let payload = try? encoder.encode(event),
          var line = String(data: payload, encoding: .utf8)
    else {
        return false
    }
    line += "\n"

    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return false }
    defer { close(fd) }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let maxPathLength = MemoryLayout.size(ofValue: addr.sun_path)
    let utf8Path = socketPath.utf8CString
    guard utf8Path.count <= maxPathLength else {
        return false
    }

    withUnsafeMutablePointer(to: &addr.sun_path) { sunPathPtr in
        _ = utf8Path.withUnsafeBufferPointer { pathPtr in
            memcpy(sunPathPtr, pathPtr.baseAddress, pathPtr.count)
        }
    }

    let connectResult = withUnsafePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
            connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.stride))
        }
    }

    guard connectResult == 0 else { return false }
    let bytes = Array(line.utf8)
    var written = 0
    while written < bytes.count {
        let chunk = bytes.withUnsafeBytes { ptr in
            let base = ptr.baseAddress!.assumingMemoryBound(to: UInt8.self)
            return write(fd, base.advanced(by: written), bytes.count - written)
        }
        if chunk < 0 {
            if errno == EINTR { continue }
            return false
        }
        written += chunk
    }
    return true
}

private func handleNotifyCommand(arguments: [String]) -> Int32? {
    guard let config = parseNotify(arguments: arguments) else { return nil }

    let source: AgentEventSource = switch config.tool {
    case .aider:
        .aiderNotify
    case .gemini:
        .geminiHook
    case .githubCopilot:
        .copilotHook
    default:
        .unknown
    }
    let event = AgentEvent(
        source: source,
        tool: config.tool,
        sessionID: config.sessionID,
        eventType: config.eventType,
        status: config.status,
        timestamp: Date(),
        pid: config.pid,
        parentPID: config.parentPID,
        cwd: config.cwd,
        command: [config.tool.executable],
        notes: config.notes,
        metadata: config.metadata
    )

    let socketPath = agentSocketPath()
    guard sendEventToAgent(event, socketPath: socketPath) else {
        fputs("vibebar: 无法发送通知到 agent: \(socketPath)\n", stderr)
        return 3
    }
    return 0
}

private func wrapperVersion() -> String {
    let versionURL = VibeBarPaths.appSupportDirectory
        .appendingPathComponent("bin", isDirectory: true)
        .appendingPathComponent("vibebar.version", isDirectory: false)
    if let raw = try? String(contentsOf: versionURL, encoding: .utf8) {
        let version = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !version.isEmpty {
            return version
        }
    }

    if let manifestVersion = ComponentVersions.wrapperVersion(),
       !manifestVersion.isEmpty {
        return manifestVersion
    }

    if let bundleVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
       !bundleVersion.isEmpty {
        return bundleVersion
    }

    return "dev"
}

private func handleMetaCommand(arguments: [String]) -> Int32? {
    guard arguments.count >= 2 else { return nil }
    switch arguments[1] {
    case "--version", "-v", "version":
        print(wrapperVersion())
        return 0
    case "--help", "-h", "help":
        printUsage()
        return 0
    default:
        return nil
    }
}

private func printUsage() {
    let usage = """
    用法:
      vibebar <claude|codex|opencode|aider|gemini|copilot> [--] [原命令参数...]
      vibebar notify <claude|codex|opencode|aider|gemini|copilot> <running|awaiting_input|idle|unknown|start|end>

    示例:
      vibebar claude
      vibebar codex -- --model gpt-5-codex
      vibebar opencode
      vibebar aider --model sonnet
      vibebar gemini -p "explain this repo"
      vibebar copilot
      vibebar notify aider awaiting_input
      vibebar notify gemini session_start session_id=abc123 hook_event_name=SessionStart
    """
    print(usage)
}

if let code = handleMetaCommand(arguments: CommandLine.arguments) {
    exit(code)
} else if let code = handleNotifyCommand(arguments: CommandLine.arguments) {
    exit(code)
} else if let config = parseCLI(arguments: CommandLine.arguments) {
    let runner = WrapperRunner(config: config)
    exit(runner.run())
} else {
    printUsage()
    exit(2)
}
