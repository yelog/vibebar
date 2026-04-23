import Foundation

/// Detects Claude Code sessions by reading transcript files from
/// `~/.claude/projects/`. Each project directory contains `.jsonl` transcript
/// files named after session IDs. The first user message in each transcript
/// becomes the session title.
public struct ClaudeTranscriptDetector: AgentDetector {
    private static let transcriptCache = ClaudeTranscriptCache()
    private static let transcriptCacheTTL: TimeInterval = 10

    private let claudeHome: URL

    public init(claudeHome: URL? = nil) {
        if let claudeHome {
            self.claudeHome = claudeHome
        } else {
            self.claudeHome = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude", isDirectory: true)
        }
    }

    public func detectSessions() async -> [SessionSnapshot] {
        let context = DetectorSupport.makeContext()
        return await detectSessions(context: context)
    }

    func detectSessions(
        context: DetectorSupport.DetectionContext,
        cwdByPID: [Int32: String]? = nil,
        now: Date = Date()
    ) async -> [SessionSnapshot] {
        let processes = await findClaudeProcesses(in: context, cwdByPID: cwdByPID, now: now)
        guard !processes.isEmpty else { return [] }

        var transcriptHints = await cachedTranscriptHints()
        var didForceRefreshHints = false
        var results: [SessionSnapshot] = []

        for process in processes {
            // Strategy 1: Use session ID from ~/.claude/sessions/<pid>.json
            var transcriptPath: String?
            if let sessionId = process.sessionId {
                transcriptPath = findTranscriptBySessionId(sessionId)
            }

            // Strategy 2: Use CWD -> project directory mapping (cached)
            if transcriptPath == nil {
                transcriptPath = transcriptHints[process.cwd]
            }

            if transcriptPath == nil, !didForceRefreshHints {
                transcriptHints = await cachedTranscriptHints(forceRefresh: true)
                didForceRefreshHints = true
                transcriptPath = transcriptHints[process.cwd]
            }

            // Strategy 3: Direct CWD decode fallback
            if transcriptPath == nil {
                transcriptPath = findTranscriptForCWD(process.cwd)
            }

            if let path = transcriptPath,
               let info = parseTranscript(path: path, now: now) {
                // Prefer explicit session name from ~/.claude/sessions/<pid>.json
                let effectiveTitle: String?
                let effectiveTitleSource: SessionTitleSource?
                if let name = process.sessionName, !name.isEmpty {
                    effectiveTitle = name
                    effectiveTitleSource = .explicit
                } else {
                    effectiveTitle = info.firstUserMessage ?? info.lastUserMessage
                    effectiveTitleSource = effectiveTitle == nil ? nil : .derived
                }

                results.append(
                    SessionSnapshot(
                        id: "claude-transcript-\(process.pid)",
                        tool: .claudeCode,
                        pid: process.pid,
                        parentPID: process.ppid,
                        status: info.status,
                        source: .transcriptFile,
                        startedAt: info.startedAt ?? process.startedAt,
                        updatedAt: now,
                        statusSince: info.statusSince,
                        idleSince: info.idleSince,
                        lastOutputAt: info.lastOutputAt,
                        lastInputAt: info.lastInputAt,
                        cwd: process.cwd,
                        command: ["claude"],
                        notes: "transcript: \(URL(fileURLWithPath: path).lastPathComponent)",
                        title: effectiveTitle,
                        titleSource: effectiveTitleSource,
                        currentTask: info.runningSummary ?? info.lastUserMessage ?? info.firstUserMessage,
                        lastUserMessage: info.lastUserMessage,
                        runningSummary: info.runningSummary,
                        terminalContext: process.terminalContext
                    )
                )
            } else {
                // Even without a transcript, we may have a session name
                let fallbackTitle = (process.sessionName?.isEmpty == false) ? process.sessionName : nil
                results.append(
                    SessionSnapshot(
                        id: "claude-process-\(process.pid)",
                        tool: .claudeCode,
                        pid: process.pid,
                        parentPID: process.ppid,
                        status: .unknown,
                        source: .transcriptFile,
                        startedAt: process.startedAt,
                        updatedAt: now,
                        statusSince: process.startedAt,
                        lastOutputAt: nil,
                        lastInputAt: nil,
                        cwd: process.cwd,
                        command: ["claude"],
                        notes: "no transcript found",
                        title: fallbackTitle,
                        titleSource: fallbackTitle == nil ? nil : .explicit,
                        terminalContext: process.terminalContext
                    )
                )
            }
        }

        return results
    }

    // MARK: - Private

    private struct ProcessInfo {
        let pid: Int32
        let ppid: Int32
        let cwd: String
        let cpu: Double
        let startedAt: Date
        /// Session ID from `~/.claude/sessions/<pid>.json`, if available.
        var sessionId: String?
        /// User-set session name from `~/.claude/sessions/<pid>.json`, if available.
        var sessionName: String?
        let terminalContext: TerminalContext?
    }

    private struct TranscriptInfo {
        let status: ToolActivityState
        let startedAt: Date?
        let statusSince: Date?
        let idleSince: Date?
        let lastOutputAt: Date?
        let lastInputAt: Date?
        let firstUserMessage: String?
        let lastUserMessage: String?
        let runningSummary: String?
    }

    /// Find Claude processes in the process list.
    private func findClaudeProcesses(
        in context: DetectorSupport.DetectionContext,
        cwdByPID: [Int32: String]? = nil,
        now: Date
    ) async -> [ProcessInfo] {
        let entries = context.processes.filter { entry in
            guard entry.commandName == "claude" else { return false }
            let loweredArgs = entry.args.lowercased()
            if loweredArgs.contains("vibebar") || loweredArgs.contains("vibe-bar") {
                return false
            }
            return true
        }

        guard !entries.isEmpty else { return [] }

        let cwds = if let cwdByPID {
            cwdByPID
        } else {
            await DetectorSupport.bulkGetCwds(pids: entries.map(\.pid))
        }

        var allProcesses: [ProcessInfo] = []
        allProcesses.reserveCapacity(entries.count)

        for entry in entries {
            guard let cwd = cwds[entry.pid], !cwd.isEmpty else { continue }
            let sessionMeta = readClaudeSessionMeta(pid: entry.pid)
            let terminalContext = await TerminalContextResolver.resolve(
                process: entry,
                context: context,
                originHint: .cli
            )
            allProcesses.append(
                ProcessInfo(
                    pid: entry.pid,
                    ppid: entry.ppid,
                    cwd: cwd,
                    cpu: entry.cpu,
                    startedAt: now.addingTimeInterval(-TimeInterval(entry.elapsedSeconds)),
                    sessionId: sessionMeta?.sessionId,
                    sessionName: sessionMeta?.name,
                    terminalContext: terminalContext
                )
            )
        }

        var byCWD: [String: [ProcessInfo]] = [:]
        for process in allProcesses {
            byCWD[process.cwd, default: []].append(process)
        }

        var result: [ProcessInfo] = []
        for (_, processes) in byCWD {
            if processes.count == 1 {
                result.append(processes[0])
            } else {
                let claudePIDs = Set(processes.map { $0.pid })
                let nonClaudeParent = processes.first { !claudePIDs.contains($0.ppid) }
                result.append(nonClaudeParent ?? processes.max(by: { $0.pid < $1.pid })!)
            }
        }

        return result
    }

    /// Metadata extracted from Claude's session PID JSON file.
    private struct ClaudeSessionMeta {
        let sessionId: String?
        let name: String?
    }

    /// Read session metadata from Claude's session PID file.
    /// Claude writes `~/.claude/sessions/<pid>.json` with `sessionId` and `name` fields.
    private func readClaudeSessionMeta(pid: Int32) -> ClaudeSessionMeta? {
        let sessionsDir = claudeHome.appendingPathComponent("sessions", isDirectory: true)
        let sessionFile = sessionsDir.appendingPathComponent("\(pid).json")
        guard let data = try? Data(contentsOf: sessionFile),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let sessionId = obj["sessionId"] as? String
        let name = obj["name"] as? String
        guard (sessionId != nil && !sessionId!.isEmpty) || (name != nil && !name!.isEmpty) else {
            return nil
        }
        return ClaudeSessionMeta(
            sessionId: (sessionId?.isEmpty == false) ? sessionId : nil,
            name: (name?.isEmpty == false) ? name : nil
        )
    }

    /// Find a transcript file by searching all project directories for a `.jsonl`
    /// file whose name matches the given session ID. This is the most reliable
    /// method since CWD may differ from the project directory.
    private func findTranscriptBySessionId(_ sessionId: String) -> String? {
        let projectsDir = claudeHome.appendingPathComponent("projects", isDirectory: true)

        guard let projectDirs = try? FileManager.default.contentsOfDirectory(
            at: projectsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let targetName = "\(sessionId).jsonl"

        for projectDir in projectDirs where projectDir.hasDirectoryPath {
            let candidateURL = projectDir.appendingPathComponent(targetName)
            if FileManager.default.fileExists(atPath: candidateURL.path) {
                return candidateURL.path
            }
        }

        return nil
    }

    /// Build CWD -> transcript path mapping by scanning the projects directory.
    /// Each project directory is named after an encoded path, e.g.:
    /// `-Users-yelog-workspace-swift-VibeBar`
    private func scanTranscriptFiles() -> [String: String] {
        let projectsDir = claudeHome.appendingPathComponent("projects", isDirectory: true)

        guard let projectDirs = try? FileManager.default.contentsOfDirectory(
            at: projectsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return [:]
        }

        var result: [String: String] = [:]
        let now = Date()

        for projectDir in projectDirs where projectDir.hasDirectoryPath {
            let projectPath = decodeProjectPath(projectDir.lastPathComponent)
            guard let projectPath, !projectPath.isEmpty else { continue }

            let sessionFiles = (try? FileManager.default.contentsOfDirectory(
                at: projectDir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            let jsonlFiles = sessionFiles.filter { $0.pathExtension == "jsonl" }
            guard let mostRecent = jsonlFiles.max(by: { a, b in
                let dateA = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let dateB = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return dateA < dateB
            }) else {
                continue
            }

            guard let modDate = try? mostRecent.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  now.timeIntervalSince(modDate) < 86400 else {
                continue
            }

            result[projectPath] = mostRecent.path
        }

        return result
    }

    /// Fallback: find transcript by checking if CWD matches a decoded project path.
    private func findTranscriptForCWD(_ cwd: String) -> String? {
        let projectsDir = claudeHome.appendingPathComponent("projects", isDirectory: true)

        guard let projectDirs = try? FileManager.default.contentsOfDirectory(
            at: projectsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let now = Date()

        for projectDir in projectDirs where projectDir.hasDirectoryPath {
            let projectPath = decodeProjectPath(projectDir.lastPathComponent)
            guard let projectPath, projectPath == cwd else { continue }

            let sessionFiles = (try? FileManager.default.contentsOfDirectory(
                at: projectDir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            let jsonlFiles = sessionFiles.filter { $0.pathExtension == "jsonl" }
            guard let mostRecent = jsonlFiles.max(by: { a, b in
                let dateA = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let dateB = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return dateA < dateB
            }) else {
                continue
            }

            guard let modDate = try? mostRecent.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  now.timeIntervalSince(modDate) < 86400 else {
                continue
            }

            return mostRecent.path
        }

        return nil
    }

    /// Decode a Claude project directory name back to a filesystem path.
    /// Claude encodes both `/` and `.` as `-`, so `--` can represent `/.`.
    /// e.g. `-Users-yelog--config` -> `/Users/yelog/.config`
    /// e.g. `-Users-yelog-workspace-swift-VibeBar` -> `/Users/yelog/workspace/swift/VibeBar`
    private func decodeProjectPath(_ name: String) -> String? {
        guard name.hasPrefix("-") else { return nil }
        let withoutPrefix = String(name.dropFirst())
        guard !withoutPrefix.isEmpty else { return "/" }

        // Try decoding with `--` -> `/.` first (handles dotfiles/dotdirs)
        let withDots = withoutPrefix.replacingOccurrences(of: "--", with: "/.")
        let pathWithDots = "/" + withDots.replacingOccurrences(of: "-", with: "/")
        if FileManager.default.fileExists(atPath: pathWithDots) {
            return pathWithDots
        }

        // Fallback: simple split
        let components = withoutPrefix.split(separator: "-")
        guard !components.isEmpty else { return nil }
        return "/" + components.joined(separator: "/")
    }

    /// Parse a Claude transcript JSONL file to extract session metadata.
    ///
    /// Claude transcript format: each line is a JSON object with a `message` field
    /// containing `role` ("user"/"assistant"/"system") and `content`.
    /// The `type` field indicates the message category.
    private func parseTranscript(path: String, now: Date) -> TranscriptInfo? {
        guard let fileHandle = FileHandle(forReadingAtPath: path) else { return nil }

        var lastAssistantAt: Date?
        var lastUserAt: Date?
        var lastMessageType: String?
        var startedAt: Date?
        var firstUserMessage: String?
        var lastUserMessage: String?
        var lastPromptText: String?
        var lastSystemAt: Date?
        var lastRetrySummary: String?
        var lastRetryAt: Date?

        var reader = JSONLReader(fileHandle: fileHandle)

        while let line = reader.nextLine() {
            guard let data = line.data(using: String.Encoding.utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            let messageType = object["type"] as? String
            lastMessageType = messageType
            let ts = (object["timestamp"] as? String).flatMap(DetectorSupport.parseISO8601)

            if startedAt == nil, let ts = object["timestamp"] as? String,
               let date = DetectorSupport.parseISO8601(ts) {
                startedAt = date
            }

            if messageType == "last-prompt",
               let prompt = normalizeText(object["lastPrompt"] as? String) {
                lastPromptText = prompt
                continue
            }

            if messageType == "system" {
                if let ts, let retrySummary = retrySummary(from: object) {
                    lastSystemAt = ts
                    lastRetryAt = ts
                    lastRetrySummary = retrySummary
                }
                continue
            }

            guard let message = object["message"] as? [String: Any] else { continue }

            let role = message["role"] as? String

            if role == "assistant" || role == "claude", let ts {
                lastAssistantAt = ts
                if lastRetryAt == nil || ts >= lastRetryAt! {
                    lastRetrySummary = nil
                }
            }

            if role == "user", let ts {
                lastUserAt = ts
                if lastRetryAt == nil || ts >= lastRetryAt! {
                    lastRetrySummary = nil
                }
                if let text = extractUserMessageText(from: message) {
                    firstUserMessage = firstUserMessage ?? text
                    lastUserMessage = text
                }
            }
        }

        try? fileHandle.close()

        if let lastPromptText {
            lastUserMessage = lastPromptText
        }

        let freshest = latestDate(lastAssistantAt, lastSystemAt, lastUserAt)

        let status: ToolActivityState
        if let freshest, now.timeIntervalSince(freshest) < 2.5 {
            status = .running
        } else if lastMessageType == "user" {
            status = .awaitingInput
        } else {
            status = .idle
        }

        let statusSince: Date? = switch status {
        case .running:
            freshest ?? startedAt
        case .awaitingInput:
            lastUserAt ?? freshest ?? startedAt
        case .completed:
            lastAssistantAt ?? lastUserAt ?? startedAt
        case .idle:
            lastAssistantAt ?? lastUserAt ?? startedAt
        case .unknown:
            startedAt
        }

        let runningSummary: String?
        if status == .running,
           let lastRetryAt,
           let lastRetrySummary,
           let latestNonRetryAt = latestDate(lastAssistantAt, lastUserAt) {
            runningSummary = lastRetryAt >= latestNonRetryAt ? lastRetrySummary : nil
        } else if status == .running {
            runningSummary = lastRetrySummary
        } else {
            runningSummary = nil
        }

        return TranscriptInfo(
            status: status,
            startedAt: startedAt,
            statusSince: statusSince,
            idleSince: status == .idle ? freshest : nil,
            lastOutputAt: latestDate(lastAssistantAt, lastSystemAt),
            lastInputAt: lastUserAt,
            firstUserMessage: firstUserMessage,
            lastUserMessage: lastUserMessage,
            runningSummary: runningSummary
        )
    }

    /// Extract text content from a Claude message object.
    ///
    /// Claude messages can have content as:
    /// - A plain string
    /// - An array of content blocks with `type: "text"` and `text: "..."`
    /// - An array with various block types (tool_use, tool_result, etc.)
    private func extractUserMessageText(from message: [String: Any]) -> String? {
        if let text = normalizeText(message["text"] as? String) {
            return text
        }

        guard let content = message["content"] else { return nil }

        if let text = normalizeText(content as? String) {
            return text
        }

        if let blocks = content as? [[String: Any]] {
            for block in blocks {
                if block["type"] as? String == "text",
                   let text = normalizeText(block["text"] as? String) {
                    return text
                }
            }
            // Fallback: try first block's text
            if let firstBlock = blocks.first,
               let text = normalizeText(firstBlock["text"] as? String) {
                return text
            }
        }

        return nil
    }

    private func normalizeText(_ value: String?) -> String? {
        guard let value else { return nil }
        let collapsed = value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }

    private func retrySummary(from object: [String: Any]) -> String? {
        guard (object["subtype"] as? String) == "api_error",
              let retryInMs = doubleValue(object["retryInMs"]),
              let retryAttempt = intValue(object["retryAttempt"]),
              let maxRetries = intValue(object["maxRetries"]) else {
            return nil
        }

        let delay = shortDurationString(milliseconds: retryInMs)
        let template = L10nStrings.string(.sessionRetryInFmt, lang: currentLanguage())
        return String(format: template, delay, retryAttempt, maxRetries)
    }

    private func shortDurationString(milliseconds: Double) -> String {
        let totalSeconds = max(1, Int((milliseconds / 1000).rounded()))
        if totalSeconds < 60 {
            return "\(totalSeconds)s"
        }

        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes < 60 {
            return seconds > 0 ? "\(minutes)m \(seconds)s" : "\(minutes)m"
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if remainingMinutes > 0 {
            return "\(hours)h \(remainingMinutes)m"
        }
        return "\(hours)h"
    }

    private func intValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let text = value as? String, let parsed = Int(text) {
            return parsed
        }
        return nil
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let text = value as? String, let parsed = Double(text) {
            return parsed
        }
        return nil
    }

    private func latestDate(_ dates: Date?...) -> Date? {
        dates.compactMap { $0 }.max()
    }

    private func currentLanguage() -> AppLanguage {
        let raw = UserDefaults.standard.string(forKey: "appLanguage") ?? ""
        return (AppLanguage(rawValue: raw) ?? .system).resolved
    }

    private func cachedTranscriptHints(forceRefresh: Bool = false) async -> [String: String] {
        let now = Date()
        if !forceRefresh,
           let cached = await Self.transcriptCache.cachedHints(now: now, ttl: Self.transcriptCacheTTL) {
            return cached
        }

        let scanned = scanTranscriptFiles()
        await Self.transcriptCache.storeHints(scanned, now: now)
        return scanned
    }
}

/// Simple line-by-line reader for JSONL files.
private struct JSONLReader {
    private let fileHandle: FileHandle
    private var buffer = Data()
    private let chunkSize = 8192

    init(fileHandle: FileHandle) {
        self.fileHandle = fileHandle
    }

    mutating func nextLine() -> String? {
        while true {
            if let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let lineData = buffer[..<newlineIndex]
                buffer = buffer[buffer.index(after: newlineIndex)...]
                guard let line = String(data: lineData, encoding: .utf8) else { continue }
                return line
            }

            let chunk = fileHandle.readData(ofLength: chunkSize)
            if chunk.isEmpty {
                if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8) {
                    buffer = Data()
                    return line
                }
                return nil
            }
            buffer.append(chunk)
        }
    }
}

/// Cache for transcript hint mappings (CWD -> transcript path).
private actor ClaudeTranscriptCache {
    private struct CacheEntry: Sendable {
        let hints: [String: String]
        let cachedAt: Date
    }

    private var entry: CacheEntry?

    func cachedHints(now: Date, ttl: TimeInterval) -> [String: String]? {
        guard let entry, now.timeIntervalSince(entry.cachedAt) <= ttl else {
            return nil
        }
        return entry.hints
    }

    func storeHints(_ hints: [String: String], now: Date) {
        entry = CacheEntry(hints: hints, cachedAt: now)
    }
}
