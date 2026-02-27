import Foundation

/// Detector for GitHub Copilot CLI based on hook-written state files.
///
/// When the user configures Copilot CLI hooks (via `.github/hooks/hooks.json`),
/// hook scripts write JSON state files to `~/.copilot/vibebar/{pid}.json`.
/// This detector reads those files and converts them into SessionSnapshots.
///
/// State mapping from last hook event:
///   session_start / user_prompt / pre_tool_use  → .running
///   post_tool_use (idle >3s after last event)   → .awaitingInput
///   post_tool_use (recent, still processing)    → .running
public struct CopilotHookDetector: AgentDetector {
    /// Directory where hook scripts write state files.
    static let stateDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".copilot/vibebar")

    public init() {}

    public func detectSessions() -> [SessionSnapshot] {
        let dir = Self.stateDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) else { return [] }

        let now = Date()
        var results: [SessionSnapshot] = []

        for file in files where file.pathExtension == "json" {
            guard let snapshot = loadStateFile(file, now: now) else { continue }
            results.append(snapshot)
        }

        return results
    }

    // MARK: - Private

    private func loadStateFile(_ url: URL, now: Date) -> SessionSnapshot? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        guard let pid = (json["pid"] as? Int).map({ Int32($0) }) ?? Int32(url.deletingPathExtension().lastPathComponent) else { return nil }

        // Verify the process is still alive
        guard kill(pid, 0) == 0 else {
            // Clean up stale file
            try? FileManager.default.removeItem(at: url)
            return nil
        }

        let lastEvent = (json["last_event"] as? String) ?? "unknown"
        let timestamp = (json["timestamp"] as? Double).map { Date(timeIntervalSince1970: $0) } ?? now
        let cwd = json["cwd"] as? String

        let status = resolveState(lastEvent: lastEvent, eventTime: timestamp, now: now)

        return SessionSnapshot(
            id: "copilot-hook-\(pid)",
            tool: .githubCopilot,
            pid: pid,
            status: status,
            source: .plugin,
            startedAt: timestamp,
            updatedAt: timestamp,
            lastOutputAt: lastEvent == "post_tool_use" ? timestamp : nil,
            lastInputAt: lastEvent == "user_prompt" ? timestamp : nil,
            cwd: cwd,
            command: ["copilot"],
            notes: "hook:\(lastEvent)"
        )
    }

    /// Determines ToolActivityState from the last recorded hook event and its age.
    private func resolveState(lastEvent: String, eventTime: Date, now: Date) -> ToolActivityState {
        let age = now.timeIntervalSince(eventTime)
        switch lastEvent {
        case "user_prompt", "pre_tool_use", "session_start":
            return .running
        case "post_tool_use":
            // After tool completes, agent is likely showing result and awaiting next prompt
            // Allow 3s grace period for sequential tool calls before marking awaiting
            return age > 3.0 ? .awaitingInput : .running
        default:
            return .running
        }
    }
}
