import Foundation

/// Detects OpenCode sessions via HTTP API
/// OpenCode exposes localhost endpoints for session status
public struct OpenCodeHTTPDetector: AgentDetector {
    public init() {}

    public func detectSessions() async -> [SessionSnapshot] {
        let context = DetectorSupport.makeContext()
        return await detectSessions(context: context)
    }

    func detectSessions(context: DetectorSupport.DetectionContext) async -> [SessionSnapshot] {
        var results: [SessionSnapshot] = []
        let processes = findOpenCodeProcesses(in: context.processes)

        for process in processes {
            guard let port = await DetectorSupport.findListeningPort(pid: process.pid) else { continue }
            guard let sessions = await fetchSessions(port: port) else { continue }
            let statuses = await fetchSessionStatuses(port: port)
            let terminalContext = await TerminalContextResolver.resolve(
                process: process,
                context: context,
                originHint: .cli
            )

            for session in sessions {
                let status: ToolActivityState
                if let statuses {
                    status = statuses.values[session.id] ?? (statuses.isEmpty ? .idle : .unknown)
                } else {
                    status = .unknown
                }

                results.append(
                    SessionSnapshot(
                        id: "opencode-http-\(session.id)",
                        tool: .opencode,
                        pid: process.pid,
                        parentPID: process.ppid,
                        status: status,
                        source: .processScan,
                        startedAt: Date(timeIntervalSince1970: TimeInterval(session.time.created) / 1000),
                        updatedAt: Date(timeIntervalSince1970: TimeInterval(session.time.updated) / 1000),
                        lastOutputAt: nil,
                        lastInputAt: nil,
                        cwd: session.directory,
                        command: ["opencode"],
                        notes: "HTTP API: port \(port), title: \(session.title ?? "-")",
                        title: session.title,
                        currentTask: session.title,
                        terminalContext: terminalContext
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

    private struct SessionStatuses: Sendable {
        let values: [String: ToolActivityState]
        let isEmpty: Bool
    }

    /// Find opencode processes (checks both comm and args to support node/bun launchers)
    private func findOpenCodeProcesses(in processes: [DetectorSupport.ProcEntry]) -> [DetectorSupport.ProcEntry] {
        processes
            .filter {
                $0.command.lowercased().contains("opencode") ||
                $0.args.lowercased().contains("opencode")
            }
    }

    /// Fetch sessions from /experimental/session endpoint
    private func fetchSessions(port: Int) async -> [GlobalSession]? {
        guard let url = URL(string: "http://localhost:\(port)/experimental/session") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 1.0

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            return try JSONDecoder().decode([GlobalSession].self, from: data)
        } catch {
            return nil
        }
    }

    /// Fetch all session statuses from /session/status endpoint once per port.
    private func fetchSessionStatuses(port: Int) async -> SessionStatuses? {
        guard let url = URL(string: "http://localhost:\(port)/session/status") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 0.5

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }

            var result: [String: ToolActivityState] = [:]
            for (sessionID, rawValue) in json {
                guard let statusData = rawValue as? [String: Any],
                      let type = statusData["type"] as? String else {
                    continue
                }
                result[sessionID] = mapStatus(type)
            }

            return SessionStatuses(values: result, isEmpty: json.isEmpty)
        } catch {
            return nil
        }
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
