import Foundation

/// Detects OpenCode sessions via HTTP API
/// OpenCode exposes localhost endpoints for session status
public struct OpenCodeHTTPDetector: AgentDetector {
    public init() {}

    public func detectSessions() -> [SessionSnapshot] {
        var results: [SessionSnapshot] = []

        // Find opencode processes and their listening ports
        let processes = findOpenCodeProcesses()

        for process in processes {
            guard let port = DetectorSupport.findListeningPort(pid: process.pid) else { continue }
            guard let sessions = fetchSessionsSync(port: port) else { continue }

            for session in sessions {
                // Fetch status for each session
                let status = fetchSessionStatusSync(port: port, sessionId: session.id)

                results.append(
                    SessionSnapshot(
                        id: "opencode-http-\(session.id)",
                        tool: .opencode,
                        pid: process.pid,
                        parentPID: process.ppid,
                        status: status,
                        source: .processScan, // Keep backward compatible
                        startedAt: Date(timeIntervalSince1970: TimeInterval(session.time.created) / 1000),
                        updatedAt: Date(timeIntervalSince1970: TimeInterval(session.time.updated) / 1000),
                        lastOutputAt: nil,
                        lastInputAt: nil,
                        cwd: session.directory,
                        command: ["opencode"],
                        notes: "HTTP API: port \(port), title: \(session.title)"
                    )
                )
            }
        }

        return results
    }

    // MARK: - Private

    /// Session from /experimental/session endpoint
    private struct GlobalSession: Codable {
        let id: String
        let slug: String?
        let directory: String
        let title: String?
        let time: TimeInfo

        struct TimeInfo: Codable {
            let created: Int64
            let updated: Int64
        }
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

    /// Fetch sessions from /experimental/session endpoint
    private func fetchSessionsSync(port: Int) -> [GlobalSession]? {
        guard let url = URL(string: "http://localhost:\(port)/experimental/session") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 1.0

        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = ResultBox<[GlobalSession]>()

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }

            guard let data = data,
                  let sessions = try? JSONDecoder().decode([GlobalSession].self, from: data) else {
                return
            }

            resultBox.value = sessions
        }

        task.resume()
        _ = semaphore.wait(timeout: .now() + 1.5)

        return resultBox.value
    }

    /// Fetch session status from /session/status endpoint
    private func fetchSessionStatusSync(port: Int, sessionId: String) -> ToolActivityState {
        // Try /session/status with directory parameter
        guard let url = URL(string: "http://localhost:\(port)/session/status") else {
            return .unknown
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 0.5

        let semaphore = DispatchSemaphore(value: 0)
        var result: ToolActivityState = .unknown

        let task = URLSession.shared.dataTask(with: request) { data, _, _ in
            defer { semaphore.signal() }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }

            // Check if there's status for this session
            if let statusData = json[sessionId] as? [String: Any],
               let type = statusData["type"] as? String {
                result = mapStatus(type)
            } else if json.isEmpty {
                // Empty response means no active session
                result = .idle
            }
        }

        task.resume()
        _ = semaphore.wait(timeout: .now() + 0.6)

        return result
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