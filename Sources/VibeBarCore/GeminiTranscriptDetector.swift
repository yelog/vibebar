import Foundation

public struct GeminiTranscriptDetector: AgentDetector {
    public init() {}

    public func detectSessions() -> [SessionSnapshot] {
        let processes = findGeminiProcesses()
        guard !processes.isEmpty else {
            return []
        }
        let transcriptHints = transcriptHintsByCWD()
        guard !transcriptHints.isEmpty else {
            return []
        }

        let now = Date()
        var results: [SessionSnapshot] = []

        for process in processes {
            guard let transcriptPath = transcriptHints[process.cwd] else {
                continue
            }
            guard let info = parseTranscript(path: transcriptPath, now: now) else {
                continue
            }
            results.append(
                SessionSnapshot(
                    id: "gemini-transcript-\(process.pid)",
                    tool: .gemini,
                    pid: process.pid,
                    parentPID: process.ppid,
                    status: info.status,
                    source: .processScan,
                    startedAt: info.startedAt ?? now,
                    updatedAt: now,
                    lastOutputAt: info.lastOutputAt,
                    lastInputAt: info.lastInputAt,
                    cwd: process.cwd,
                    command: ["gemini"],
                    notes: "transcript: \(URL(fileURLWithPath: transcriptPath).lastPathComponent)"
                )
            )
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

    private func transcriptHintsByCWD() -> [String: String] {
        let store = SessionFileStore()
        let sessions = store.loadAll().filter { $0.tool == .gemini && $0.source == .plugin }
        var latestByCWD: [String: (updatedAt: Date, path: String)] = [:]

        for session in sessions {
            guard let notes = session.notes,
                  let path = transcriptPath(from: notes)
            else {
                continue
            }
            let cwd = session.cwd ?? deriveCWD(fromTranscriptPath: path)
            guard !cwd.isEmpty else {
                continue
            }
            if let existing = latestByCWD[cwd], existing.updatedAt >= session.updatedAt {
                continue
            }
            latestByCWD[cwd] = (session.updatedAt, path)
        }

        var result: [String: String] = [:]
        for (cwd, value) in latestByCWD {
            result[cwd] = value.path
        }
        return result
    }

    private func transcriptPath(from notes: String) -> String? {
        for token in notes.split(separator: "|") {
            let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("transcript=") else { continue }
            let path = String(trimmed.dropFirst("transcript=".count))
            if !path.isEmpty {
                return path
            }
        }
        return nil
    }

    private func deriveCWD(fromTranscriptPath path: String) -> String {
        let marker = "/.gemini/"
        guard let range = path.range(of: marker) else {
            return ""
        }
        return String(path[..<range.lowerBound])
    }

    private func parseTranscript(path: String, now: Date) -> TranscriptInfo? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        let startedAt = (json["startTime"] as? String).flatMap(DetectorSupport.parseISO8601)
        let lastUpdated = (json["lastUpdated"] as? String).flatMap(DetectorSupport.parseISO8601)
        let messages = json["messages"] as? [[String: Any]]

        var lastGeminiAt: Date?
        var lastUserAt: Date?
        var lastType: String?

        if let messages {
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
        }

        let freshest = lastUpdated ?? lastGeminiAt ?? lastUserAt
        let status: ToolActivityState
        if let freshest, now.timeIntervalSince(freshest) < 2.5 {
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
            $0.args.lowercased().contains("gemini-cli")
        }
        guard !entries.isEmpty else { return [] }
        let cwds = DetectorSupport.bulkGetCwds(pids: entries.map(\.pid))
        return entries.compactMap { entry in
            guard let cwd = cwds[entry.pid], !cwd.isEmpty else { return nil }
            return ProcessInfo(pid: entry.pid, ppid: entry.ppid, cwd: cwd)
        }
    }
}
