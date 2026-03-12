import Foundation
import SQLite3
import Testing
@testable import VibeBarCore

@Test func claudeLoaderParsesUsageEntries() async throws {
    let root = try makeTemporaryDirectory(prefix: "claude-loader")
    defer { try? FileManager.default.removeItem(at: root) }

    let projectRoot = root.appendingPathComponent("projects/demo", isDirectory: true)
    try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
    let jsonl = projectRoot.appendingPathComponent("session-1.jsonl", isDirectory: false)
    try """
    {"timestamp":"2026-03-10T10:00:00.000Z","sessionId":"abc","costUSD":0.0042,"message":{"model":"claude-sonnet-4-5-20250929","usage":{"input_tokens":1000,"output_tokens":200,"cache_creation_input_tokens":50,"cache_read_input_tokens":25}}}
    {"timestamp":"2026-03-10T11:00:00.000Z","sessionId":"abc","message":{"model":"claude-sonnet-4-5-20250929","usage":{"input_tokens":500,"output_tokens":100}}}
    """.write(to: jsonl, atomically: true, encoding: .utf8)

    let result = try await ClaudeUsageLoader(searchRoots: [projectRoot.deletingLastPathComponent()]).load()

    #expect(result.events.count == 2)
    #expect(result.events.first?.source == .claudeCode)
    #expect(result.events.first?.sessionID == "abc")
    #expect(result.events.first?.cacheWriteTokens == 50)
    #expect(result.events.first?.costUSD == 0.0042)
}

@Test func codexLoaderBuildsDeltaEvents() async throws {
    let root = try makeTemporaryDirectory(prefix: "codex-loader")
    defer { try? FileManager.default.removeItem(at: root) }

    let fileURL = root.appendingPathComponent("project-1.jsonl", isDirectory: false)
    try """
    {"timestamp":"2026-03-11T18:25:30.000Z","type":"turn_context","payload":{"model":"gpt-5"}}
    {"timestamp":"2026-03-11T18:25:40.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1200,"cached_input_tokens":200,"output_tokens":500,"reasoning_output_tokens":0,"total_tokens":1700},"last_token_usage":{"input_tokens":1200,"cached_input_tokens":200,"output_tokens":500,"reasoning_output_tokens":0,"total_tokens":1700},"model":"gpt-5"}}}
    {"timestamp":"2026-03-11T18:26:40.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1700,"cached_input_tokens":300,"output_tokens":700,"reasoning_output_tokens":0,"total_tokens":2400},"model":"gpt-5"}}}
    """.write(to: fileURL, atomically: true, encoding: .utf8)

    let result = try await CodexUsageLoader(baseDirectory: root).load()

    #expect(result.events.count == 2)
    #expect(result.events[0].inputTokens == 1_200)
    #expect(result.events[1].inputTokens == 500)
    #expect(result.events[1].cacheReadTokens == 100)
    #expect(result.events[1].outputTokens == 200)
}

@Test func opencodeLoaderParsesMessageFiles() async throws {
    let root = try makeTemporaryDirectory(prefix: "opencode-loader")
    defer { try? FileManager.default.removeItem(at: root) }

    let messageRoot = root.appendingPathComponent("storage/message/session-1", isDirectory: true)
    try FileManager.default.createDirectory(at: messageRoot, withIntermediateDirectories: true)
    let messageURL = messageRoot.appendingPathComponent("msg_1.json", isDirectory: false)
    try """
    {"id":"msg_1","sessionID":"session-1","providerID":"anthropic","modelID":"claude-sonnet-4-5","time":{"created":1770000000000},"tokens":{"input":900,"output":300,"cache":{"read":50,"write":20}},"cost":0}
    """.write(to: messageURL, atomically: true, encoding: .utf8)

    let result = try await OpenCodeUsageLoader(baseDirectory: root).load()

    #expect(result.events.count == 1)
    #expect(result.events[0].source == .opencode)
    #expect(result.events[0].sessionID == "session-1")
    #expect(result.events[0].modelName == "claude-sonnet-4-5")
    #expect(result.events[0].timestamp == Date(timeIntervalSince1970: 1_770_000_000))
    #expect(result.events[0].costUSD == nil)
    #expect(result.events[0].cacheReadTokens == 50)
    #expect(result.events[0].cacheWriteTokens == 20)
}

@Test func opencodeLoaderParsesSQLiteMessages() async throws {
    let root = try makeTemporaryDirectory(prefix: "opencode-sqlite-loader")
    defer { try? FileManager.default.removeItem(at: root) }

    let databaseURL = root.appendingPathComponent("opencode.db", isDirectory: false)
    try createOpenCodeMessageDatabase(
        at: databaseURL,
        rows: [
            OpenCodeDatabaseFixtureRow(
                id: "msg_db_1",
                sessionID: "session-db",
                timeCreated: 1_770_000_100_000,
                data: """
                {"role":"assistant","time":{"created":1770000100000},"modelID":"k2p5","providerID":"kimi-for-coding","cost":0,"tokens":{"total":600,"input":400,"output":150,"cache":{"read":50,"write":0}}}
                """
            ),
        ]
    )

    let result = try await OpenCodeUsageLoader(baseDirectory: root).load()

    #expect(result.events.count == 1)
    #expect(result.events[0].source == .opencode)
    #expect(result.events[0].sessionID == "session-db")
    #expect(result.events[0].modelName == "k2p5")
    #expect(result.events[0].timestamp == Date(timeIntervalSince1970: 1_770_000_100))
    #expect(result.events[0].inputTokens == 400)
    #expect(result.events[0].outputTokens == 150)
    #expect(result.events[0].cacheReadTokens == 50)
    #expect(result.events[0].cacheWriteTokens == 0)
}

@Test func opencodeLoaderPrefersSQLiteOverLegacyFiles() async throws {
    let root = try makeTemporaryDirectory(prefix: "opencode-priority-loader")
    defer { try? FileManager.default.removeItem(at: root) }

    let databaseURL = root.appendingPathComponent("opencode.db", isDirectory: false)
    try createOpenCodeMessageDatabase(
        at: databaseURL,
        rows: [
            OpenCodeDatabaseFixtureRow(
                id: "msg_db_priority",
                sessionID: "session-db-priority",
                timeCreated: 1_770_000_200_000,
                data: """
                {"role":"assistant","time":{"created":1770000200000},"modelID":"gpt-4.1","providerID":"openai","cost":0.12,"tokens":{"total":300,"input":120,"output":80,"cache":{"read":100,"write":0}}}
                """
            ),
        ]
    )

    let messageRoot = root.appendingPathComponent("storage/message/session-legacy", isDirectory: true)
    try FileManager.default.createDirectory(at: messageRoot, withIntermediateDirectories: true)
    let messageURL = messageRoot.appendingPathComponent("msg_legacy.json", isDirectory: false)
    try """
    {"id":"msg_legacy","sessionID":"session-legacy","providerID":"anthropic","modelID":"claude-sonnet-4-5","time":{"created":1770000000000},"tokens":{"input":900,"output":300,"cache":{"read":50,"write":20}},"cost":0}
    """.write(to: messageURL, atomically: true, encoding: .utf8)

    let result = try await OpenCodeUsageLoader(baseDirectory: root).load()

    #expect(result.events.count == 1)
    #expect(result.events[0].sessionID == "session-db-priority")
    #expect(result.events[0].modelName == "gpt-4.1")
    #expect(result.events[0].costUSD == 0.12)
}

@Test func claudeLoaderRemovesDeletedFilesFromCache() async throws {
    let root = try makeTemporaryDirectory(prefix: "claude-loader-cache")
    defer { try? FileManager.default.removeItem(at: root) }

    let cacheDirectory = root.appendingPathComponent("cache", isDirectory: true)
    try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

    let projectRoot = root.appendingPathComponent("projects/demo", isDirectory: true)
    try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
    let jsonl = projectRoot.appendingPathComponent("session-1.jsonl", isDirectory: false)
    try """
    {"timestamp":"2026-03-10T10:00:00.000Z","sessionId":"abc","message":{"model":"claude-sonnet-4-5-20250929","usage":{"input_tokens":1000,"output_tokens":200}}}
    """.write(to: jsonl, atomically: true, encoding: .utf8)

    let cacheStore = UsageFileCacheStore(baseURL: cacheDirectory)
    let first = try await ClaudeUsageLoader(
        searchRoots: [projectRoot.deletingLastPathComponent()],
        cacheStore: cacheStore
    ).load()
    #expect(first.events.count == 1)

    try FileManager.default.removeItem(at: jsonl)

    let second = try await ClaudeUsageLoader(
        searchRoots: [projectRoot.deletingLastPathComponent()],
        cacheStore: cacheStore
    ).load()
    #expect(second.events.isEmpty)
}

private func makeTemporaryDirectory(prefix: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private struct OpenCodeDatabaseFixtureRow {
    let id: String
    let sessionID: String
    let timeCreated: Int64
    let data: String
}

private func createOpenCodeMessageDatabase(
    at databaseURL: URL,
    rows: [OpenCodeDatabaseFixtureRow]
) throws {
    var database: OpaquePointer?
    guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK else {
        defer {
            if let database {
                sqlite3_close(database)
            }
        }
        throw TestSQLiteFailure.openDatabase
    }
    defer {
        sqlite3_close(database)
    }

    try executeSQLite(
        """
        CREATE TABLE message (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            time_created INTEGER NOT NULL,
            time_updated INTEGER NOT NULL,
            data TEXT NOT NULL
        );
        """,
        database: database
    )

    var statement: OpaquePointer?
    let sql = "INSERT INTO message (id, session_id, time_created, time_updated, data) VALUES (?, ?, ?, ?, ?);"
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
        throw TestSQLiteFailure.prepareStatement
    }
    defer {
        sqlite3_finalize(statement)
    }

    for row in rows {
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
        sqlite3_bind_text(statement, 1, row.id, -1, sqliteTransientDestructor)
        sqlite3_bind_text(statement, 2, row.sessionID, -1, sqliteTransientDestructor)
        sqlite3_bind_int64(statement, 3, row.timeCreated)
        sqlite3_bind_int64(statement, 4, row.timeCreated)
        sqlite3_bind_text(statement, 5, row.data, -1, sqliteTransientDestructor)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw TestSQLiteFailure.insertRow
        }
    }
}

private func executeSQLite(_ sql: String, database: OpaquePointer?) throws {
    guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
        throw TestSQLiteFailure.executeStatement
    }
}

private enum TestSQLiteFailure: Error {
    case openDatabase
    case executeStatement
    case prepareStatement
    case insertRow
}

private let sqliteTransientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
