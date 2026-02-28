import Foundation

/// Detects OpenCode sessions via HTTP API
/// OpenCode exposes localhost endpoints for session status
public struct OpenCodeHTTPDetector: AgentDetector {
    public init() {}

    public func detectSessions() -> [SessionSnapshot] {
        let now = Date()
        var results: [SessionSnapshot] = []

        // Find opencode processes and their listening ports
        let processes = findOpenCodeProcesses()

        for process in processes {
            guard let port = DetectorSupport.findListeningPort(pid: process.pid) else { continue }
            guard let sessions = fetchSessionStatusSync(port: port) else { continue }

            for (sessionId, info) in sessions {
                let status = mapStatus(info.state)

                results.append(
                    SessionSnapshot(
                        id: "opencode-http-\(sessionId)",
                        tool: .opencode,
                        pid: process.pid,
                        parentPID: process.ppid,
                        status: status,
                        source: .processScan, // Keep backward compatible
                        startedAt: now,
                        updatedAt: now,
                        lastOutputAt: nil,
                        lastInputAt: nil,
                        cwd: info.workspacePath,
                        command: ["opencode"],
                        notes: "HTTP API: port \(port)"
                    )
                )
            }
        }

        return results
    }

    // MARK: - Private

    private struct SessionInfo {
        let state: String
        let workspacePath: String?
    }

    /// Thread-safe box for capturing result from async closure
    private final class ResultBox<T: Sendable>: @unchecked Sendable {
        var value: T?
        init(_ value: T? = nil) { self.value = value }
    }

    /// Find opencode processes (checks both comm and args to support node/bun launchers)
    private func findOpenCodeProcesses() -> [(pid: Int32, ppid: Int32)] {
        DetectorSupport.listProcesses()
            .filter {
                $0.command.lowercased().contains("opencode") ||
                $0.args.lowercased().contains("opencode")
            }
            .map { ($0.pid, $0.ppid) }
    }

    /// Fetch session status from OpenCode HTTP API using synchronous request
    private func fetchSessionStatusSync(port: Int) -> [String: SessionInfo]? {
        guard let url = URL(string: "http://localhost:\(port)/session/status") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 0.5

        // Use semaphore for synchronous execution
        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = ResultBox<[String: SessionInfo]>()

        let task = URLSession.shared.dataTask(with: request) { [semaphore] data, response, error in
            defer { semaphore.signal() }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }

            var sessions: [String: SessionInfo] = [:]

            // OpenCode API returns sessions keyed by session ID
            for (key, value) in json {
                guard let sessionData = value as? [String: Any] else { continue }

                let state = sessionData["state"] as? String ?? "unknown"
                let workspace = sessionData["workspace_path"] as? String

                sessions[key] = SessionInfo(
                    state: state,
                    workspacePath: workspace
                )
            }

            resultBox.value = sessions
        }

        task.resume()
        _ = semaphore.wait(timeout: .now() + 0.6)

        return resultBox.value
    }

    /// Map OpenCode state to ToolActivityState
    private func mapStatus(_ state: String) -> ToolActivityState {
        switch state.lowercased() {
        case "idle":
            return .idle
        case "busy", "running":
            return .running
        case "awaiting_input", "awaitinginput":
            return .awaitingInput
        default:
            return .unknown
        }
    }
}
