import Foundation

/// Detector for GitHub Copilot CLI using its local JSON-RPC server.
///
/// When `copilot` starts, it spawns a local JSON-RPC server that the
/// `@github/copilot-sdk` connects to via `cliUrl: "localhost:PORT"`.
/// This detector discovers the port via `lsof`, then probes the server
/// with a JSON-RPC session status request to obtain accurate state.
///
/// Priority: higher than CopilotHookDetector (real-time vs file-based).
/// Falls back gracefully — if the probe fails, returns nil (no session).
public struct CopilotServerDetector: AgentDetector {
    /// JSON-RPC request timeout
    private static let timeout: TimeInterval = 0.8

    public init() {}

    public func detectSessions() -> [SessionSnapshot] {
        let processes = findCopilotProcesses()
        guard !processes.isEmpty else { return [] }

        var results: [SessionSnapshot] = []
        for proc in processes {
            if let snapshot = queryServer(pid: proc.pid, ppid: proc.ppid, cwd: proc.cwd) {
                results.append(snapshot)
            }
        }
        return results
    }

    // MARK: - Private

    private struct ProcInfo {
        var pid: Int32
        var ppid: Int32
        var cwd: String?
    }

    private func findCopilotProcesses() -> [ProcInfo] {
        DetectorSupport.listProcesses()
            .filter { $0.commandName == "copilot" }
            .map { ProcInfo(pid: $0.pid, ppid: $0.ppid, cwd: nil) }
    }

    private func queryServer(pid: Int32, ppid: Int32, cwd: String?) -> SessionSnapshot? {
        guard let port = DetectorSupport.findListeningPort(pid: pid) else { return nil }

        // JSON-RPC 2.0 request: query session status
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "session/status",
            "params": [:]
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return nil }

        let semaphore = DispatchSemaphore(value: 0)
        var responseData: Data?

        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = Self.timeout

        let task = URLSession.shared.dataTask(with: request) { data, _, _ in
            responseData = data
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + Self.timeout + 0.2)

        let now = Date()
        let status = parseSessionStatus(from: responseData)

        return SessionSnapshot(
            id: "copilot-server-\(pid)",
            tool: .githubCopilot,
            pid: pid,
            parentPID: ppid,
            status: status,
            source: .processScan,
            startedAt: now,
            updatedAt: now,
            lastOutputAt: status == .running ? now : nil,
            cwd: cwd,
            command: ["copilot"],
            notes: "rpc-port:\(port)"
        )
    }

    /// Parse the JSON-RPC response to determine session state.
    ///
    /// Expected Copilot SDK events mapped to state:
    ///   result.status == "idle"            → .awaitingInput
    ///   result.status == "busy" / "running" → .running
    private func parseSessionStatus(from data: Data?) -> ToolActivityState {
        guard let data = data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any]
        else {
            // Server responded but we couldn't parse — still running
            return data != nil ? .running : .unknown
        }

        let statusStr = (result["status"] as? String)?.lowercased() ?? ""
        switch statusStr {
        case "idle":
            return .awaitingInput
        case "busy", "running", "processing":
            return .running
        default:
            // Any response means the server is alive; fall back to running
            return .running
        }
    }
}
