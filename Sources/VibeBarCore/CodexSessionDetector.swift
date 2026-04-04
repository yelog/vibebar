import Foundation

public struct CodexSessionDetector: AgentDetector {
    private struct SessionIndexEntry: Decodable, Sendable {
        let id: String
        let threadName: String?
        let updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case id
            case threadName = "thread_name"
            case updatedAt = "updated_at"
        }
    }

    private struct RolloutSummary: Sendable {
        var id: String
        var startedAt: Date?
        var updatedAt: Date?
        var lastActivityAt: Date?
        var awaitingInputAt: Date?
        var cwd: String?
        var source: SessionOriginKind
        var originator: String?
        var lastUserMessage: String?
        var rolloutPath: String?
    }

    private struct ProcessCandidate: Sendable {
        let pid: Int32
        let ppid: Int32
        let elapsedSeconds: Int
        let command: String
        let args: String
        let cwd: String?
        let threadID: String?
        let terminalContext: TerminalContext?
    }

    private let baseDirectory: URL
    private let recentSessionWindow: TimeInterval
    private let runningWindow: TimeInterval
    private let awaitingWindow: TimeInterval

    public init(
        baseDirectory: URL? = nil,
        recentSessionWindow: TimeInterval = 90,
        runningWindow: TimeInterval = 8,
        awaitingWindow: TimeInterval = 30
    ) {
        if let baseDirectory {
            self.baseDirectory = baseDirectory
        } else if let raw = ProcessInfo.processInfo.environment["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty {
            self.baseDirectory = URL(fileURLWithPath: UsageLoaderSupport.expandedPath(raw), isDirectory: true)
        } else {
            self.baseDirectory = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex", isDirectory: true)
        }

        self.recentSessionWindow = recentSessionWindow
        self.runningWindow = runningWindow
        self.awaitingWindow = awaitingWindow
    }

    public func detectSessions() async -> [SessionSnapshot] {
        let context = DetectorSupport.makeContext()
        return await detectSessions(context: context)
    }

    func detectSessions(
        context: DetectorSupport.DetectionContext,
        now: Date = Date()
    ) async -> [SessionSnapshot] {
        let processCandidates = await loadProcessCandidates(context: context)
        let sessionIndex = loadSessionIndex()
        let recentIndexEntries = sessionIndex.values.filter {
            now.timeIntervalSince($0.updatedAt) <= recentSessionWindow || processCandidates.byThreadID[$0.id] != nil
        }

        var candidateIDs = Set(recentIndexEntries.map(\.id))
        candidateIDs.formUnion(processCandidates.byThreadID.keys)
        guard !candidateIDs.isEmpty else { return [] }

        let rollouts = loadRolloutSummaries(candidateIDs: candidateIDs)
        candidateIDs.formUnion(rollouts.keys)

        return candidateIDs.compactMap { id in
            makeSessionSnapshot(
                sessionID: id,
                indexEntry: sessionIndex[id],
                rollout: rollouts[id],
                processCandidate: processCandidate(
                    for: id,
                    cwd: rollouts[id]?.cwd,
                    candidates: processCandidates
                ),
                now: now
            )
        }
    }

    // MARK: - Process correlation

    private func loadProcessCandidates(
        context: DetectorSupport.DetectionContext
    ) async -> (all: [ProcessCandidate], byThreadID: [String: ProcessCandidate], byCwd: [String: [ProcessCandidate]]) {
        let rawCandidates = context.processes.filter { entry in
            let loweredCommand = entry.commandName
            let loweredArgs = entry.args.lowercased()
            return loweredCommand == "codex" ||
                loweredArgs.contains(" codex") ||
                loweredArgs.contains("/codex") ||
                loweredArgs.contains("gpt-5-codex") ||
                loweredArgs.contains("codex ")
        }

        let cwds = await DetectorSupport.bulkGetCwds(pids: rawCandidates.map(\.pid))

        var candidates: [ProcessCandidate] = []
        for process in rawCandidates {
            let environment = await DetectorSupport.getProcessEnvironment(pid: process.pid)
            let originHint = origin(from: environment["CODEX_INTERNAL_ORIGINATOR_OVERRIDE"] ?? environment["TERM_PROGRAM"])
            let terminalContext = await TerminalContextResolver.resolve(
                process: process,
                context: context,
                originHint: originHint
            )

            candidates.append(
                ProcessCandidate(
                    pid: process.pid,
                    ppid: process.ppid,
                    elapsedSeconds: process.elapsedSeconds,
                    command: process.command,
                    args: process.args,
                    cwd: cwds[process.pid],
                    threadID: environment["CODEX_THREAD_ID"],
                    terminalContext: terminalContext
                )
            )
        }

        var byThreadID: [String: ProcessCandidate] = [:]
        var byCwd: [String: [ProcessCandidate]] = [:]

        for candidate in candidates {
            if let threadID = candidate.threadID, !threadID.isEmpty {
                byThreadID[threadID] = candidate
            }
            if let cwd = candidate.cwd, !cwd.isEmpty {
                byCwd[cwd, default: []].append(candidate)
            }
        }

        return (candidates, byThreadID, byCwd)
    }

    private func processCandidate(
        for sessionID: String,
        cwd: String?,
        candidates: (all: [ProcessCandidate], byThreadID: [String: ProcessCandidate], byCwd: [String: [ProcessCandidate]])
    ) -> ProcessCandidate? {
        if let direct = candidates.byThreadID[sessionID] {
            return direct
        }

        guard let cwd,
              let matches = candidates.byCwd[cwd],
              matches.count == 1 else {
            return nil
        }

        return matches[0]
    }

    // MARK: - Session index

    private func loadSessionIndex() -> [String: SessionIndexEntry] {
        let url = baseDirectory.appendingPathComponent("session_index.jsonl", isDirectory: false)
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [:] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let date = DetectorSupport.parseISO8601(value) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date")
            }
            return date
        }

        var result: [String: SessionIndexEntry] = [:]
        for line in content.split(whereSeparator: \.isNewline) {
            let raw = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty, let data = raw.data(using: .utf8) else { continue }
            guard let entry = try? decoder.decode(SessionIndexEntry.self, from: data) else { continue }
            result[entry.id] = entry
        }
        return result
    }

    // MARK: - Rollout parsing

    private func loadRolloutSummaries(candidateIDs: Set<String>) -> [String: RolloutSummary] {
        guard !candidateIDs.isEmpty else { return [:] }

        let sessionsRoot = baseDirectory.appendingPathComponent("sessions", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: sessionsRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return [:]
        }

        var result: [String: RolloutSummary] = [:]
        for case let fileURL as URL in enumerator {
            guard fileURL.lastPathComponent.hasPrefix("rollout-"),
                  fileURL.pathExtension == "jsonl" else {
                continue
            }

            let filename = fileURL.lastPathComponent
            guard candidateIDs.contains(where: { filename.contains($0) }) else { continue }
            guard let summary = summarizeRollout(fileURL: fileURL) else { continue }
            result[summary.id] = summary
        }

        return result
    }

    private func summarizeRollout(fileURL: URL) -> RolloutSummary? {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }

        var summary: RolloutSummary?
        for line in content.split(whereSeparator: \.isNewline) {
            let rawLine = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawLine.isEmpty, let data = rawLine.data(using: .utf8) else { continue }
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            let lineTimestamp = (object["timestamp"] as? String).flatMap(DetectorSupport.parseISO8601)
            let entryType = (object["type"] as? String) ?? ""
            let payload = object["payload"] as? [String: Any]
            let loweredRaw = rawLine.lowercased()

            if entryType == "session_meta",
               let payload,
               let id = payload["id"] as? String {
                var current = summary ?? RolloutSummary(id: id, source: .unknown)
                current.id = id
                current.startedAt = current.startedAt ?? lineTimestamp ?? (payload["timestamp"] as? String).flatMap(DetectorSupport.parseISO8601)
                current.updatedAt = newer(current.updatedAt, lineTimestamp)
                current.cwd = current.cwd ?? payload["cwd"] as? String
                current.source = origin(from: payload["source"] as? String)
                current.originator = payload["originator"] as? String
                current.rolloutPath = fileURL.path
                summary = current
                continue
            }

            guard var current = summary else { continue }
            current.updatedAt = newer(current.updatedAt, lineTimestamp)
            current.rolloutPath = fileURL.path

            if entryType == "turn_context", let payload {
                current.cwd = current.cwd ?? payload["cwd"] as? String
            }

            if entryType == "event_msg",
               let payloadType = payload?["type"] as? String {
                switch payloadType {
                case "user_message":
                    current.lastUserMessage = payload?["message"] as? String ?? current.lastUserMessage
                    current.lastActivityAt = newer(current.lastActivityAt, lineTimestamp)
                case "agent_reasoning", "token_count", "plan_updated":
                    current.lastActivityAt = newer(current.lastActivityAt, lineTimestamp)
                default:
                    break
                }
            }

            if entryType == "response_item",
               let responseType = payload?["type"] as? String {
                switch responseType {
                case "function_call", "reasoning", "function_call_output":
                    current.lastActivityAt = newer(current.lastActivityAt, lineTimestamp)
                case "message":
                    if (payload?["role"] as? String) == "assistant" {
                        current.lastActivityAt = newer(current.lastActivityAt, lineTimestamp)
                    }
                default:
                    break
                }
            }

            if loweredRaw.contains("request_user_input") ||
                loweredRaw.contains("ask_user_question") ||
                loweredRaw.contains("permissionrequest") ||
                loweredRaw.contains("exitplanmode") ||
                loweredRaw.contains("\"type\":\"question\"") {
                current.awaitingInputAt = newer(current.awaitingInputAt, lineTimestamp)
            }

            summary = current
        }

        return summary
    }

    // MARK: - Snapshot building

    private func makeSessionSnapshot(
        sessionID: String,
        indexEntry: SessionIndexEntry?,
        rollout: RolloutSummary?,
        processCandidate: ProcessCandidate?,
        now: Date
    ) -> SessionSnapshot? {
        let updatedAt = latest(
            indexEntry?.updatedAt,
            rollout?.updatedAt,
            rollout?.lastActivityAt,
            rollout?.awaitingInputAt
        )

        guard processCandidate != nil || (updatedAt != nil && now.timeIntervalSince(updatedAt!) <= recentSessionWindow) else {
            return nil
        }

        let status = resolveStatus(
            indexEntry: indexEntry,
            rollout: rollout,
            processCandidate: processCandidate,
            now: now
        )
        let title = indexEntry?.threadName ?? rollout?.lastUserMessage
        let currentTask = rollout?.lastUserMessage ?? indexEntry?.threadName
        let terminalContext = processCandidate?.terminalContext
        let command = command(for: processCandidate)

        return SessionSnapshot(
            id: "codex-session-\(sessionID)",
            tool: .codex,
            pid: processCandidate?.pid ?? 0,
            parentPID: processCandidate?.ppid,
            status: status,
            source: .sessionFile,
            startedAt: rollout?.startedAt ?? startedAt(for: processCandidate, now: now) ?? updatedAt ?? now,
            updatedAt: updatedAt ?? now,
            lastOutputAt: status == .running ? (rollout?.lastActivityAt ?? updatedAt) : nil,
            lastInputAt: status == .awaitingInput ? (rollout?.awaitingInputAt ?? updatedAt) : nil,
            cwd: rollout?.cwd ?? processCandidate?.cwd,
            command: command,
            notes: composeNotes(rollout: rollout, processCandidate: processCandidate),
            title: title,
            currentTask: currentTask,
            terminalContext: terminalContext
        )
    }

    private func resolveStatus(
        indexEntry: SessionIndexEntry?,
        rollout: RolloutSummary?,
        processCandidate: ProcessCandidate?,
        now: Date
    ) -> ToolActivityState {
        if let awaitingInputAt = rollout?.awaitingInputAt,
           now.timeIntervalSince(awaitingInputAt) <= awaitingWindow {
            return .awaitingInput
        }

        let latestActivity = latest(rollout?.lastActivityAt, rollout?.updatedAt, indexEntry?.updatedAt)
        if let latestActivity, now.timeIntervalSince(latestActivity) <= runningWindow {
            return .running
        }

        if processCandidate != nil {
            return .idle
        }

        if let latestActivity, now.timeIntervalSince(latestActivity) <= recentSessionWindow {
            return .running
        }

        return .unknown
    }

    private func startedAt(for candidate: ProcessCandidate?, now: Date) -> Date? {
        guard let candidate else { return nil }
        return now.addingTimeInterval(-TimeInterval(candidate.elapsedSeconds))
    }

    private func command(for candidate: ProcessCandidate?) -> [String] {
        guard let candidate else { return ["codex"] }
        if !candidate.args.isEmpty {
            return [candidate.args]
        }
        return [candidate.command]
    }

    private func composeNotes(
        rollout: RolloutSummary?,
        processCandidate: ProcessCandidate?
    ) -> String {
        var parts = ["codex-session-file"]
        if let rolloutPath = rollout?.rolloutPath {
            parts.append("rollout=\(rolloutPath)")
        }
        if let originator = rollout?.originator, !originator.isEmpty {
            parts.append("originator=\(originator)")
        }
        if let processCandidate {
            parts.append("pid=\(processCandidate.pid)")
        }
        return parts.joined(separator: " | ")
    }

    private func latest(_ dates: Date?...) -> Date? {
        dates.compactMap { $0 }.max()
    }

    private func newer(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            return lhs > rhs ? lhs : rhs
        case let (lhs?, nil):
            return lhs
        case let (nil, rhs?):
            return rhs
        case (nil, nil):
            return nil
        }
    }

    private func origin(from rawValue: String?) -> SessionOriginKind {
        guard let rawValue = rawValue?.lowercased(), !rawValue.isEmpty else {
            return .unknown
        }
        if rawValue.contains("cli") {
            return .cli
        }
        if rawValue.contains("desktop") || rawValue.contains("vscode") || rawValue.contains("ide") {
            return .desktop
        }
        return .unknown
    }
}
