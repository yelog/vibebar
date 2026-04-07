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
        var firstUserMessage: String?
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

    typealias EnvironmentProvider = @Sendable (Int32) async -> [String: String]
    typealias CWDProvider = @Sendable ([Int32]) async -> [Int32: String]

    private let baseDirectory: URL
    private let recentSessionWindow: TimeInterval
    private let runningWindow: TimeInterval
    private let awaitingWindow: TimeInterval
    private let processCorrelationWindow: TimeInterval
    private let environmentProvider: EnvironmentProvider
    private let cwdProvider: CWDProvider

    public init(
        baseDirectory: URL? = nil,
        recentSessionWindow: TimeInterval = 90,
        runningWindow: TimeInterval = 8,
        awaitingWindow: TimeInterval = 30
    ) {
        self.init(
            baseDirectory: baseDirectory,
            recentSessionWindow: recentSessionWindow,
            runningWindow: runningWindow,
            awaitingWindow: awaitingWindow,
            processCorrelationWindow: 30 * 60,
            environmentProvider: { pid in
                await DetectorSupport.getProcessEnvironment(pid: pid)
            },
            cwdProvider: { pids in
                await DetectorSupport.bulkGetCwds(pids: pids)
            }
        )
    }

    init(
        baseDirectory: URL? = nil,
        recentSessionWindow: TimeInterval = 90,
        runningWindow: TimeInterval = 8,
        awaitingWindow: TimeInterval = 30,
        processCorrelationWindow: TimeInterval = 30 * 60,
        environmentProvider: @escaping EnvironmentProvider,
        cwdProvider: @escaping CWDProvider
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
        self.processCorrelationWindow = processCorrelationWindow
        self.environmentProvider = environmentProvider
        self.cwdProvider = cwdProvider
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

        // When process candidates exist but none matched via CODEX_THREAD_ID or
        // recent index entries (common: CODEX_THREAD_ID is set after exec and invisible
        // to ps eww, and index entries expire after recentSessionWindow), scan recent
        // rollout files by CWD to discover session IDs for running processes.
        let unmatchedCWDs = processCandidates.byCwd.keys.filter { cwd in
            // A CWD is "unmatched" if no candidateID's rollout is known to use it yet.
            // At this point we haven't loaded rollouts, so check if any process at
            // this CWD was already matched by threadID.
            let processesAtCwd = processCandidates.byCwd[cwd] ?? []
            return !processesAtCwd.contains { p in
                p.threadID != nil && candidateIDs.contains(p.threadID!)
            }
        }

        if !unmatchedCWDs.isEmpty {
            let cwdMatches = scanRolloutsByCwd(cwds: Set(unmatchedCWDs))
            candidateIDs.formUnion(cwdMatches.keys)
        }

        guard !candidateIDs.isEmpty else { return [] }

        let rollouts = loadRolloutSummaries(candidateIDs: candidateIDs)
        candidateIDs.formUnion(rollouts.keys)
        let assignedCandidates = assignedProcessCandidates(
            candidateIDs: candidateIDs,
            rollouts: rollouts,
            candidates: processCandidates,
            now: now
        )

        return candidateIDs.compactMap { id in
            makeSessionSnapshot(
                sessionID: id,
                indexEntry: sessionIndex[id],
                rollout: rollouts[id],
                processCandidate: assignedCandidates[id],
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

        let cwds = await cwdProvider(rawCandidates.map(\.pid))

        var candidates: [ProcessCandidate] = []
        for process in rawCandidates {
            let environment = await environmentProvider(process.pid)
            let originHint = originHintFromEnvironment(environment["CODEX_INTERNAL_ORIGINATOR_OVERRIDE"])
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

    private func assignedProcessCandidates(
        candidateIDs: Set<String>,
        rollouts: [String: RolloutSummary],
        candidates: (all: [ProcessCandidate], byThreadID: [String: ProcessCandidate], byCwd: [String: [ProcessCandidate]]),
        now: Date
    ) -> [String: ProcessCandidate] {
        var assignments: [String: ProcessCandidate] = [:]
        var usedPIDs = Set<Int32>()

        for sessionID in candidateIDs.sorted() {
            guard let direct = candidates.byThreadID[sessionID] else { continue }
            assignments[sessionID] = direct
            usedPIDs.insert(direct.pid)
        }

        var sessionIDsByCwd: [String: [String]] = [:]
        for sessionID in candidateIDs where assignments[sessionID] == nil {
            guard let cwd = rollouts[sessionID]?.cwd, !cwd.isEmpty else { continue }
            sessionIDsByCwd[cwd, default: []].append(sessionID)
        }

        for (cwd, sessionIDs) in sessionIDsByCwd {
            let availableCandidates = (candidates.byCwd[cwd] ?? [])
                .filter { !usedPIDs.contains($0.pid) }
                .sorted { lhs, rhs in
                    if lhs.elapsedSeconds == rhs.elapsedSeconds {
                        return lhs.pid < rhs.pid
                    }
                    return lhs.elapsedSeconds < rhs.elapsedSeconds
                }
            let orderedSessionIDs = sessionIDs.sorted { lhs, rhs in
                let lhsDate = correlationDate(for: rollouts[lhs])
                let rhsDate = correlationDate(for: rollouts[rhs])
                if lhsDate == rhsDate {
                    return lhs < rhs
                }
                return lhsDate > rhsDate
            }

            var remainingCandidates = availableCandidates
            for sessionID in orderedSessionIDs {
                guard let matchIndex = bestCandidateIndex(
                    for: sessionID,
                    rollout: rollouts[sessionID],
                    candidates: remainingCandidates,
                    now: now
                ) else {
                    continue
                }

                let candidate = remainingCandidates.remove(at: matchIndex)
                assignments[sessionID] = candidate
                usedPIDs.insert(candidate.pid)
            }
        }

        return assignments
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

    /// Scan recent rollout files by CWD to find session IDs for running processes.
    /// Only reads the first line (session_meta) of each file to extract CWD and ID.
    /// Returns a mapping of session ID → CWD for matches.
    private func scanRolloutsByCwd(cwds: Set<String>) -> [String: String] {
        let sessionsRoot = baseDirectory.appendingPathComponent("sessions", isDirectory: true)
        let fm = FileManager.default

        // Only scan recent date directories (today + last 6 days) to limit I/O
        let calendar = Calendar.current
        let now = Date()
        var dateDirs: [URL] = []
        for dayOffset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: now) else { continue }
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            guard let year = components.year, let month = components.month, let day = components.day else { continue }
            let datePath = String(format: "%04d/%02d/%02d", year, month, day)
            dateDirs.append(sessionsRoot.appendingPathComponent(datePath, isDirectory: true))
        }

        var result: [String: String] = [:]  // sessionID → cwd

        for dateDir in dateDirs {
            guard let entries = try? fm.contentsOfDirectory(
                at: dateDir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            // Sort by modification date, newest first
            let rolloutFiles = entries
                .filter { $0.pathExtension == "jsonl" && $0.lastPathComponent.hasPrefix("rollout-") }
                .sorted { a, b in
                    let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    return da > db
                }

            for fileURL in rolloutFiles {
                guard let firstLine = readFirstLine(of: fileURL) else { continue }
                guard let data = firstLine.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let type = json["type"] as? String, type == "session_meta",
                      let payload = json["payload"] as? [String: Any],
                      let cwd = payload["cwd"] as? String,
                      let sid = payload["id"] as? String
                else { continue }

                // Include any rollout whose CWD matches a running process's CWD.
                // Multiple sessions may share the same CWD, so later correlation
                // assigns concrete processes after rollout summaries are loaded.
                if cwds.contains(cwd) && result[sid] == nil {
                    result[sid] = cwd
                }
            }
        }

        return result
    }

    /// Read first line of a file efficiently (up to 8 KB)
    private func readFirstLine(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { handle.closeFile() }

        let chunk = handle.readData(ofLength: 8192)
        guard !chunk.isEmpty else { return nil }
        guard let text = String(data: chunk, encoding: .utf8) else { return nil }

        if let newlineIndex = text.firstIndex(of: "\n") {
            return String(text[..<newlineIndex])
        }
        return text
    }

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
                    if let message = normalized(payload?["message"] as? String) {
                        current.firstUserMessage = current.firstUserMessage ?? message
                        current.lastUserMessage = message
                    }
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
        let explicitTitle = normalized(indexEntry?.threadName)
        let derivedTitle = normalized(rollout?.firstUserMessage) ?? normalized(rollout?.lastUserMessage)
        let title = explicitTitle ?? derivedTitle
        let titleSource: SessionTitleSource? = explicitTitle != nil ? .explicit : (derivedTitle != nil ? .derived : nil)
        let currentTask = rollout?.lastUserMessage ?? indexEntry?.threadName
        let terminalContext = resolveTerminalContext(
            rollout: rollout,
            processCandidate: processCandidate
        )
        let command = command(for: processCandidate)
        let startedAt = rollout?.startedAt ?? startedAt(for: processCandidate, now: now) ?? updatedAt ?? now
        let idleSince: Date? = if status == .idle {
            latest(rollout?.lastActivityAt, rollout?.updatedAt, indexEntry?.updatedAt)
        } else {
            nil
        }
        let statusSince = resolveStatusSince(
            status: status,
            rollout: rollout,
            indexEntry: indexEntry,
            startedAt: startedAt,
            updatedAt: updatedAt
        )

        return SessionSnapshot(
            id: "codex-session-\(sessionID)",
            tool: .codex,
            pid: processCandidate?.pid ?? 0,
            parentPID: processCandidate?.ppid,
            status: status,
            source: .sessionFile,
            startedAt: startedAt,
            updatedAt: updatedAt ?? now,
            statusSince: statusSince,
            idleSince: idleSince,
            lastOutputAt: status == .running ? (rollout?.lastActivityAt ?? updatedAt) : nil,
            lastInputAt: status == .awaitingInput ? (rollout?.awaitingInputAt ?? updatedAt) : nil,
            cwd: rollout?.cwd ?? processCandidate?.cwd,
            command: command,
            notes: composeNotes(rollout: rollout, processCandidate: processCandidate),
            title: title,
            titleSource: titleSource,
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

    private func resolveStatusSince(
        status: ToolActivityState,
        rollout: RolloutSummary?,
        indexEntry: SessionIndexEntry?,
        startedAt: Date,
        updatedAt: Date?
    ) -> Date {
        switch status {
        case .awaitingInput:
            rollout?.awaitingInputAt ?? updatedAt ?? startedAt
        case .running:
            latest(rollout?.lastActivityAt, rollout?.updatedAt, indexEntry?.updatedAt) ?? startedAt
        case .idle:
            latest(rollout?.lastActivityAt, rollout?.updatedAt, indexEntry?.updatedAt) ?? updatedAt ?? startedAt
        case .unknown:
            updatedAt ?? startedAt
        }
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

    private func resolveTerminalContext(
        rollout: RolloutSummary?,
        processCandidate: ProcessCandidate?
    ) -> TerminalContext? {
        let fallback = desktopFallbackContext(
            rollout: rollout,
            processCandidate: processCandidate
        )
        return TerminalContextResolver.merge(
            primary: processCandidate?.terminalContext,
            fallback: fallback
        )
    }

    private func desktopFallbackContext(
        rollout: RolloutSummary?,
        processCandidate: ProcessCandidate?
    ) -> TerminalContext? {
        let rolloutLooksDesktop = rollout?.source == .desktop ||
            origin(from: rollout?.originator) == .desktop
        let processLooksDesktop = processCandidate.map { candidate in
            candidate.command.localizedCaseInsensitiveContains("codex.app") ||
                candidate.args.localizedCaseInsensitiveContains("codex.app")
        } ?? false

        guard rolloutLooksDesktop || processLooksDesktop else {
            return nil
        }

        return TerminalContext(
            clientKind: .unknown,
            bundleIdentifier: "com.openai.codex",
            sessionManagerKind: .none,
            origin: .desktop
        )
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

    private func bestCandidateIndex(
        for sessionID: String,
        rollout: RolloutSummary?,
        candidates: [ProcessCandidate],
        now: Date
    ) -> Int? {
        guard let sessionAnchor = processCorrelationDate(for: rollout) else {
            return nil
        }

        var bestIndex: Int?
        var bestDistance: TimeInterval?
        for (index, candidate) in candidates.enumerated() {
            let processStart = now.addingTimeInterval(-TimeInterval(candidate.elapsedSeconds))
            let distance = abs(processStart.timeIntervalSince(sessionAnchor))
            guard distance <= processCorrelationWindow else {
                continue
            }

            if let currentBestDistance = bestDistance {
                if distance < currentBestDistance {
                    bestIndex = index
                    bestDistance = distance
                }
            } else {
                bestIndex = index
                bestDistance = distance
            }
        }

        return bestIndex
    }

    private func correlationDate(for rollout: RolloutSummary?) -> Date {
        latest(
            rollout?.awaitingInputAt,
            rollout?.lastActivityAt,
            rollout?.updatedAt,
            rollout?.startedAt
        ) ?? .distantPast
    }

    private func processCorrelationDate(for rollout: RolloutSummary?) -> Date? {
        if let startedAt = rollout?.startedAt {
            return startedAt
        }

        let value = correlationDate(for: rollout)
        return value == .distantPast ? nil : value
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

    private func originHintFromEnvironment(_ rawValue: String?) -> SessionOriginKind {
        guard let rawValue = rawValue?.lowercased(), !rawValue.isEmpty else {
            return .unknown
        }
        if rawValue.contains("cli") {
            return .cli
        }
        if rawValue.contains("desktop") {
            return .desktop
        }
        return .unknown
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
