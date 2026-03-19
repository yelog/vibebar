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

@Test func claudeIncrementalRefreshRemovesDeletedResolvedEvents() async throws {
    let root = try makeTemporaryDirectory(prefix: "claude-incremental-delete")
    defer { try? FileManager.default.removeItem(at: root) }

    let projectRoot = root.appendingPathComponent("projects/demo", isDirectory: true)
    try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
    let jsonl = projectRoot.appendingPathComponent("session-1.jsonl", isDirectory: false)
    try """
    {"timestamp":"2026-03-10T10:00:00.000Z","sessionId":"abc","message":{"model":"claude-sonnet-4-5-20250929","usage":{"input_tokens":1000,"output_tokens":200}}}
    """.write(to: jsonl, atomically: true, encoding: .utf8)

    let loader = UsageIncrementalLoader(
        claudeLoader: ClaudeUsageLoader(searchRoots: [projectRoot.deletingLastPathComponent()])
    )

    let first = try await loader.refresh(
        currentState: .empty,
        sources: [.claudeCode],
        fullRefreshInterval: .sixHours,
        forceFullRefresh: true
    )
    #expect(first.state.resolvedEvents.count == 1)
    #expect(first.state.fileSignatures(for: .claudeCode).count == 1)

    try FileManager.default.removeItem(at: jsonl)

    let second = try await loader.refresh(
        currentState: first.state,
        sources: [.claudeCode],
        fullRefreshInterval: .sixHours,
        forceFullRefresh: false
    )

    #expect(second.isFullRefresh == false)
    #expect(second.state.resolvedEvents.isEmpty)
    #expect(second.state.fileSignatures(for: .claudeCode).isEmpty)
}

@Test func claudeFullRefreshReusesExistingEventsForUnchangedUnreadableFiles() async throws {
    let root = try makeTemporaryDirectory(prefix: "claude-full-reuse")
    defer { try? FileManager.default.removeItem(at: root) }

    let projectRoot = root.appendingPathComponent("projects/demo", isDirectory: true)
    try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
    let jsonl = projectRoot.appendingPathComponent("session-1.jsonl", isDirectory: false)
    try """
    {"timestamp":"2026-03-10T10:00:00.000Z","sessionId":"abc","message":{"model":"claude-sonnet-4-5-20250929","usage":{"input_tokens":1000,"output_tokens":200}}}
    """.write(to: jsonl, atomically: true, encoding: .utf8)

    let loader = UsageIncrementalLoader(
        claudeLoader: ClaudeUsageLoader(searchRoots: [projectRoot.deletingLastPathComponent()])
    )

    let first = try await loader.refresh(
        currentState: .empty,
        sources: [.claudeCode],
        fullRefreshInterval: .sixHours,
        forceFullRefresh: true
    )
    #expect(first.state.resolvedEvents.count == 1)

    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: jsonl.path)
    defer {
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: jsonl.path)
    }

    let second = try await loader.refresh(
        currentState: first.state,
        sources: [.claudeCode],
        fullRefreshInterval: .sixHours,
        forceFullRefresh: true
    )

    #expect(second.state.resolvedEvents.count == 1)
    #expect(second.state.warnings.isEmpty)
}

@Test func parserVersionMismatchForcesFullRefresh() async throws {
    let root = try makeTemporaryDirectory(prefix: "claude-parser-version")
    defer { try? FileManager.default.removeItem(at: root) }

    let projectRoot = root.appendingPathComponent("projects/demo", isDirectory: true)
    try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
    let jsonl = projectRoot.appendingPathComponent("session-1.jsonl", isDirectory: false)
    try """
    {"timestamp":"2026-03-10T10:00:00.000Z","sessionId":"abc","message":{"model":"claude-sonnet-4-5-20250929","usage":{"input_tokens":1000,"output_tokens":200}}}
    """.write(to: jsonl, atomically: true, encoding: .utf8)

    let loader = UsageIncrementalLoader(
        claudeLoader: ClaudeUsageLoader(searchRoots: [projectRoot.deletingLastPathComponent()])
    )

    let first = try await loader.refresh(
        currentState: .empty,
        sources: [.claudeCode],
        fullRefreshInterval: .sixHours,
        forceFullRefresh: true
    )
    #expect(first.isFullRefresh == true)

    var staleState = first.state
    staleState.setParserVersion(0, for: .claudeCode)

    let second = try await loader.refresh(
        currentState: staleState,
        sources: [.claudeCode],
        fullRefreshInterval: .sixHours,
        forceFullRefresh: false
    )

    #expect(second.isFullRefresh == true)
    #expect(second.state.parserVersion(for: .claudeCode) == ClaudeUsageLoader.parserVersion)
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
        CREATE TABLE session (
            id TEXT PRIMARY KEY,
            project_id TEXT NOT NULL,
            parent_id TEXT,
            slug TEXT NOT NULL,
            directory TEXT NOT NULL,
            title TEXT NOT NULL,
            version TEXT NOT NULL,
            share_url TEXT,
            summary_additions INTEGER,
            summary_deletions INTEGER,
            summary_files INTEGER,
            summary_diffs TEXT,
            revert TEXT,
            permission TEXT,
            time_created INTEGER NOT NULL,
            time_updated INTEGER NOT NULL,
            time_compacting INTEGER,
            time_archived INTEGER,
            workspace_id TEXT
        );
        """,
        database: database
    )

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

    var sessionStatement: OpaquePointer?
    let sessionSQL = "INSERT INTO session (id, project_id, slug, directory, title, version, time_created, time_updated) VALUES (?, ?, ?, ?, ?, ?, ?, ?);"
    guard sqlite3_prepare_v2(database, sessionSQL, -1, &sessionStatement, nil) == SQLITE_OK else {
        throw TestSQLiteFailure.prepareStatement
    }
    defer {
        sqlite3_finalize(sessionStatement)
    }

    let sessionIDs = Set(rows.map(\.sessionID))
    for sessionID in sessionIDs {
        sqlite3_reset(sessionStatement)
        sqlite3_clear_bindings(sessionStatement)
        sqlite3_bind_text(sessionStatement, 1, sessionID, -1, sqliteTransientDestructor)
        sqlite3_bind_text(sessionStatement, 2, "test-project", -1, sqliteTransientDestructor)
        sqlite3_bind_text(sessionStatement, 3, "test-slug", -1, sqliteTransientDestructor)
        sqlite3_bind_text(sessionStatement, 4, "/Users/test/projects/test-project", -1, sqliteTransientDestructor)
        sqlite3_bind_text(sessionStatement, 5, "Test Session", -1, sqliteTransientDestructor)
        sqlite3_bind_text(sessionStatement, 6, "1.0.0", -1, sqliteTransientDestructor)
        sqlite3_bind_int64(sessionStatement, 7, 1_770_000_000_000)
        sqlite3_bind_int64(sessionStatement, 8, 1_770_000_000_000)

        guard sqlite3_step(sessionStatement) == SQLITE_DONE else {
            throw TestSQLiteFailure.insertRow
        }
    }

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
