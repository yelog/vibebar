import Foundation
import SQLite3

/// Detects OpenCode sessions via HTTP API, with SQLite DB fallback.
/// OpenCode exposes localhost endpoints for session status. When no HTTP port
/// is available (common for newer OpenCode versions), falls back to reading
/// session metadata from the SQLite database at `~/.local/share/opencode/opencode.db`.
public struct OpenCodeHTTPDetector: AgentDetector {
    static let cwdFallbackFreshnessGrace: TimeInterval = 5

    private struct SessionBatch: Sendable {
        let process: DetectorSupport.ProcEntry
        let port: Int
        let sessions: [GlobalSession]
        let statuses: SessionStatuses?
        let terminalContext: TerminalContext?
    }

    private let dataDirectory: URL?
    private let environment: [String: String]

    public init(
        dataDirectory: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.dataDirectory = dataDirectory
        self.environment = environment
    }

    public func detectSessions() async -> [SessionSnapshot] {
        let context = DetectorSupport.makeContext()
        return await detectSessions(context: context)
    }

    func detectSessions(context: DetectorSupport.DetectionContext) async -> [SessionSnapshot] {
        let processes = findOpenCodeProcesses(in: context.processes)
        var batches: [SessionBatch] = []
        var noPortProcesses: [DetectorSupport.ProcEntry] = []

        for process in processes {
            if let port = await DetectorSupport.findListeningPort(pid: process.pid),
               let sessions = await fetchSessions(port: port) {
                let statuses = await fetchSessionStatuses(port: port)
                let terminalContext = await TerminalContextResolver.resolve(
                    process: process,
                    context: context,
                    originHint: .cli
                )

                batches.append(
                    SessionBatch(
                        process: process,
                        port: port,
                        sessions: sessions,
                        statuses: statuses,
                        terminalContext: terminalContext
                    )
                )
            } else {
                noPortProcesses.append(process)
            }
        }

        let lastActivityBySessionID = OpenCodeSessionActivityStore.loadLastActivityBySessionID(
            sessionIDs: Set(batches.flatMap { $0.sessions.map(\.id) }),
            dataDirectory: dataDirectory,
            environment: environment
        )
        let messageSummaryBySessionID = OpenCodeSessionActivityStore.loadMessageSummariesBySessionID(
            sessionIDs: Set(batches.flatMap { $0.sessions.map(\.id) }),
            dataDirectory: dataDirectory,
            environment: environment
        )

        var results: [SessionSnapshot] = []

        // HTTP-based sessions
        for batch in batches {
            for session in batch.sessions {
                let messageSummary = messageSummaryBySessionID[session.id]
                let status: ToolActivityState
                if let statuses = batch.statuses {
                    status = statuses.values[session.id] ?? (statuses.isEmpty ? .idle : .unknown)
                } else {
                    status = .unknown
                }

                let updatedAt = Date(timeIntervalSince1970: TimeInterval(session.time.updated) / 1000)
                let idleSince = status == .idle
                    ? (lastActivityBySessionID[session.id] ?? updatedAt)
                    : nil
                let statusSince: Date = switch status {
                case .completed:
                    idleSince ?? updatedAt
                case .idle:
                    idleSince ?? updatedAt
                case .running, .awaitingInput, .unknown:
                    updatedAt
                }

                results.append(
                    SessionSnapshot(
                        id: "opencode-http-\(session.id)",
                        tool: .opencode,
                        pid: batch.process.pid,
                        parentPID: batch.process.ppid,
                        status: status,
                        source: .processScan,
                        startedAt: Date(timeIntervalSince1970: TimeInterval(session.time.created) / 1000),
                        updatedAt: updatedAt,
                        statusSince: statusSince,
                        idleSince: idleSince,
                        lastOutputAt: nil,
                        lastInputAt: nil,
                        cwd: session.directory,
                        command: ["opencode"],
                        notes: "HTTP API: port \(batch.port), title: \(session.title ?? "-")",
                        title: session.title,
                        titleSource: session.title == nil ? nil : .explicit,
                        currentTask: messageSummary?.runningSummary ?? session.title,
                        lastUserMessage: messageSummary?.lastUserMessage,
                        runningSummary: messageSummary?.runningSummary,
                        terminalContext: batch.terminalContext
                    )
                )
            }
        }

        // SQLite fallback for processes without HTTP ports
        if !noPortProcesses.isEmpty {
            let cwds = await DetectorSupport.bulkGetCwds(pids: noPortProcesses.map(\.pid))
            let sqliteSessions = loadSessionsFromSQLite(processes: noPortProcesses, cwds: cwds)
            let sqliteSessionIDs = Set(sqliteSessions.compactMap(\.sessionId))
            let sqliteMessageSummaryBySessionID = OpenCodeSessionActivityStore.loadMessageSummariesBySessionID(
                sessionIDs: sqliteSessionIDs,
                dataDirectory: dataDirectory,
                environment: environment
            )

            for session in sqliteSessions {
                let process = session.process
                let messageSummary = session.sessionId.flatMap { sqliteMessageSummaryBySessionID[$0] }
                let terminalContext = await TerminalContextResolver.resolve(
                    process: process,
                    context: context,
                    originHint: .cli
                )

                let updatedAt = session.timeUpdated ?? Date()
                let startedAt = session.timeCreated ?? Date()
                let status: ToolActivityState = process.cpu >= 0.5 ? .running : .idle
                let idleSince = status == .idle ? updatedAt : nil

                results.append(
                    SessionSnapshot(
                        id: "opencode-http-\(session.sessionId ?? "pid-\(process.pid)")",
                        tool: .opencode,
                        pid: process.pid,
                        parentPID: process.ppid,
                        status: status,
                        source: .sessionFile,
                        startedAt: startedAt,
                        updatedAt: updatedAt,
                        idleSince: idleSince,
                        lastOutputAt: nil,
                        lastInputAt: nil,
                        cwd: session.cwd ?? cwds[process.pid],
                        command: ["opencode"],
                        notes: "SQLite fallback, session: \(session.sessionId ?? "-")",
                        title: session.title,
                        titleSource: session.title == nil ? nil : .explicit,
                        currentTask: messageSummary?.runningSummary ?? session.title,
                        lastUserMessage: messageSummary?.lastUserMessage,
                        runningSummary: messageSummary?.runningSummary,
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

    // MARK: - SQLite Fallback

    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    struct SQLiteSessionInfo {
        let process: DetectorSupport.ProcEntry
        let sessionId: String?
        let title: String?
        let cwd: String?
        let timeCreated: Date?
        let timeUpdated: Date?
    }

    /// Extract session ID from process arguments (e.g., `-s ses_xxx` or `--session ses_xxx`).
    private func parseSessionIdFromArgs(_ args: String) -> String? {
        let tokens = args.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        for (index, token) in tokens.enumerated() {
            if (token == "-s" || token == "--session"), index + 1 < tokens.count {
                let candidate = tokens[index + 1]
                if candidate.hasPrefix("ses_") {
                    return candidate
                }
            }
        }
        return nil
    }

    /// Load session info from SQLite DB for processes that have no HTTP port.
    func loadSessionsFromSQLite(
        processes: [DetectorSupport.ProcEntry],
        cwds: [Int32: String],
        now: Date = Date()
    ) -> [SQLiteSessionInfo] {
        guard let root = resolvedRoot() else { return [] }

        let databaseURL = root.appendingPathComponent("opencode.db", isDirectory: false)
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return [] }

        var database: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            if let database { sqlite3_close(database) }
            return []
        }
        defer { sqlite3_close(database) }

        sqlite3_busy_timeout(database, 2_000)

        var results: [SQLiteSessionInfo] = []

        for process in processes {
            let explicitSessionId = parseSessionIdFromArgs(process.args)
            let cwd = cwds[process.pid]
            let processStartedAt = estimatedProcessStartedAt(process: process, now: now)

            if let sessionId = explicitSessionId {
                // Direct lookup by session ID
                if let info = querySessionById(database: database, sessionId: sessionId) {
                    results.append(SQLiteSessionInfo(
                        process: process,
                        sessionId: sessionId,
                        title: info.title,
                        cwd: info.directory ?? cwd,
                        timeCreated: info.timeCreated,
                        timeUpdated: info.timeUpdated
                    ))
                    continue
                }
            }

            // Fall back to CWD -> project -> most recent session
            if let cwd, !cwd.isEmpty, cwd != "/" {
                // A fresh opencode process without a reliable session ID should not
                // inherit an older same-project session just because the worktree matches.
                if let info = querySessionByCwd(database: database, cwd: cwd),
                   shouldReuseCwdFallback(info: info, process: process, now: now) {
                    results.append(SQLiteSessionInfo(
                        process: process,
                        sessionId: info.sessionId,
                        title: info.title,
                        cwd: info.directory ?? cwd,
                        timeCreated: info.timeCreated,
                        timeUpdated: info.timeUpdated
                    ))
                    continue
                }
            }

            // No match found — still emit a session with no title
            results.append(SQLiteSessionInfo(
                process: process,
                sessionId: nil,
                title: nil,
                cwd: cwd,
                timeCreated: processStartedAt,
                timeUpdated: processStartedAt
            ))
        }

        return results
    }

    private struct SessionQueryResult {
        let sessionId: String?
        let title: String?
        let directory: String?
        let timeCreated: Date?
        let timeUpdated: Date?
    }

    /// Query session by explicit session ID.
    private func querySessionById(database: OpaquePointer?, sessionId: String) -> SessionQueryResult? {
        let query = """
        SELECT id, title, directory, time_created, time_updated
        FROM session
        WHERE id = ?
        LIMIT 1
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, sessionId, -1, Self.sqliteTransient)

        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }

        return SessionQueryResult(
            sessionId: sqliteText(statement, column: 0),
            title: sqliteText(statement, column: 1),
            directory: sqliteText(statement, column: 2),
            timeCreated: sqliteDate(statement, column: 3),
            timeUpdated: sqliteDate(statement, column: 4)
        )
    }

    /// Query most recently updated non-archived session for a given CWD.
    private func querySessionByCwd(database: OpaquePointer?, cwd: String) -> SessionQueryResult? {
        let query = """
        SELECT s.id, s.title, s.directory, s.time_created, s.time_updated
        FROM session s
        JOIN project p ON s.project_id = p.id
        WHERE (s.directory = ? OR p.worktree = ?)
          AND s.parent_id IS NULL
          AND s.time_archived IS NULL
        ORDER BY CASE WHEN s.directory = ? THEN 0 ELSE 1 END, s.time_updated DESC
        LIMIT 1
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, cwd, -1, Self.sqliteTransient)
        sqlite3_bind_text(statement, 2, cwd, -1, Self.sqliteTransient)
        sqlite3_bind_text(statement, 3, cwd, -1, Self.sqliteTransient)

        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }

        return SessionQueryResult(
            sessionId: sqliteText(statement, column: 0),
            title: sqliteText(statement, column: 1),
            directory: sqliteText(statement, column: 2),
            timeCreated: sqliteDate(statement, column: 3),
            timeUpdated: sqliteDate(statement, column: 4)
        )
    }

    private func shouldReuseCwdFallback(
        info: SessionQueryResult,
        process: DetectorSupport.ProcEntry,
        now: Date
    ) -> Bool {
        guard let sessionCreatedAt = info.timeCreated else {
            return false
        }

        let processStartedAt = estimatedProcessStartedAt(process: process, now: now)
        return sessionCreatedAt.timeIntervalSince(processStartedAt) >= -Self.cwdFallbackFreshnessGrace
    }

    private func estimatedProcessStartedAt(
        process: DetectorSupport.ProcEntry,
        now: Date
    ) -> Date {
        now.addingTimeInterval(-TimeInterval(max(process.elapsedSeconds, 0)))
    }

    private func resolvedRoot() -> URL? {
        if let dataDirectory {
            return FileManager.default.fileExists(atPath: dataDirectory.path) ? dataDirectory : nil
        }

        if let raw = environment["OPENCODE_DATA_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            let resolved = URL(fileURLWithPath: UsageLoaderSupport.expandedPath(raw), isDirectory: true)
            return FileManager.default.fileExists(atPath: resolved.path) ? resolved : nil
        }

        let fallback = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/opencode", isDirectory: true)
        return FileManager.default.fileExists(atPath: fallback.path) ? fallback : nil
    }

    private func sqliteText(_ statement: OpaquePointer?, column: Int32) -> String? {
        guard let text = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: text)
    }

    private func sqliteDate(_ statement: OpaquePointer?, column: Int32) -> Date? {
        let raw = sqlite3_column_double(statement, column)
        guard raw > 0 else { return nil }
        // OpenCode stores timestamps in milliseconds
        let seconds = raw > 10_000_000_000 ? raw / 1_000.0 : raw
        return Date(timeIntervalSince1970: seconds)
    }
}
