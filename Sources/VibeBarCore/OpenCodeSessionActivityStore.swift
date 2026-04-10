import Foundation
import SQLite3

enum OpenCodeSessionActivityStore {
    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    struct SessionMessageSummary: Sendable, Equatable {
        let lastUserMessage: String?
        let runningSummary: String?
    }

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

    static func loadMessageSummariesBySessionID(
        sessionIDs: Set<String>,
        dataDirectory: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: SessionMessageSummary] {
        guard !sessionIDs.isEmpty,
              let root = resolvedRoot(dataDirectory: dataDirectory, environment: environment) else {
            return [:]
        }

        let databaseURL = root.appendingPathComponent("opencode.db", isDirectory: false)
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            return [:]
        }

        return (try? loadMessageSummariesBySessionID(sessionIDs: sessionIDs, databaseURL: databaseURL)) ?? [:]
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

    private static func loadMessageSummariesBySessionID(
        sessionIDs: Set<String>,
        databaseURL: URL
    ) throws -> [String: SessionMessageSummary] {
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
        SELECT p.session_id, m.data, p.data
        FROM part p
        JOIN message m ON p.message_id = m.id
        WHERE p.session_id IN (\(placeholders))
        ORDER BY p.time_created DESC
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

        struct PartialSummary {
            var lastUserMessage: String?
            var runningSummary: String?

            var isComplete: Bool {
                lastUserMessage != nil && runningSummary != nil
            }
        }

        var partials = Dictionary(uniqueKeysWithValues: orderedSessionIDs.map { ($0, PartialSummary()) })
        var unresolved = Set(orderedSessionIDs)

        while !unresolved.isEmpty {
            let stepResult = sqlite3_step(statement)
            if stepResult == SQLITE_DONE {
                break
            }
            guard stepResult == SQLITE_ROW else {
                throw SQLiteFailure(message: sqliteErrorMessage(from: database))
            }

            guard let sessionID = sqliteTextValue(statement, column: 0),
                  unresolved.contains(sessionID),
                  var partial = partials[sessionID],
                  let messageData = sqliteTextValue(statement, column: 1)?.data(using: .utf8),
                  let partData = sqliteTextValue(statement, column: 2)?.data(using: .utf8),
                  let messageJSON = (try? JSONSerialization.jsonObject(with: messageData)) as? [String: Any],
                  let partJSON = (try? JSONSerialization.jsonObject(with: partData)) as? [String: Any]
            else {
                continue
            }

            let role = normalizedString(messageJSON["role"])
            if partial.lastUserMessage == nil, role == "user" {
                partial.lastUserMessage = userMessage(from: partJSON)
            }
            if partial.runningSummary == nil, role == "assistant" {
                partial.runningSummary = assistantSummary(from: partJSON)
            }

            partials[sessionID] = partial
            if partial.isComplete {
                unresolved.remove(sessionID)
            }
        }

        return partials.reduce(into: [:]) { result, entry in
            let value = entry.value
            guard value.lastUserMessage != nil || value.runningSummary != nil else {
                return
            }
            result[entry.key] = SessionMessageSummary(
                lastUserMessage: value.lastUserMessage,
                runningSummary: value.runningSummary
            )
        }
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

    private static func userMessage(from partJSON: [String: Any]) -> String? {
        let type = normalizedString(partJSON["type"])
        guard type == "text" || type == "reasoning" else {
            return nil
        }
        guard let summary = summarizeText(normalizedString(partJSON["text"])),
              !isLowSignalUserMessage(summary) else {
            return nil
        }
        return summary
    }

    private static func assistantSummary(from partJSON: [String: Any]) -> String? {
        let type = normalizedString(partJSON["type"])

        switch type {
        case "text", "reasoning":
            return summarizeText(normalizedString(partJSON["text"]))
        case "tool":
            if let state = partJSON["state"] as? [String: Any] {
                if let title = normalizedString(state["title"]) {
                    return summarizeText(title)
                }
                if let input = state["input"] as? [String: Any] {
                    if let description = normalizedString(input["description"]) {
                        return summarizeText(description)
                    }
                    if let command = normalizedString(input["command"]) {
                        return summarizeText(command)
                    }
                }
            }
            if let tool = normalizedString(partJSON["tool"]) {
                return tool
            }
            return nil
        case "patch":
            if let files = partJSON["files"] as? [String], !files.isEmpty {
                let names = files.map { URL(fileURLWithPath: $0).lastPathComponent }
                if let first = names.first, names.count == 1 {
                    return "更新 \(first)"
                }
                return "更新 \(names.count) 个文件"
            }
            return "正在修改文件"
        case "step-start":
            return "处理中"
        case "step-finish":
            if let reason = normalizedString(partJSON["reason"]), reason == "tool-calls" {
                return "处理中"
            }
            return nil
        default:
            return nil
        }
    }

    private static func summarizeText(_ text: String?, maxLength: Int = 120) -> String? {
        guard let text else { return nil }
        let firstLine = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        guard var firstLine, !firstLine.isEmpty else { return nil }
        firstLine = firstLine.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        if firstLine.count <= maxLength {
            return firstLine
        }
        return String(firstLine.prefix(maxLength - 1)) + "…"
    }

    private static func isLowSignalUserMessage(_ text: String) -> Bool {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalized.isEmpty else {
            return true
        }

        let exactMatches: Set<String> = [
            "好",
            "好的",
            "行",
            "可以",
            "嗯",
            "哦",
            "要",
            "是",
            "否",
            "继续",
            "继续吧",
            "ok",
            "okay",
            "yes",
            "no",
            "continue",
        ]
        if exactMatches.contains(normalized) {
            return true
        }

        return normalized.count <= 2
    }

    private static func normalizedString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
