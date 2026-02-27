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

        let startedAt = (json["startTime"] as? String).flatMap(parseISO8601)
        let lastUpdated = (json["lastUpdated"] as? String).flatMap(parseISO8601)
        let messages = json["messages"] as? [[String: Any]]

        var lastGeminiAt: Date?
        var lastUserAt: Date?
        var lastType: String?

        if let messages {
            for message in messages {
                guard let type = message["type"] as? String else { continue }
                let ts = (message["timestamp"] as? String).flatMap(parseISO8601)
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

    private func parseISO8601(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private func findGeminiProcesses() -> [ProcessInfo] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,ppid=,comm=,args="]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        guard (try? process.run()) != nil else {
            return []
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let text = String(data: data, encoding: .utf8)
        else {
            return []
        }

        var pids: [(pid: Int32, ppid: Int32)] = []
        for line in text.split(separator: "\n") {
            let parts = line.split(maxSplits: 4, omittingEmptySubsequences: true, whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 5,
                  let pid = Int32(parts[0]),
                  let ppid = Int32(parts[1])
            else {
                continue
            }
            let command = String(parts[3]).lowercased()
            let args = String(parts[4]).lowercased()
            if command == "gemini" || args.contains("@google/gemini-cli") || args.contains("gemini-cli") {
                pids.append((pid, ppid))
            }
        }

        let cwds = bulkGetCwds(pids: pids.map(\.pid))
        return pids.compactMap { item in
            guard let cwd = cwds[item.pid], !cwd.isEmpty else {
                return nil
            }
            return ProcessInfo(pid: item.pid, ppid: item.ppid, cwd: cwd)
        }
    }

    private func bulkGetCwds(pids: [Int32]) -> [Int32: String] {
        guard !pids.isEmpty else { return [:] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-a", "-p", pids.map(String.init).joined(separator: ","), "-d", "cwd", "-Fp", "-Fn"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return [:] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return [:] }

        var result: [Int32: String] = [:]
        var currentPID: Int32?
        for line in text.split(separator: "\n") {
            let value = String(line)
            if value.hasPrefix("p"), let pid = Int32(value.dropFirst()) {
                currentPID = pid
            } else if value.hasPrefix("n"), let pid = currentPID {
                let path = String(value.dropFirst())
                if !path.isEmpty {
                    result[pid] = path
                }
                currentPID = nil
            }
        }
        return result
    }
}
