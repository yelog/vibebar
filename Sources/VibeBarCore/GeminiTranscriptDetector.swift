import Foundation

public struct GeminiTranscriptDetector: AgentDetector {
    private static let transcriptCache = TranscriptHintCache()
    private static let transcriptCacheTTL: TimeInterval = 10

    public init() {}

    public func detectSessions() async -> [SessionSnapshot] {
        let context = DetectorSupport.makeContext()
        return await detectSessions(context: context)
    }

    func detectSessions(context: DetectorSupport.DetectionContext) async -> [SessionSnapshot] {
        let processes = await findGeminiProcesses(in: context)
        guard !processes.isEmpty else {
            return []
        }

        var transcriptHints = await cachedTranscriptHints()
        var didForceRefreshHints = false

        let now = Date()
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
                        startedAt: info.startedAt ?? now,
                        updatedAt: now,
                        lastOutputAt: info.lastOutputAt,
                        lastInputAt: info.lastInputAt,
                        cwd: process.cwd,
                        command: ["gemini"],
                        notes: "transcript: \(URL(fileURLWithPath: path).lastPathComponent)"
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
                        startedAt: now,
                        updatedAt: now,
                        lastOutputAt: nil,
                        lastInputAt: nil,
                        cwd: process.cwd,
                        command: ["gemini"],
                        notes: "no transcript found"
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
    }

    private struct TranscriptInfo {
        let status: ToolActivityState
        let startedAt: Date?
        let lastOutputAt: Date?
        let lastInputAt: Date?
    }

    /// Scan ~/.gemini/tmp/ directories to build CWD -> transcript mapping
    private func scanTranscriptFiles() -> [String: String] {
        let geminiTmp = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".gemini")
            .appendingPathComponent("tmp")

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
        let geminiTmp = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".gemini")
            .appendingPathComponent("tmp")

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

        return TranscriptInfo(
            status: status,
            startedAt: startedAt,
            lastOutputAt: lastGeminiAt,
            lastInputAt: lastUserAt
        )
    }

    private func findGeminiProcesses(
        in context: DetectorSupport.DetectionContext
    ) async -> [ProcessInfo] {
        let entries = context.processes.filter {
            $0.commandName == "gemini" ||
            $0.args.lowercased().contains("@google/gemini-cli") ||
            $0.args.lowercased().contains("gemini-cli") ||
            $0.args.lowercased().contains("/bin/gemini")
        }
        guard !entries.isEmpty else { return [] }
        let cwds = await DetectorSupport.bulkGetCwds(pids: entries.map(\.pid))

        let allProcesses = entries.compactMap { entry -> ProcessInfo? in
            guard let cwd = cwds[entry.pid], !cwd.isEmpty else { return nil }
            return ProcessInfo(pid: entry.pid, ppid: entry.ppid, cwd: cwd, cpu: entry.cpu)
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
