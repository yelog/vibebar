import Foundation

public struct GeminiTranscriptDetector: AgentDetector {
    private static let transcriptCache = TranscriptHintCache()
    private static let transcriptCacheTTL: TimeInterval = 10
    private let geminiHome: URL

    public init(geminiHome: URL? = nil) {
        if let geminiHome {
            self.geminiHome = geminiHome
        } else {
            self.geminiHome = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".gemini", isDirectory: true)
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
        let processes = await findGeminiProcesses(in: context, cwdByPID: cwdByPID, now: now)
        guard !processes.isEmpty else {
            return []
        }

        var transcriptHints = await cachedTranscriptHints()
        var didForceRefreshHints = false
        var results: [SessionSnapshot] = []

        for process in processes {
            var transcriptPath: String? = transcriptHints[process.cwd]

            if transcriptPath == nil, !didForceRefreshHints {
                transcriptHints = await cachedTranscriptHints(forceRefresh: true)
                didForceRefreshHints = true
                transcriptPath = transcriptHints[process.cwd]
            }

            if transcriptPath == nil {
                transcriptPath = findTranscriptForCWD(process.cwd)
            }

            if let path = transcriptPath,
               let info = parseTranscript(path: path, cpuUsage: process.cpu, now: now) {
                results.append(
                    SessionSnapshot(
                        id: "gemini-transcript-\(process.pid)",
                        tool: .gemini,
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
                        command: ["gemini"],
                        notes: "transcript: \(URL(fileURLWithPath: path).lastPathComponent)",
                        title: info.firstUserMessage ?? info.lastUserMessage,
                        titleSource: (info.firstUserMessage ?? info.lastUserMessage) == nil ? nil : .derived,
                        currentTask: info.lastUserMessage ?? info.firstUserMessage,
                        lastUserMessage: info.lastUserMessage,
                        terminalContext: process.terminalContext
                    )
                )
            } else {
                results.append(
                    SessionSnapshot(
                        id: "gemini-process-\(process.pid)",
                        tool: .gemini,
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
                        command: ["gemini"],
                        notes: "no transcript found",
                        terminalContext: process.terminalContext
                    )
                )
            }
        }

        return results
    }

    private struct ProcessInfo {
        let pid: Int32
        let ppid: Int32
        let cwd: String
        let cpu: Double
        let startedAt: Date
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
    }

    /// Scan ~/.gemini/tmp/ directories to build CWD -> transcript mapping
    private func scanTranscriptFiles() -> [String: String] {
        let geminiTmp = geminiHome.appendingPathComponent("tmp")

        guard let enumerator = FileManager.default.enumerator(
            at: geminiTmp,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return [:]
        }

        var result: [String: String] = [:]
        let now = Date()

        for case let url as URL in enumerator {
            guard url.lastPathComponent == ".project_root" else { continue }

            let tmpDir = url.deletingLastPathComponent()
            let projectRootPath = tmpDir.appendingPathComponent(".project_root").path

            guard let projectRoot = try? String(contentsOf: URL(fileURLWithPath: projectRootPath), encoding: .utf8),
                  !projectRoot.isEmpty else {
                continue
            }

            let chatsDir = tmpDir.appendingPathComponent("chats")
            guard let sessionFiles = try? FileManager.default.contentsOfDirectory(
                at: chatsDir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            let jsonFiles = sessionFiles.filter { $0.pathExtension == "json" }
            guard let mostRecent = jsonFiles.max(by: { a, b in
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

            result[projectRoot] = mostRecent.path
        }

        return result
    }

    /// Fallback: find transcript by checking if CWD matches a .project_root
    private func findTranscriptForCWD(_ cwd: String) -> String? {
        let geminiTmp = geminiHome.appendingPathComponent("tmp")

        guard let dirs = try? FileManager.default.contentsOfDirectory(
            at: geminiTmp,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let now = Date()

        for dir in dirs where dir.hasDirectoryPath {
            let projectRootPath = dir.appendingPathComponent(".project_root").path
            guard let projectRoot = try? String(contentsOf: URL(fileURLWithPath: projectRootPath), encoding: .utf8),
                  projectRoot == cwd else {
                continue
            }

            let chatsDir = dir.appendingPathComponent("chats")
            guard let sessionFiles = try? FileManager.default.contentsOfDirectory(
                at: chatsDir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            let jsonFiles = sessionFiles.filter { $0.pathExtension == "json" }
            guard let mostRecent = jsonFiles.max(by: { a, b in
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

    private func parseTranscript(path: String, cpuUsage: Double, now: Date) -> TranscriptInfo? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let messages = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            return nil
        }

        var lastGeminiAt: Date?
        var lastUserAt: Date?
        var lastType: String?
        var startedAt: Date?
        var firstUserMessage: String?
        var lastUserMessage: String?

        if let first = messages.first,
           let firstTs = (first["timestamp"] as? String).flatMap(DetectorSupport.parseISO8601) {
            startedAt = firstTs
        }

        for message in messages {
            guard let type = message["type"] as? String else { continue }
            let ts = (message["timestamp"] as? String).flatMap(DetectorSupport.parseISO8601)
            lastType = type
            if type == "gemini", let ts {
                lastGeminiAt = ts
            }
            if type == "user", let ts {
                lastUserAt = ts
                if let text = transcriptMessageText(from: message) {
                    firstUserMessage = firstUserMessage ?? text
                    lastUserMessage = text
                }
            }
        }

        let freshest = lastGeminiAt ?? lastUserAt
        let isCPUActive = cpuUsage >= 0.5

        let status: ToolActivityState
        if isCPUActive {
            status = .running
        } else if let freshest, now.timeIntervalSince(freshest) < 2.5 {
            status = .running
        } else if lastType == "user" {
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
            lastGeminiAt ?? lastUserAt ?? startedAt
        case .idle:
            lastGeminiAt ?? lastUserAt ?? startedAt
        case .unknown:
            startedAt
        }

        return TranscriptInfo(
            status: status,
            startedAt: startedAt,
            statusSince: statusSince,
            idleSince: status == .idle ? (lastGeminiAt ?? lastUserAt) : nil,
            lastOutputAt: lastGeminiAt,
            lastInputAt: lastUserAt,
            firstUserMessage: firstUserMessage,
            lastUserMessage: lastUserMessage
        )
    }

    private func findGeminiProcesses(
        in context: DetectorSupport.DetectionContext,
        cwdByPID: [Int32: String]? = nil,
        now: Date
    ) async -> [ProcessInfo] {
        let entries = context.processes.filter {
            $0.commandName == "gemini" ||
            $0.args.lowercased().contains("@google/gemini-cli") ||
            $0.args.lowercased().contains("gemini-cli") ||
            $0.args.lowercased().contains("/bin/gemini")
        }
        guard !entries.isEmpty else { return [] }
        let cwds: [Int32: String]
        if let cwdByPID {
            cwds = cwdByPID
        } else {
            cwds = await DetectorSupport.bulkGetCwds(pids: entries.map(\.pid))
        }

        var allProcesses: [ProcessInfo] = []
        allProcesses.reserveCapacity(entries.count)

        for entry in entries {
            guard let cwd = cwds[entry.pid], !cwd.isEmpty else { continue }
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
                let geminiPIDs = Set(processes.map { $0.pid })
                let nonGeminiParent = processes.first { !geminiPIDs.contains($0.ppid) }
                result.append(nonGeminiParent ?? processes.max(by: { $0.pid < $1.pid })!)
            }
        }

        return result
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

    private func transcriptMessageText(from message: [String: Any]) -> String? {
        if let text = normalizeText(message["text"] as? String) {
            return text
        }
        if let text = normalizeText(message["message"] as? String) {
            return text
        }
        if let content = message["content"],
           let text = extractText(from: content) {
            return text
        }
        if let parts = message["parts"] as? [Any] {
            return parts.compactMap(extractText(from:)).first
        }
        return nil
    }

    private func extractText(from value: Any) -> String? {
        if let string = value as? String {
            return normalizeText(string)
        }

        if let array = value as? [Any] {
            return array.compactMap(extractText(from:)).first
        }

        guard let object = value as? [String: Any] else {
            return nil
        }

        for key in ["text", "message", "prompt", "value"] {
            if let text = normalizeText(object[key] as? String) {
                return text
            }
        }

        for key in ["content", "parts", "items"] {
            if let nested = object[key],
               let text = extractText(from: nested) {
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
}

private actor TranscriptHintCache {
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
