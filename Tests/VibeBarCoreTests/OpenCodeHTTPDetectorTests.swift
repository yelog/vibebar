import Foundation
import SQLite3
import Testing
@testable import VibeBarCore

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

@Test func openCodeSQLiteFallbackRejectsHistoricalSameProjectSessionWithoutSessionID() throws {
    let root = try makeOpenCodeDetectorTemporaryDirectory(prefix: "opencode-http-detector")
    defer { try? FileManager.default.removeItem(at: root) }

    let worktree = "/Users/yelog/workspace/swift/VibeBar"
    let now = Date(timeIntervalSince1970: 1_777_000_200)
    try createOpenCodeSessionDatabase(
        at: root.appendingPathComponent("opencode.db", isDirectory: false),
        worktree: worktree,
        sessions: [
            SQLiteSessionRow(
                id: "ses_old",
                title: "旧会话标题",
                directory: worktree,
                timeCreated: 1_777_000_000_000,
                timeUpdated: 1_777_000_199_000
            )
        ]
    )

    let detector = OpenCodeHTTPDetector(dataDirectory: root, environment: [:])
    let process = makeOpenCodeProcess(pid: 4242, elapsedSeconds: 10, args: "opencode")

    let sessions = detector.loadSessionsFromSQLite(
        processes: [process],
        cwds: [process.pid: worktree],
        now: now
    )

    let session = try #require(sessions.first)
    #expect(session.sessionId == nil)
    #expect(session.title == nil)
    #expect(session.cwd == worktree)
    #expect(session.timeCreated == Date(timeIntervalSince1970: 1_777_000_190))
    #expect(session.timeUpdated == Date(timeIntervalSince1970: 1_777_000_190))
}

@Test func openCodeSQLiteFallbackAcceptsFreshSameProjectSessionWithoutSessionID() throws {
    let root = try makeOpenCodeDetectorTemporaryDirectory(prefix: "opencode-http-detector")
    defer { try? FileManager.default.removeItem(at: root) }

    let worktree = "/Users/yelog/workspace/swift/VibeBar"
    let now = Date(timeIntervalSince1970: 1_777_000_200)
    try createOpenCodeSessionDatabase(
        at: root.appendingPathComponent("opencode.db", isDirectory: false),
        worktree: worktree,
        sessions: [
            SQLiteSessionRow(
                id: "ses_fresh",
                title: "新会话标题",
                directory: worktree,
                timeCreated: 1_777_000_192_000,
                timeUpdated: 1_777_000_199_000
            )
        ]
    )

    let detector = OpenCodeHTTPDetector(dataDirectory: root, environment: [:])
    let process = makeOpenCodeProcess(pid: 4343, elapsedSeconds: 10, args: "opencode")

    let sessions = detector.loadSessionsFromSQLite(
        processes: [process],
        cwds: [process.pid: worktree],
        now: now
    )

    let session = try #require(sessions.first)
    #expect(session.sessionId == "ses_fresh")
    #expect(session.title == "新会话标题")
    #expect(session.cwd == worktree)
    #expect(session.timeCreated == Date(timeIntervalSince1970: 1_777_000_192))
    #expect(session.timeUpdated == Date(timeIntervalSince1970: 1_777_000_199))
}

@Test func openCodeSQLiteFallbackDoesNotReuseOneSessionForAmbiguousSameCWDProcesses() throws {
    let root = try makeOpenCodeDetectorTemporaryDirectory(prefix: "opencode-http-detector")
    defer { try? FileManager.default.removeItem(at: root) }

    let worktree = "/Users/yelog/workspace/swift/VibeBar"
    let now = Date(timeIntervalSince1970: 1_777_000_200)
    try createOpenCodeSessionDatabase(
        at: root.appendingPathComponent("opencode.db", isDirectory: false),
        worktree: worktree,
        sessions: [
            SQLiteSessionRow(
                id: "ses_shared",
                title: "共享会话",
                directory: worktree,
                timeCreated: 1_777_000_192_000,
                timeUpdated: 1_777_000_199_000
            )
        ]
    )

    let detector = OpenCodeHTTPDetector(dataDirectory: root, environment: [:])
    let first = makeOpenCodeProcess(pid: 4344, elapsedSeconds: 10, args: "opencode")
    let second = makeOpenCodeProcess(pid: 4345, elapsedSeconds: 20, args: "opencode")

    let sessions = detector.loadSessionsFromSQLite(
        processes: [first, second],
        cwds: [first.pid: worktree, second.pid: worktree],
        now: now
    )

    #expect(sessions.count == 2)
    #expect(sessions.allSatisfy { $0.sessionId == nil })
}

@Test func openCodeSQLiteFallbackExplicitSessionClaimsBeforeCWDFallback() throws {
    let root = try makeOpenCodeDetectorTemporaryDirectory(prefix: "opencode-http-detector")
    defer { try? FileManager.default.removeItem(at: root) }

    let worktree = "/Users/yelog/workspace/swift/VibeBar"
    let now = Date(timeIntervalSince1970: 1_777_000_200)
    try createOpenCodeSessionDatabase(
        at: root.appendingPathComponent("opencode.db", isDirectory: false),
        worktree: worktree,
        sessions: [
            SQLiteSessionRow(
                id: "ses_shared",
                title: "共享会话",
                directory: worktree,
                timeCreated: 1_777_000_192_000,
                timeUpdated: 1_777_000_199_000
            )
        ]
    )

    let detector = OpenCodeHTTPDetector(dataDirectory: root, environment: [:])
    let explicit = makeOpenCodeProcess(
        pid: 4346,
        elapsedSeconds: 10,
        args: "opencode -s ses_shared"
    )
    let fallback = makeOpenCodeProcess(pid: 4347, elapsedSeconds: 20, args: "opencode")

    let sessions = detector.loadSessionsFromSQLite(
        processes: [explicit, fallback],
        cwds: [explicit.pid: worktree, fallback.pid: worktree],
        now: now
    )

    #expect(sessions.first { $0.process.pid == explicit.pid }?.sessionId == "ses_shared")
    #expect(sessions.first { $0.process.pid == fallback.pid }?.sessionId == nil)
}

@Test func openCodeSQLiteFallbackMatchesSessionDirectoryWhenProjectWorktreeDiffers() throws {
    let root = try makeOpenCodeDetectorTemporaryDirectory(prefix: "opencode-http-detector")
    defer { try? FileManager.default.removeItem(at: root) }

    let actualWorktree = "/Users/yelog/workspace/lenovo/opencode/moss-base"
    let now = Date(timeIntervalSince1970: 1_777_000_200)
    try createOpenCodeSessionDatabase(
        at: root.appendingPathComponent("opencode.db", isDirectory: false),
        worktree: "/",
        sessions: [
            SQLiteSessionRow(
                id: "ses_global",
                title: "恢复目录匹配标题",
                directory: actualWorktree,
                timeCreated: 1_777_000_192_000,
                timeUpdated: 1_777_000_199_000
            )
        ]
    )

    let detector = OpenCodeHTTPDetector(dataDirectory: root, environment: [:])
    let process = makeOpenCodeProcess(pid: 4444, elapsedSeconds: 10, args: "opencode")

    let sessions = detector.loadSessionsFromSQLite(
        processes: [process],
        cwds: [process.pid: actualWorktree],
        now: now
    )

    let session = try #require(sessions.first)
    #expect(session.sessionId == "ses_global")
    #expect(session.title == "恢复目录匹配标题")
    #expect(session.cwd == actualWorktree)
}

@Test func openCodeSQLiteStatusIsIdleWhenLatestAssistantMessageHasTerminalFinish() throws {
    let worktree = "/Users/yelog/workspace/swift/VibeBar"
    let root = try makeOpenCodeDetectorTemporaryDirectory(prefix: "opencode-http-detector")
    defer { try? FileManager.default.removeItem(at: root) }

    try createOpenCodeSessionDatabase(
        at: root.appendingPathComponent("opencode.db", isDirectory: false),
        worktree: worktree,
        sessions: [
            SQLiteSessionRow(
                id: "ses_status",
                title: "状态会话",
                directory: worktree,
                timeCreated: 1_777_000_100_000,
                timeUpdated: 1_777_000_199_000
            )
        ],
        messages: [
            SQLiteMessageRow(sessionId: "ses_status", timeCreated: 1_777_000_199_000, data: "{\"role\":\"assistant\",\"finish\":\"stop\"}")
        ]
    )

    let detector = OpenCodeHTTPDetector(dataDirectory: root, environment: [:])
    let process = makeOpenCodeProcess(pid: 4545, elapsedSeconds: 10, args: "opencode -s ses_status")

    let sessions = detector.loadSessionsFromSQLite(
        processes: [process],
        cwds: [process.pid: worktree],
        now: Date(timeIntervalSince1970: 1_777_000_200)
    )

    #expect(sessions.first?.status == .idle)
}

@Test func openCodeSQLiteStatusIsRunningWhenLatestAssistantMessageHasToolCallsFinish() throws {
    let worktree = "/Users/yelog/workspace/swift/VibeBar"
    let root = try makeOpenCodeDetectorTemporaryDirectory(prefix: "opencode-http-detector")
    defer { try? FileManager.default.removeItem(at: root) }

    try createOpenCodeSessionDatabase(
        at: root.appendingPathComponent("opencode.db", isDirectory: false),
        worktree: worktree,
        sessions: [
            SQLiteSessionRow(
                id: "ses_status",
                title: "状态会话",
                directory: worktree,
                timeCreated: 1_777_000_100_000,
                timeUpdated: 1_777_000_199_000
            )
        ],
        messages: [
            SQLiteMessageRow(sessionId: "ses_status", timeCreated: 1_777_000_199_000, data: "{\"role\":\"assistant\",\"finish\":\"tool-calls\"}")
        ]
    )

    let detector = OpenCodeHTTPDetector(dataDirectory: root, environment: [:])
    let process = makeOpenCodeProcess(pid: 4545, elapsedSeconds: 10, args: "opencode -s ses_status")

    let sessions = detector.loadSessionsFromSQLite(
        processes: [process],
        cwds: [process.pid: worktree],
        now: Date(timeIntervalSince1970: 1_777_000_200)
    )

    #expect(sessions.first?.status == .running)
}

@Test func openCodeSQLiteStatusIsRunningWhenLatestMessageIsUser() throws {
    let worktree = "/Users/yelog/workspace/swift/VibeBar"
    let root = try makeOpenCodeDetectorTemporaryDirectory(prefix: "opencode-http-detector")
    defer { try? FileManager.default.removeItem(at: root) }

    try createOpenCodeSessionDatabase(
        at: root.appendingPathComponent("opencode.db", isDirectory: false),
        worktree: worktree,
        sessions: [
            SQLiteSessionRow(
                id: "ses_status",
                title: "状态会话",
                directory: worktree,
                timeCreated: 1_777_000_100_000,
                timeUpdated: 1_777_000_199_000
            )
        ],
        messages: [
            SQLiteMessageRow(sessionId: "ses_status", timeCreated: 1_777_000_199_000, data: "{\"role\":\"user\",\"text\":\"继续\"}")
        ]
    )

    let detector = OpenCodeHTTPDetector(dataDirectory: root, environment: [:])
    let process = makeOpenCodeProcess(pid: 4545, elapsedSeconds: 10, args: "opencode -s ses_status")

    let sessions = detector.loadSessionsFromSQLite(
        processes: [process],
        cwds: [process.pid: worktree],
        now: Date(timeIntervalSince1970: 1_777_000_200)
    )

    #expect(sessions.first?.status == .running)
}

@Test func openCodeSQLiteStatusFallsBackToNilWithoutMessages() throws {
    let worktree = "/Users/yelog/workspace/swift/VibeBar"
    let root = try makeOpenCodeDetectorTemporaryDirectory(prefix: "opencode-http-detector")
    defer { try? FileManager.default.removeItem(at: root) }

    try createOpenCodeSessionDatabase(
        at: root.appendingPathComponent("opencode.db", isDirectory: false),
        worktree: worktree,
        sessions: [
            SQLiteSessionRow(
                id: "ses_status",
                title: "状态会话",
                directory: worktree,
                timeCreated: 1_777_000_100_000,
                timeUpdated: 1_777_000_199_000
            )
        ]
    )

    let detector = OpenCodeHTTPDetector(dataDirectory: root, environment: [:])
    let process = makeOpenCodeProcess(pid: 4545, elapsedSeconds: 10, args: "opencode -s ses_status")

    let sessions = detector.loadSessionsFromSQLite(
        processes: [process],
        cwds: [process.pid: worktree],
        now: Date(timeIntervalSince1970: 1_777_000_200)
    )

    #expect(sessions.first?.status == nil)
}

private struct SQLiteMessageRow {
    let sessionId: String
    let timeCreated: Int64
    let data: String
}

private struct SQLiteSessionRow {
    let id: String
    let title: String
    let directory: String
    let timeCreated: Int64
    let timeUpdated: Int64
}

private enum DatabaseError: Error {
    case open
    case schema
    case insert
}

private func createOpenCodeSessionDatabase(
    at url: URL,
    worktree: String,
    sessions: [SQLiteSessionRow],
    messages: [SQLiteMessageRow] = []
) throws {
    var database: OpaquePointer?
    guard sqlite3_open(url.path, &database) == SQLITE_OK else {
        throw DatabaseError.open
    }
    defer { sqlite3_close(database) }

    guard sqlite3_exec(
        database,
        """
        CREATE TABLE project (
            id TEXT PRIMARY KEY,
            worktree TEXT NOT NULL
        );

        CREATE TABLE session (
            id TEXT PRIMARY KEY,
            project_id TEXT NOT NULL,
            parent_id TEXT,
            directory TEXT NOT NULL,
            title TEXT NOT NULL,
            time_created INTEGER NOT NULL,
            time_updated INTEGER NOT NULL,
            time_archived INTEGER
        );

        CREATE TABLE message (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            time_created INTEGER NOT NULL,
            time_updated INTEGER NOT NULL,
            data TEXT NOT NULL
        );
        """,
        nil,
        nil,
        nil
    ) == SQLITE_OK else {
        throw DatabaseError.schema
    }

    var projectStatement: OpaquePointer?
    guard sqlite3_prepare_v2(
        database,
        "INSERT INTO project (id, worktree) VALUES (?, ?)",
        -1,
        &projectStatement,
        nil
    ) == SQLITE_OK else {
        throw DatabaseError.insert
    }
    defer { sqlite3_finalize(projectStatement) }

    sqlite3_bind_text(projectStatement, 1, "project-1", -1, sqliteTransient)
    sqlite3_bind_text(projectStatement, 2, worktree, -1, sqliteTransient)
    guard sqlite3_step(projectStatement) == SQLITE_DONE else {
        throw DatabaseError.insert
    }

    var sessionStatement: OpaquePointer?
    guard sqlite3_prepare_v2(
        database,
        "INSERT INTO session (id, project_id, parent_id, directory, title, time_created, time_updated, time_archived) VALUES (?, ?, NULL, ?, ?, ?, ?, NULL)",
        -1,
        &sessionStatement,
        nil
    ) == SQLITE_OK else {
        throw DatabaseError.insert
    }
    defer { sqlite3_finalize(sessionStatement) }

    for row in sessions {
        sqlite3_reset(sessionStatement)
        sqlite3_clear_bindings(sessionStatement)
        sqlite3_bind_text(sessionStatement, 1, row.id, -1, sqliteTransient)
        sqlite3_bind_text(sessionStatement, 2, "project-1", -1, sqliteTransient)
        sqlite3_bind_text(sessionStatement, 3, row.directory, -1, sqliteTransient)
        sqlite3_bind_text(sessionStatement, 4, row.title, -1, sqliteTransient)
        sqlite3_bind_int64(sessionStatement, 5, row.timeCreated)
        sqlite3_bind_int64(sessionStatement, 6, row.timeUpdated)

        guard sqlite3_step(sessionStatement) == SQLITE_DONE else {
            throw DatabaseError.insert
        }
    }

    var messageStatement: OpaquePointer?
    guard sqlite3_prepare_v2(
        database,
        "INSERT INTO message (id, session_id, time_created, time_updated, data) VALUES (?, ?, ?, ?, ?)",
        -1,
        &messageStatement,
        nil
    ) == SQLITE_OK else {
        throw DatabaseError.insert
    }
    defer { sqlite3_finalize(messageStatement) }

    for (index, row) in messages.enumerated() {
        sqlite3_reset(messageStatement)
        sqlite3_clear_bindings(messageStatement)
        sqlite3_bind_text(messageStatement, 1, "msg-\(index)", -1, sqliteTransient)
        sqlite3_bind_text(messageStatement, 2, row.sessionId, -1, sqliteTransient)
        sqlite3_bind_int64(messageStatement, 3, row.timeCreated)
        sqlite3_bind_int64(messageStatement, 4, row.timeCreated)
        sqlite3_bind_text(messageStatement, 5, row.data, -1, sqliteTransient)

        guard sqlite3_step(messageStatement) == SQLITE_DONE else {
            throw DatabaseError.insert
        }
    }
}

private func makeOpenCodeDetectorTemporaryDirectory(prefix: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func makeOpenCodeProcess(
    pid: Int32,
    elapsedSeconds: Int,
    args: String
) -> DetectorSupport.ProcEntry {
    DetectorSupport.ProcEntry(
        pid: pid,
        ppid: 1,
        tty: "ttys001",
        state: "S",
        cpu: 0,
        elapsedSeconds: elapsedSeconds,
        command: "opencode",
        args: args
    )
}
