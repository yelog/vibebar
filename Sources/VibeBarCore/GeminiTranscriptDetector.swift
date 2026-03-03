import Foundation

public struct GeminiTranscriptDetector: AgentDetector {
    public init() {}

    public func detectSessions() -> [SessionSnapshot] {
        let processes = findGeminiProcesses()
        guard !processes.isEmpty else {
            return []
        }

        // Build CWD -> transcript path mapping by scanning ~/.gemini/tmp/
        let transcriptHints = scanTranscriptFiles()

        let now = Date()
        var results: [SessionSnapshot] = []

        for process in processes {
            // Try to find transcript by CWD
            var transcriptPath: String? = transcriptHints[process.cwd]

            // Fallback: check if CWD matches a .project_root
            if transcriptPath == nil {
                transcriptPath = findTranscriptForCWD(process.cwd)
            }

            // If we have a transcript, parse it for detailed status
            if let path = transcriptPath, let info = parseTranscript(path: path, pid: process.pid, now: now) {
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
                // Fallback: no transcript found, but process is running
                // Return basic session with unknown status
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
            // Look for .project_root files
            guard url.lastPathComponent == ".project_root" else { continue }

            let tmpDir = url.deletingLastPathComponent()
            let projectRootPath = tmpDir.appendingPathComponent(".project_root").path

            guard let projectRoot = try? String(contentsOf: URL(fileURLWithPath: projectRootPath), encoding: .utf8),
                  !projectRoot.isEmpty else {
                continue
            }

            // Find the most recent session file in chats/
            let chatsDir = tmpDir.appendingPathComponent("chats")
            guard let sessionFiles = try? FileManager.default.contentsOfDirectory(
                at: chatsDir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            // Get the most recently modified session file
            let jsonFiles = sessionFiles.filter { $0.pathExtension == "json" }
            guard let mostRecent = jsonFiles.max(by: { a, b in
                let dateA = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let dateB = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return dateA < dateB
            }) else {
                continue
            }

            // Only include if modified within last 24 hours (active session)
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

            // Find most recent session file
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

            // Only include if modified within last 24 hours
            guard let modDate = try? mostRecent.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  now.timeIntervalSince(modDate) < 86400 else {
                continue
            }

            return mostRecent.path
        }

        return nil
    }

    private func parseTranscript(path: String, pid: Int32, now: Date) -> TranscriptInfo? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let messages = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            return nil
        }

        var lastGeminiAt: Date?
        var lastUserAt: Date?
        var lastType: String?
        var startedAt: Date?

        // Find earliest timestamp for startedAt
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

        // Check CPU usage for real-time activity detection
        let isCPUActive = DetectorSupport.isProcessActive(pid: pid, threshold: 0.5)

        let status: ToolActivityState
        if isCPUActive {
            // Process is actively using CPU - likely running
            status = .running
        } else if let freshest, now.timeIntervalSince(freshest) < 2.5 {
            // Recent transcript activity
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

    private func findGeminiProcesses() -> [ProcessInfo] {
        let entries = DetectorSupport.listProcesses().filter {
            $0.commandName == "gemini" ||
            $0.args.lowercased().contains("@google/gemini-cli") ||
            $0.args.lowercased().contains("gemini-cli") ||
            $0.args.lowercased().contains("/bin/gemini")
        }
        guard !entries.isEmpty else { return [] }
        let cwds = DetectorSupport.bulkGetCwds(pids: entries.map(\.pid))

        let allProcesses = entries.compactMap { entry -> ProcessInfo? in
            guard let cwd = cwds[entry.pid], !cwd.isEmpty else { return nil }
            return ProcessInfo(pid: entry.pid, ppid: entry.ppid, cwd: cwd)
        }

        // Deduplicate: Gemini spawns parent+child processes for the same session
        // Group by CWD and keep only one process per session
        var byCWD: [String: [ProcessInfo]] = [:]
        for process in allProcesses {
            byCWD[process.cwd, default: []].append(process)
        }

        var result: [ProcessInfo] = []
        for (_, processes) in byCWD {
            if processes.count == 1 {
                result.append(processes[0])
            } else {
                // Multiple processes for same CWD: prefer the one with highest PID (child process)
                // or the one whose parent is NOT a gemini process
                let geminiPIDs = Set(processes.map { $0.pid })
                let nonGeminiParent = processes.first { !geminiPIDs.contains($0.ppid) }
                result.append(nonGeminiParent ?? processes.max(by: { $0.pid < $1.pid })!)
            }
        }

        return result
    }
}