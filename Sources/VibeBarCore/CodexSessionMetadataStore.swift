import Foundation
import SQLite3

struct CodexSessionMetadata: Sendable {
    var id: String
    var title: String?
    var firstUserMessage: String?
    var cwd: String?
    var rolloutPath: String?
    var source: String?
    var updatedAt: Date?

    var hasContent: Bool {
        title != nil ||
            firstUserMessage != nil ||
            cwd != nil ||
            rolloutPath != nil ||
            source != nil ||
            updatedAt != nil
    }
}

struct CodexSessionMetadataStore {
    private let baseDirectory: URL

    init(
        baseDirectory: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        if let baseDirectory {
            self.baseDirectory = baseDirectory
        } else if let raw = environment["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty {
            self.baseDirectory = URL(
                fileURLWithPath: UsageLoaderSupport.expandedPath(raw),
                isDirectory: true
            )
        } else {
            self.baseDirectory = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex", isDirectory: true)
        }
    }

    func metadata(for sessionID: String) -> CodexSessionMetadata? {
        let indexRecord = loadSessionIndexRecord(for: sessionID)
        let threadRecord = loadThreadRecord(for: sessionID)

        var metadata = CodexSessionMetadata(id: sessionID)
        metadata.title = preferredTitle(indexTitle: indexRecord?.title, threadTitle: threadRecord?.title)
        metadata.firstUserMessage = normalized(threadRecord?.firstUserMessage)
        metadata.cwd = normalized(threadRecord?.cwd)
        metadata.rolloutPath = normalized(threadRecord?.rolloutPath)
        metadata.source = normalized(threadRecord?.source)
        metadata.updatedAt = latest(indexRecord?.updatedAt, threadRecord?.updatedAt)

        return metadata.hasContent ? metadata : nil
    }

    private func loadSessionIndexRecord(for sessionID: String) -> SessionIndexRecord? {
        let url = baseDirectory.appendingPathComponent("session_index.jsonl", isDirectory: false)
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let date = DetectorSupport.parseISO8601(value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid ISO8601 date"
                )
            }
            return date
        }

        for line in content.split(whereSeparator: \.isNewline) {
            let raw = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty,
                  let data = raw.data(using: .utf8),
                  let record = try? decoder.decode(SessionIndexRecord.self, from: data),
                  record.id == sessionID else {
                continue
            }
            return record
        }

        return nil
    }

    private func loadThreadRecord(for sessionID: String) -> ThreadRecord? {
        let databaseURL = baseDirectory.appendingPathComponent("state_5.sqlite", isDirectory: false)
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            return nil
        }

        var database: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database else {
            if let database {
                sqlite3_close(database)
            }
            return nil
        }
        defer { sqlite3_close(database) }

        sqlite3_busy_timeout(database, 2_000)

        let query = "SELECT * FROM threads WHERE id = ? LIMIT 1;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, sessionID, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }

        var valuesByName: [String: SQLiteValue] = [:]
        for index in 0..<sqlite3_column_count(statement) {
            let columnName = String(cString: sqlite3_column_name(statement, index))
            valuesByName[columnName] = sqliteValue(statement: statement, index: index)
        }

        let updatedAt = dateValue(
            milliseconds: valuesByName["updated_at_ms"]?.int64Value,
            seconds: valuesByName["updated_at"]?.int64Value
        )

        return ThreadRecord(
            id: sessionID,
            title: valuesByName["title"]?.stringValue,
            firstUserMessage: valuesByName["first_user_message"]?.stringValue,
            cwd: valuesByName["cwd"]?.stringValue,
            rolloutPath: valuesByName["rollout_path"]?.stringValue,
            source: valuesByName["source"]?.stringValue,
            updatedAt: updatedAt
        )
    }

    private func preferredTitle(indexTitle: String?, threadTitle: String?) -> String? {
        let threadTitle = normalized(threadTitle)
        if let threadTitle, !looksLikePlaceholderTitle(threadTitle) {
            return threadTitle
        }

        let indexTitle = normalized(indexTitle)
        if let indexTitle, !looksLikePlaceholderTitle(indexTitle) {
            return indexTitle
        }

        return threadTitle ?? indexTitle
    }

    private func looksLikePlaceholderTitle(_ value: String) -> Bool {
        let lowered = value.lowercased()
        return lowered == "new session" ||
            lowered == "new chat" ||
            lowered.hasPrefix("new session ") ||
            lowered.hasPrefix("new chat ")
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func latest(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            return lhs > rhs ? lhs : rhs
        case let (lhs?, nil):
            return lhs
        case let (nil, rhs?):
            return rhs
        case (nil, nil):
            return nil
        }
    }

    private func dateValue(milliseconds: Int64?, seconds: Int64?) -> Date? {
        if let milliseconds, milliseconds > 0 {
            return Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1_000)
        }
        if let seconds, seconds > 0 {
            return Date(timeIntervalSince1970: TimeInterval(seconds))
        }
        return nil
    }

    private func sqliteValue(statement: OpaquePointer?, index: Int32) -> SQLiteValue {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER:
            return .integer(sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT:
            return .float(sqlite3_column_double(statement, index))
        case SQLITE_TEXT:
            guard let text = sqlite3_column_text(statement, index) else {
                return .null
            }
            return .text(String(cString: text))
        default:
            return .null
        }
    }

    private struct SessionIndexRecord: Decodable, Sendable {
        let id: String
        let title: String?
        let updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case id
            case title = "thread_name"
            case updatedAt = "updated_at"
        }
    }

    private struct ThreadRecord: Sendable {
        let id: String
        let title: String?
        let firstUserMessage: String?
        let cwd: String?
        let rolloutPath: String?
        let source: String?
        let updatedAt: Date?
    }

    private enum SQLiteValue {
        case integer(Int64)
        case float(Double)
        case text(String)
        case null

        var int64Value: Int64? {
            switch self {
            case let .integer(value):
                return value
            case let .float(value):
                return Int64(value)
            case let .text(value):
                return Int64(value)
            case .null:
                return nil
            }
        }

        var stringValue: String? {
            switch self {
            case let .integer(value):
                return String(value)
            case let .float(value):
                return String(value)
            case let .text(value):
                return value
            case .null:
                return nil
            }
        }
    }
}
