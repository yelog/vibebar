import Foundation

/// Detects Claude Code sessions via debug logs and JSONL files
/// Parses ~/.claude/debug/*.txt and ~/.claude/projects/*/*.jsonl
public struct ClaudeLogDetector: AgentDetector {
    public init() {}

    public func detectSessions() -> [SessionSnapshot] {
        let now = Date()
        var results: [SessionSnapshot] = []

        // Find claude processes
        let processes = findClaudeProcesses()
        guard !processes.isEmpty else { return [] }

        // Map PID to session ID from debug logs
        let pidToSessionMap = mapPIDsToSessions(processes: processes)

        for (pid, sessionId) in pidToSessionMap {
            guard let sessionInfo = parseSessionJSONL(sessionId: sessionId) else { continue }

            results.append(
                SessionSnapshot(
                    id: "claude-log-\(sessionId)",
                    tool: .claudeCode,
                    pid: pid,
                    parentPID: nil,
                    status: sessionInfo.status,
                    source: .processScan,
                    startedAt: sessionInfo.startedAt ?? now,
                    updatedAt: now,
                    lastOutputAt: sessionInfo.lastOutputAt,
                    lastInputAt: sessionInfo.lastInputAt,
                    cwd: sessionInfo.cwd,
                    command: ["claude"],
                    notes: "Log parsed: \(sessionId.suffix(8))"
                )
            )
        }

        return results
    }

    // MARK: - Private

    private struct SessionInfo {
        let status: ToolActivityState
        let startedAt: Date?
        let lastOutputAt: Date?
        let lastInputAt: Date?
        let cwd: String?
    }

    /// Find claude processes using ps
    private func findClaudeProcesses() -> [Int32] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,comm="]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard process.terminationStatus == 0,
                  let text = String(data: data, encoding: .utf8) else {
                return []
            }

            var pids: [Int32] = []
            for line in text.split(separator: "\n") {
                let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                guard parts.count >= 2 else { continue }

                guard let pid = Int32(parts[0]) else { continue }
                let command = String(parts[1])

                // Match 'claude' binary (but not claude-vibebar-plugin, etc)
                if command == "claude" || command.hasSuffix("/claude") {
                    pids.append(pid)
                }
            }
            return pids

        } catch {
            return []
        }
    }

    /// Map PIDs to session IDs by scanning ~/.claude/debug/*.txt
    /// Debug files have format: .tmp.{PID}.sessionId.txt
    private func mapPIDsToSessions(processes: [Int32]) -> [Int32: String] {
        let debugDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/debug")

        guard FileManager.default.fileExists(atPath: debugDir.path) else {
            return [:]
        }

        var pidToSession: [Int32: String] = [:]
        let pidSet = Set(processes)

        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: debugDir,
                includingPropertiesForKeys: nil
            )

            for file in files {
                let filename = file.lastPathComponent

                // Pattern: .tmp.{PID}.{sessionId}.txt
                guard filename.hasPrefix(".tmp."),
                      filename.hasSuffix(".txt") else { continue }

                let parts = filename.split(separator: ".")
                guard parts.count >= 4 else { continue }

                // parts[0] is empty (starts with .), parts[1] = "tmp", parts[2] = PID
                guard let pidIndex = parts.firstIndex(of: "tmp"),
                      pidIndex + 1 < parts.count,
                      let pid = Int32(parts[pidIndex + 1]),
                      pidSet.contains(pid) else { continue }

                // Extract session ID (everything between PID and .txt)
                let sessionId = parts[(pidIndex + 2)...].dropLast().joined(separator: ".")
                guard !sessionId.isEmpty else { continue }

                pidToSession[pid] = sessionId
            }

        } catch {
            // Ignore directory read errors
        }

        return pidToSession
    }

    /// Parse session JSONL file to determine status
    /// Reads last 128KB for efficiency (as agentstat does)
    private func parseSessionJSONL(sessionId: String) -> SessionInfo? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let projectsDir = home.appendingPathComponent(".claude/projects")

        // Find the session file: ~/.claude/projects/{projectId}/{sessionId}.jsonl
        guard let enumerator = FileManager.default.enumerator(
            at: projectsDir,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            return nil
        }

        var sessionFile: URL?
        for case let fileURL as URL in enumerator {
            if fileURL.lastPathComponent == "\(sessionId).jsonl" {
                sessionFile = fileURL
                break
            }
        }

        guard let file = sessionFile,
              let handle = try? FileHandle(forReadingFrom: file) else {
            return nil
        }

        defer { handle.closeFile() }

        // Seek to last 128KB
        let fileSize = (try? handle.seekToEnd()) ?? 0
        let offset = max(0, fileSize - 131072)
        handle.seek(toFileOffset: offset)

        let data = handle.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else {
            return nil
        }

        // Parse JSONL lines
        var lastTurnDuration: Date?
        var lastAssistant: Date?
        var lastMessageTime: Date?
        var cwd: String?

        for line in text.split(separator: "\n") {
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }

            let timestamp = (json["timestamp"] as? String).flatMap { parseISO8601($0) }

            // Track message types for state detection
            if let type = json["type"] as? String {
                switch type {
                case "turn_duration":
                    lastTurnDuration = timestamp
                case "assistant":
                    lastAssistant = timestamp
                default:
                    break
                }
            }

            // Track latest timestamp
            if let ts = timestamp {
                if lastMessageTime == nil || ts > lastMessageTime! {
                    lastMessageTime = ts
                }
            }

            // Extract working directory from init or context messages
            if cwd == nil, let payload = json["payload"] as? [String: Any] {
                if let path = payload["cwd"] as? String {
                    cwd = path
                } else if let context = payload["context"] as? [String: Any],
                          let path = context["cwd"] as? String {
                    cwd = path
                }
            }
        }

        // Determine status based on message order
        // If last assistant > last turn_duration: busy (responding)
        // If last turn_duration > last assistant: idle (waiting for input)
        let status: ToolActivityState
        if let assistant = lastAssistant, let turn = lastTurnDuration {
            status = assistant > turn ? .running : .idle
        } else if lastAssistant != nil {
            status = .running
        } else if lastTurnDuration != nil {
            status = .idle
        } else {
            status = .unknown
        }

        return SessionInfo(
            status: status,
            startedAt: nil, // Could be extracted from first message
            lastOutputAt: lastAssistant,
            lastInputAt: lastTurnDuration,
            cwd: cwd
        )
    }

    private func parseISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string)
    }
}
