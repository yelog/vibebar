import Foundation
import SQLite3
import Testing
@testable import VibeBarCore

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

@Test func openCodeSessionActivityStoreLoadsLatestMessageTimestampPerSession() throws {
    let root = try makeActivityStoreTemporaryDirectory(prefix: "opencode-activity-store")
    defer { try? FileManager.default.removeItem(at: root) }

    let databaseURL = root.appendingPathComponent("opencode.db", isDirectory: false)
    try createMessageActivityDatabase(
        at: databaseURL,
        rows: [
            ("msg-1", "session-a", 1_770_000_000_000),
            ("msg-2", "session-a", 1_770_000_300_000),
            ("msg-3", "session-b", 1_770_000_100_000),
        ]
    )

    let activity = OpenCodeSessionActivityStore.loadLastActivityBySessionID(
        sessionIDs: Set(["session-a", "session-b", "session-c"]),
        dataDirectory: root
    )

    #expect(activity["session-a"] == Date(timeIntervalSince1970: 1_770_000_300))
    #expect(activity["session-b"] == Date(timeIntervalSince1970: 1_770_000_100))
    #expect(activity["session-c"] == nil)
}

@Test func openCodeSessionActivityStoreSkipsLowSignalUserMessageAndKeepsLastMeaningfulPrompt() throws {
    let root = try makeActivityStoreTemporaryDirectory(prefix: "opencode-activity-summary")
    defer { try? FileManager.default.removeItem(at: root) }

    let databaseURL = root.appendingPathComponent("opencode.db", isDirectory: false)
    try createMessageSummaryDatabase(
        at: databaseURL,
        rows: [
            MessageSummaryRow(
                messageID: "msg-1",
                sessionID: "session-a",
                role: "user",
                messageTimeCreated: 1_770_000_000_000,
                partID: "part-1",
                partTimeCreated: 1_770_000_000_000,
                partJSON: ["type": "text", "text": "请结合代码分析当前 readme 的质量，有哪些缺失"]
            ),
            MessageSummaryRow(
                messageID: "msg-2",
                sessionID: "session-a",
                role: "user",
                messageTimeCreated: 1_770_000_300_000,
                partID: "part-2",
                partTimeCreated: 1_770_000_300_000,
                partJSON: ["type": "text", "text": "要"]
            ),
        ]
    )

    let summaries = OpenCodeSessionActivityStore.loadMessageSummariesBySessionID(
        sessionIDs: Set(["session-a"]),
        dataDirectory: root
    )

    #expect(summaries["session-a"]?.lastUserMessage == "请结合代码分析当前 readme 的质量，有哪些缺失")
}

private func createMessageActivityDatabase(
    at url: URL,
    rows: [(id: String, sessionID: String, timeCreated: Int64)]
) throws {
    var database: OpaquePointer?
    guard sqlite3_open(url.path, &database) == SQLITE_OK else {
        throw DatabaseError.open
    }
    defer {
        sqlite3_close(database)
    }

    guard sqlite3_exec(
        database,
        """
        CREATE TABLE message (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            time_created INTEGER NOT NULL
        );
        """,
        nil,
        nil,
        nil
    ) == SQLITE_OK else {
        throw DatabaseError.schema
    }

    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(
        database,
        "INSERT INTO message (id, session_id, time_created) VALUES (?, ?, ?)",
        -1,
        &statement,
        nil
    ) == SQLITE_OK else {
        throw DatabaseError.insert
    }
    defer {
        sqlite3_finalize(statement)
    }

    for row in rows {
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
        sqlite3_bind_text(statement, 1, row.id, -1, sqliteTransient)
        sqlite3_bind_text(statement, 2, row.sessionID, -1, sqliteTransient)
        sqlite3_bind_int64(statement, 3, row.timeCreated)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.insert
        }
    }
}

private enum DatabaseError: Error {
    case open
    case schema
    case insert
}

private struct MessageSummaryRow {
    let messageID: String
    let sessionID: String
    let role: String
    let messageTimeCreated: Int64
    let partID: String
    let partTimeCreated: Int64
    let partJSON: [String: Any]
}

private func createMessageSummaryDatabase(
    at url: URL,
    rows: [MessageSummaryRow]
) throws {
    var database: OpaquePointer?
    guard sqlite3_open(url.path, &database) == SQLITE_OK else {
        throw DatabaseError.open
    }
    defer {
        sqlite3_close(database)
    }

    guard sqlite3_exec(
        database,
        """
        CREATE TABLE message (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            time_created INTEGER NOT NULL,
            time_updated INTEGER NOT NULL,
            data TEXT NOT NULL
        );

        CREATE TABLE part (
            id TEXT PRIMARY KEY,
            message_id TEXT NOT NULL,
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
    defer {
        sqlite3_finalize(messageStatement)
    }

    var partStatement: OpaquePointer?
    guard sqlite3_prepare_v2(
        database,
        "INSERT INTO part (id, message_id, session_id, time_created, time_updated, data) VALUES (?, ?, ?, ?, ?, ?)",
        -1,
        &partStatement,
        nil
    ) == SQLITE_OK else {
        throw DatabaseError.insert
    }
    defer {
        sqlite3_finalize(partStatement)
    }

    for row in rows {
        sqlite3_reset(messageStatement)
        sqlite3_clear_bindings(messageStatement)
        sqlite3_bind_text(messageStatement, 1, row.messageID, -1, sqliteTransient)
        sqlite3_bind_text(messageStatement, 2, row.sessionID, -1, sqliteTransient)
        sqlite3_bind_int64(messageStatement, 3, row.messageTimeCreated)
        sqlite3_bind_int64(messageStatement, 4, row.messageTimeCreated)
        let messageData = try JSONSerialization.data(withJSONObject: ["role": row.role], options: [])
        let messageJSONString = String(decoding: messageData, as: UTF8.self)
        sqlite3_bind_text(messageStatement, 5, messageJSONString, -1, sqliteTransient)
        guard sqlite3_step(messageStatement) == SQLITE_DONE else {
            throw DatabaseError.insert
        }

        sqlite3_reset(partStatement)
        sqlite3_clear_bindings(partStatement)
        sqlite3_bind_text(partStatement, 1, row.partID, -1, sqliteTransient)
        sqlite3_bind_text(partStatement, 2, row.messageID, -1, sqliteTransient)
        sqlite3_bind_text(partStatement, 3, row.sessionID, -1, sqliteTransient)
        sqlite3_bind_int64(partStatement, 4, row.partTimeCreated)
        sqlite3_bind_int64(partStatement, 5, row.partTimeCreated)
        let partData = try JSONSerialization.data(withJSONObject: row.partJSON, options: [])
        let partJSONString = String(decoding: partData, as: UTF8.self)
        sqlite3_bind_text(partStatement, 6, partJSONString, -1, sqliteTransient)
        guard sqlite3_step(partStatement) == SQLITE_DONE else {
            throw DatabaseError.insert
        }
    }
}

private func makeActivityStoreTemporaryDirectory(prefix: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}
