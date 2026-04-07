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

private func makeActivityStoreTemporaryDirectory(prefix: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}
