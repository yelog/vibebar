import Foundation
import SQLite3

enum OpenCodeSessionActivityStore {
    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private struct SQLiteFailure: LocalizedError {
        let message: String

        var errorDescription: String? {
            message
        }
    }

    static func loadLastActivityBySessionID(
        sessionIDs: Set<String>,
        dataDirectory: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: Date] {
        guard !sessionIDs.isEmpty,
              let root = resolvedRoot(dataDirectory: dataDirectory, environment: environment) else {
            return [:]
        }

        let databaseURL = root.appendingPathComponent("opencode.db", isDirectory: false)
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            return [:]
        }

        return (try? loadLastActivityBySessionID(sessionIDs: sessionIDs, databaseURL: databaseURL)) ?? [:]
    }

    private static func loadLastActivityBySessionID(
        sessionIDs: Set<String>,
        databaseURL: URL
    ) throws -> [String: Date] {
        var database: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            defer {
                if let database {
                    sqlite3_close(database)
                }
            }
            throw SQLiteFailure(message: "无法打开数据库")
        }
        defer {
            sqlite3_close(database)
        }

        sqlite3_busy_timeout(database, 2_000)

        let orderedSessionIDs = sessionIDs.sorted()
        let placeholders = Array(repeating: "?", count: orderedSessionIDs.count).joined(separator: ",")
        let query = """
        SELECT session_id, MAX(time_created)
        FROM message
        WHERE session_id IN (\(placeholders))
        GROUP BY session_id
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteFailure(message: sqliteErrorMessage(from: database))
        }
        defer {
            sqlite3_finalize(statement)
        }

        for (index, sessionID) in orderedSessionIDs.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), sessionID, -1, sqliteTransient)
        }

        var result: [String: Date] = [:]
        while true {
            let stepResult = sqlite3_step(statement)
            if stepResult == SQLITE_DONE {
                break
            }
            guard stepResult == SQLITE_ROW else {
                throw SQLiteFailure(message: sqliteErrorMessage(from: database))
            }

            guard let sessionID = sqliteTextValue(statement, column: 0) else {
                continue
            }
            let rawTime = sqlite3_column_double(statement, 1)
            result[sessionID] = Date(timeIntervalSince1970: normalizedUnixTimestampSeconds(rawTime))
        }

        return result
    }

    private static func resolvedRoot(
        dataDirectory: URL?,
        environment: [String: String]
    ) -> URL? {
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

    private static func normalizedUnixTimestampSeconds(_ raw: Double) -> Double {
        raw > 10_000_000_000 ? raw / 1_000.0 : raw
    }

    private static func sqliteErrorMessage(from database: OpaquePointer?) -> String {
        guard let database, let message = sqlite3_errmsg(database) else {
            return "unknown sqlite error"
        }
        return String(cString: message)
    }

    private static func sqliteTextValue(_ statement: OpaquePointer?, column: Int32) -> String? {
        guard let text = sqlite3_column_text(statement, column) else {
            return nil
        }
        return String(cString: text)
    }
}
