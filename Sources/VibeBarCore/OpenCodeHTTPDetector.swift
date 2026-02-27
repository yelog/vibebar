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
            guard let port = findListeningPort(pid: process.pid) else { continue }
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

    private struct ProcessInfo {
        let pid: Int32
        let ppid: Int32
    }

    private struct SessionInfo {
        let state: String
        let workspacePath: String?
    }

    /// Thread-safe box for capturing result from async closure
    private final class ResultBox<T: Sendable>: @unchecked Sendable {
        var value: T?
        init(_ value: T? = nil) { self.value = value }
    }

    /// Find opencode processes using ps
    /// Checks both command name and arguments to handle cases where
    /// opencode is launched via node/bun or other runtime
    private func findOpenCodeProcesses() -> [ProcessInfo] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,ppid=,comm=,args="]

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

            var results: [ProcessInfo] = []
            for line in text.split(separator: "\n") {
                let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                guard parts.count >= 4 else { continue }

                guard let pid = Int32(parts[0]),
                      let ppid = Int32(parts[1]) else { continue }

                let command = String(parts[2])
                // Reconstruct args from remaining parts
                let args = parts.dropFirst(3).joined(separator: " ")

                // Check command name or args for opencode
                let commandLower = command.lowercased()
                let argsLower = args.lowercased()
                
                if commandLower.contains("opencode") || argsLower.contains("opencode") {
                    results.append(ProcessInfo(pid: pid, ppid: ppid))
                }
            }
            return results

        } catch {
            return []
        }
    }


    /// Find TCP listening port for a process using lsof
    private func findListeningPort(pid: Int32) -> Int? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-p", String(pid), "-Pn", "-iTCP", "-sTCP:LISTEN"]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard process.terminationStatus == 0,
                  let text = String(data: data, encoding: .utf8) else {
                return nil
            }

            // Parse lsof output: COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
            // NAME format: *:PORT (IPv4) or [::]:PORT (IPv6)
            for line in text.split(separator: "\n").dropFirst() {
                let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                guard parts.count >= 9 else { continue }

                let nameField = String(parts[8])
                // Extract port from *:PORT or [::]:PORT
                if let portRange = nameField.range(of: ":"),
                   let port = Int(nameField[portRange.upperBound...]) {
                    return port
                }
            }

            return nil

        } catch {
            return nil
        }
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
