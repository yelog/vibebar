import Darwin
import Foundation
import VibeBarCore

private struct AgentConfig {
    var socketPath: String = VibeBarPaths.agentSocketURL.path
    var verbose: Bool = false
    var printSocketPathOnly: Bool = false
}

private final class AgentServer: @unchecked Sendable {
    private let config: AgentConfig
    private let store = SessionFileStore()
    private let interactionStore = InteractionStore()
    private let decoder: JSONDecoder
    private var listenFD: Int32 = -1
    private let stateQueue = DispatchQueue(label: "vibebar.agent.state")
    private var brokerState = InteractionBrokerState()
    private var pendingResponders: [String: PendingResponder] = [:]
    private var earlyInteractionResponses: [String: AgentInteractionResponse] = [:]

    private final class PendingResponder {
        let semaphore = DispatchSemaphore(value: 0)
        var response: AgentInteractionResponse?
    }

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

            DispatchQueue.global(qos: .utility).async { [weak self] in
                defer { close(clientFD) }
                self?.handleClient(fd: clientFD)
            }
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
            handleLine(String(line), fd: fd)
        }
    }

    private func handleLine(_ line: String, fd: Int32) {
        let raw = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        guard let data = raw.data(using: .utf8) else { return }

        do {
            if let envelope = try? decoder.decode(AgentEnvelope.self, from: data) {
                switch envelope.kind {
                case .event:
                    if let event = envelope.event {
                        apply(event: event)
                    }
                case .interactionRequest:
                    if let request = envelope.request {
                        handleInteractionRequest(request, fd: fd)
                    }
                case .interactionResponse:
                    if let response = envelope.response {
                        applyInteractionResponse(response)
                    }
                }
                return
            }

            let event = try decoder.decode(AgentEvent.self, from: data)
            apply(event: event)
        } catch {
            fputs("vibebar-agent: 无法解析事件: \(raw)\n", stderr)
        }
    }

    private func apply(event: AgentEvent) {
        let now = event.timestamp ?? Date()
        let sessionID = event.compositeSessionID
        let previous = stateQueue.sync {
            store.load(sessionID: sessionID)
        }
        let reduction = AgentEventReducer.reduce(event: event, previous: previous)

        if reduction.shouldDeleteSession {
            stateQueue.sync {
                store.delete(sessionID: sessionID)
                interactionStore.deleteAll(sessionID: sessionID)
            }
            return
        }

        guard let status = reduction.status else { return }
        let processChain = event.pid.map { storeProcessChain(for: $0) } ?? []
        let terminalContext = TerminalContextResolver.merge(
            primary: TerminalContextResolver.resolve(
                metadata: event.metadata,
                processChain: processChain,
                originHint: originHint(for: event)
            ),
            fallback: previous?.terminalContext
        )

        var snapshot = previous ?? SessionSnapshot(
            id: sessionID,
            tool: event.tool,
            pid: event.pid ?? 0,
            parentPID: event.parentPID,
            status: status,
            source: .plugin,
            startedAt: now,
            updatedAt: now,
            statusSince: now,
            lastOutputAt: nil,
            lastInputAt: nil,
            cwd: event.cwd,
            command: event.command ?? [event.tool.executable],
            notes: nil,
            title: nil,
            titleSource: nil,
            currentTask: nil,
            lastUserMessage: nil,
            runningSummary: nil,
            pendingInteractionID: nil,
            terminalContext: terminalContext
        )

        snapshot.tool = event.tool
        snapshot.pid = event.pid ?? snapshot.pid
        snapshot.parentPID = event.parentPID ?? snapshot.parentPID
        snapshot.source = .plugin
        snapshot.status = status
        updateStatusSince(
            snapshot: &snapshot,
            previousStatus: previous?.status,
            previousUpdatedAt: previous?.updatedAt,
            updatedAt: now
        )
        snapshot.updatedAt = now
        snapshot.cwd = event.cwd ?? snapshot.cwd
        snapshot.command = event.command ?? snapshot.command
        snapshot.notes = composeNotes(event: event)
        let titleCandidate = resolveTitle(event: event, previous: previous)
        snapshot.title = titleCandidate.value
        snapshot.titleSource = titleCandidate.source ?? previous?.titleSource
        snapshot.currentTask = resolveCurrentTask(event: event, previous: previous)
        snapshot.lastUserMessage = resolveLastUserMessage(event: event, previous: previous)
        snapshot.runningSummary = resolveRunningSummary(event: event, previous: previous)
        snapshot.terminalContext = terminalContext

        if status == .running {
            snapshot.lastOutputAt = now
        } else if status == .awaitingInput {
            snapshot.lastInputAt = now
        }
        updateIdleSince(snapshot: &snapshot, previousStatus: previous?.status, updatedAt: now)

        do {
            try stateQueue.sync {
                try store.write(snapshot)
                // 同一 PID 可能因插件生成不同 sessionID 而存在旧文件，写入后清理。
                store.deleteOtherSessions(forPID: snapshot.pid, keeping: sessionID)
            }
        } catch {
            fputs("vibebar-agent: 写入会话失败: \(error.localizedDescription)\n", stderr)
        }
    }

    private func handleInteractionRequest(_ request: PendingInteraction, fd: Int32) {
        let request = normalizeInteractionRequest(request)
        let responder = PendingResponder()
        let now = Date()
        let timeout = max(1, request.expiresAt?.timeIntervalSince(now) ?? 60 * 60 * 24)

        let drained = stateQueue.sync { () -> (PendingInteraction, PendingResponder?)? in
            let drainedInteraction = brokerState.begin(request)
            pendingResponders[request.id] = responder
            try? interactionStore.write(request)
            markPendingInteraction(
                sessionID: request.sessionID,
                interactionID: request.id,
                currentTask: request.title ?? request.message,
                updatedAt: request.requestedAt
            )

            if let earlyResponse = earlyInteractionResponses.removeValue(forKey: request.id) {
                responder.response = earlyResponse
                responder.semaphore.signal()
            }
 
            guard let drainedInteraction else { return nil }
            let drainedResponder = pendingResponders.removeValue(forKey: drainedInteraction.id)
            _ = brokerState.disconnect(requestID: drainedInteraction.id)
            interactionStore.delete(id: drainedInteraction.id)
            earlyInteractionResponses.removeValue(forKey: drainedInteraction.id)
            clearPendingInteraction(
                sessionID: drainedInteraction.sessionID,
                interactionID: drainedInteraction.id,
                updatedAt: Date()
            )
            return (drainedInteraction, drainedResponder)
        }

        if let (drainedInteraction, drainedResponder) = drained {
            let response = AgentInteractionResponse(
                requestID: drainedInteraction.id,
                decision: conservativeDecision(for: drainedInteraction, reason: "superseded")
            )
            drainedResponder?.response = response
            drainedResponder?.semaphore.signal()
        }

        let waitResult = responder.semaphore.wait(timeout: .now() + timeout)
        let response = stateQueue.sync { () -> AgentInteractionResponse in
            defer {
                pendingResponders.removeValue(forKey: request.id)
                interactionStore.delete(id: request.id)
                clearPendingInteraction(
                    sessionID: request.sessionID,
                    interactionID: request.id,
                    updatedAt: Date()
                )
            }

            if waitResult == .success, let response = responder.response {
                _ = brokerState.resolve(requestID: request.id, response: response)
                return response
            }

            _ = brokerState.timeout(requestID: request.id)
            return AgentInteractionResponse(
                requestID: request.id,
                decision: conservativeDecision(for: request, reason: "timeout")
            )
        }

        writeEnvelope(AgentEnvelope(kind: .interactionResponse, response: response), to: fd)
    }

    private func applyInteractionResponse(_ response: AgentInteractionResponse) {
        stateQueue.sync {
            if let responder = pendingResponders[response.requestID] {
                let interactionSessionID = brokerState.resolve(requestID: response.requestID, response: response)?.sessionID
                    ?? interactionStore.load(id: response.requestID)?.sessionID
                interactionStore.delete(id: response.requestID)
                responder.response = response
                responder.semaphore.signal()
                clearPendingInteraction(
                    sessionID: interactionSessionID,
                    interactionID: response.requestID,
                    updatedAt: Date()
                )
                return
            }

            if let interactionSessionID = brokerState.resolve(requestID: response.requestID, response: response)?.sessionID
                ?? interactionStore.load(id: response.requestID)?.sessionID {
                interactionStore.delete(id: response.requestID)
                clearPendingInteraction(
                    sessionID: interactionSessionID,
                    interactionID: response.requestID,
                    updatedAt: Date()
                )
                return
            }

            guard !brokerState.hasSeen(requestID: response.requestID) else { return }
            earlyInteractionResponses[response.requestID] = response
        }
    }

    private func resolveStatus(event: AgentEvent, previous: SessionSnapshot?) -> ToolActivityState {
        if let status = event.status {
            return status
        }

        let loweredType = event.eventType.lowercased()
        if loweredType == "afteragent" || loweredType == "after_agent" {
            return .awaitingInput
        }
        if loweredType == "sessionstart" || loweredType == "session_start" || loweredType == "beforeagent" || loweredType == "before_agent" {
            return .running
        }
        if loweredType == "notification" {
            let notificationType = event.metadata["notification_type"]?.lowercased() ?? ""
            if notificationType.contains("permission") {
                return .awaitingInput
            }
        }
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

    private func composeNotes(event: AgentEvent) -> String {
        var notes: [String] = []
        if let eventNotes = event.notes, !eventNotes.isEmpty {
            notes.append(eventNotes)
        } else {
            notes.append("\(event.source.rawValue):\(event.eventType)")
        }
        if let transcriptPath = event.metadata["transcript_path"], !transcriptPath.isEmpty {
            notes.append("transcript=\(transcriptPath)")
        }
        return notes.joined(separator: " | ")
    }

    private struct TitleCandidate {
        let value: String?
        let source: SessionTitleSource?
    }

    private func resolveTitle(event: AgentEvent, previous: SessionSnapshot?) -> TitleCandidate {
        let explicitKeys = [
            "title",
            "thread_name",
            "task_name",
            "custom_title",
        ]

        for key in explicitKeys {
            if let value = event.metadata[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return TitleCandidate(value: value, source: .explicit)
            }
        }

        if let previousTitle = previous?.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !previousTitle.isEmpty {
            return TitleCandidate(value: previousTitle, source: previous?.titleSource)
        }

        let derivedKeys = [
            "first_user_message",
            "prompt",
            "question",
            "message",
        ]

        for key in derivedKeys {
            if let value = event.metadata[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return TitleCandidate(value: value, source: .derived)
            }
        }

        return TitleCandidate(value: nil, source: previous?.titleSource)
    }

    private func resolveCurrentTask(event: AgentEvent, previous: SessionSnapshot?) -> String? {
        let keys = [
            "current_task",
            "prompt",
            "task_name",
            "question",
            "message",
            "tool_name",
            "title",
            "thread_name",
            "first_user_message",
        ]

        for key in keys {
            if let value = event.metadata[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }

        return previous?.currentTask ?? previous?.title
    }

    private func resolveLastUserMessage(event: AgentEvent, previous: SessionSnapshot?) -> String? {
        let keys = [
            "last_user_message",
            "user_message",
            "first_user_message",
            "prompt",
        ]

        for key in keys {
            if let value = event.metadata[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }

        return previous?.lastUserMessage
    }

    private func resolveRunningSummary(event: AgentEvent, previous: SessionSnapshot?) -> String? {
        let userMessageCandidates = Set(
            [
                event.metadata["last_user_message"],
                event.metadata["user_message"],
                event.metadata["prompt"],
                event.metadata["question"],
                event.metadata["message"],
                previous?.lastUserMessage,
            ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        )

        let keys = [
            "running_summary",
            "tool_input_summary",
            "current_task",
            "tool_name",
            "tool",
            "action",
            "operation",
            "step",
        ]

        for key in keys {
            if let value = event.metadata[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty,
               !userMessageCandidates.contains(value) {
                return value
            }
        }

        return previous?.runningSummary
    }

    private func originHint(for event: AgentEvent) -> SessionOriginKind {
        if event.tool == .codex,
           let raw = event.metadata["source"] ?? event.metadata["thread_source"] {
            let lowered = raw.lowercased()
            if lowered.contains("cli") {
                return .cli
            }
            if lowered.contains("desktop") || lowered.contains("vscode") || lowered.contains("ide") {
                return .desktop
            }
        }
        return .unknown
    }

    private func storeProcessChain(for pid: Int32) -> [DetectorSupport.ProcEntry] {
        let context = DetectorSupport.makeContext()
        return context.parentChain(startingAt: pid)
    }

    private func normalizeInteractionRequest(_ request: PendingInteraction) -> PendingInteraction {
        guard !request.sessionID.hasPrefix("plugin-"),
              let source = request.transportContext["source"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !source.isEmpty else {
            return request
        }

        var normalized = request
        normalized.sessionID = "plugin-\(source)-\(request.sessionID)"
        return normalized
    }

    private func markPendingInteraction(
        sessionID: String,
        interactionID: String,
        currentTask: String,
        updatedAt: Date
    ) {
        guard var snapshot = store.load(sessionID: sessionID) else { return }
        snapshot.pendingInteractionID = interactionID
        snapshot.currentTask = currentTask
        snapshot.runningSummary = currentTask
        let previousStatus = snapshot.status
        snapshot.status = .awaitingInput
        updateStatusSince(
            snapshot: &snapshot,
            previousStatus: previousStatus,
            previousUpdatedAt: snapshot.updatedAt,
            updatedAt: updatedAt
        )
        snapshot.updatedAt = updatedAt
        snapshot.idleSince = nil
        snapshot.lastInputAt = updatedAt
        try? store.write(snapshot)
    }

    private func clearPendingInteraction(
        sessionID: String?,
        interactionID: String,
        updatedAt: Date
    ) {
        guard let sessionID,
              var snapshot = store.load(sessionID: sessionID),
              snapshot.pendingInteractionID == interactionID else {
            return
        }
        snapshot.pendingInteractionID = nil
        let previousStatus = snapshot.status
        if snapshot.status == .awaitingInput {
            snapshot.status = .running
            snapshot.lastOutputAt = updatedAt
        }
        updateStatusSince(
            snapshot: &snapshot,
            previousStatus: previousStatus,
            previousUpdatedAt: snapshot.updatedAt,
            updatedAt: updatedAt
        )
        snapshot.updatedAt = updatedAt
        snapshot.idleSince = nil
        try? store.write(snapshot)
    }

    private func updateStatusSince(
        snapshot: inout SessionSnapshot,
        previousStatus: ToolActivityState?,
        previousUpdatedAt: Date?,
        updatedAt: Date
    ) {
        if previousStatus != snapshot.status {
            snapshot.statusSince = updatedAt
            return
        }
        guard snapshot.statusSince == nil else { return }
        switch snapshot.status {
        case .idle:
            snapshot.statusSince = snapshot.idleSince ?? previousUpdatedAt ?? snapshot.startedAt
        case .awaitingInput:
            snapshot.statusSince = snapshot.lastInputAt ?? previousUpdatedAt ?? snapshot.startedAt
        case .running:
            snapshot.statusSince = snapshot.startedAt
        case .unknown:
            snapshot.statusSince = previousUpdatedAt ?? snapshot.startedAt
        }
    }

    private func updateIdleSince(
        snapshot: inout SessionSnapshot,
        previousStatus: ToolActivityState?,
        updatedAt: Date
    ) {
        switch snapshot.status {
        case .idle:
            if previousStatus != .idle || snapshot.idleSince == nil {
                snapshot.idleSince = updatedAt
            }
        case .running, .awaitingInput, .unknown:
            snapshot.idleSince = nil
        }
    }

    private func writeEnvelope(_ envelope: AgentEnvelope, to fd: Int32) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(envelope) else { return }
        _ = data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return 0 }
            return write(fd, baseAddress, buffer.count)
        }
        _ = "\n".utf8CString.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return 0 }
            return write(fd, baseAddress, 1)
        }
    }

    private func conservativeDecision(
        for interaction: PendingInteraction,
        reason: String
    ) -> InteractionDecision {
        if interaction.tool == .codex {
            return CodexInteractionBridge.defaultDecision(for: interaction, reason: reason)
                ?? InteractionDecision(behavior: .deny, metadata: ["reason": reason])
        }

        return InteractionDecision(
            behavior: .deny,
            metadata: ["reason": reason]
        )
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
