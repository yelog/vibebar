import Foundation
import SQLite3

public struct OpenCodeUsageLoader {
    private struct CacheSignature {
        let modificationTimeIntervalSince1970: TimeInterval
        let fileSize: Int64
    }

    private struct SQLiteFailure: LocalizedError {
        let message: String

        var errorDescription: String? {
            message
        }
    }

    private let baseDirectory: URL?
    private let environment: [String: String]
    private let cacheStore: UsageFileCacheStore?

    public init(
        baseDirectory: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        cacheStore: UsageFileCacheStore? = nil
    ) {
        self.baseDirectory = baseDirectory
        self.environment = environment
        self.cacheStore = cacheStore
    }

    public func load() async throws -> UsageLoadResult {
        let root = resolvedRoot()
        guard let root else {
            let missingPath = defaultRoot().path
            return UsageLoadResult(missingDirectories: [missingPath])
        }

        var warnings: [String] = []
        do {
            if let databaseResult = try loadDatabaseIfAvailable(at: root) {
                return databaseResult
            }
        } catch {
            let databaseURL = root.appendingPathComponent("opencode.db", isDirectory: false)
            warnings.append("OpenCode usage 数据库解析失败: \(databaseURL.path)")
        }

        let legacyResult = try loadLegacyMessages(at: root)
        return UsageLoadResult(
            events: legacyResult.events,
            warnings: Array(Set(legacyResult.warnings + warnings)).sorted(),
            missingDirectories: legacyResult.missingDirectories
        )
    }

    private func loadDatabaseIfAvailable(at root: URL) throws -> UsageLoadResult? {
        let databaseURL = root.appendingPathComponent("opencode.db", isDirectory: false)
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            return nil
        }

        let cacheKey = "sqlite:\(databaseURL.path)"
        let signature = try databaseCacheSignature(for: databaseURL)
        let cachedEntries = (try? cacheStore?.load(source: .opencode))?.entries ?? [:]

        if let cached = cachedEntries[cacheKey],
           cached.fileSize == signature.fileSize,
           cached.modificationTimeIntervalSince1970 == signature.modificationTimeIntervalSince1970 {
            return UsageLoadResult(events: cached.events)
        }

        let events = try loadDatabaseEvents(from: databaseURL)
        if let cacheStore {
            let entry = UsageCachedFileEntry(
                modificationTimeIntervalSince1970: signature.modificationTimeIntervalSince1970,
                fileSize: signature.fileSize,
                events: events
            )
            try? cacheStore.write(
                UsageSourceFileCache(entries: [cacheKey: entry]),
                source: .opencode
            )
        }
        return UsageLoadResult(events: events)
    }

    private func loadLegacyMessages(at root: URL) throws -> UsageLoadResult {
        let messagesRoot = root.appendingPathComponent("storage/message", isDirectory: true)
        guard FileManager.default.fileExists(atPath: messagesRoot.path) else {
            return UsageLoadResult(missingDirectories: [messagesRoot.path])
        }

        var events: [UsageEvent] = []
        var warnings: [String] = []
        let cachedEntries = (try? cacheStore?.load(source: .opencode))?.entries ?? [:]
        var nextEntries: [String: UsageCachedFileEntry] = [:]

        for file in UsageLoaderSupport.recursivelyEnumerateFiles(under: messagesRoot, pathExtension: "json") {
            let cacheKey = file.url.path
            if let cached = cachedEntries[cacheKey],
               cached.fileSize == file.fileSize,
               cached.modificationTimeIntervalSince1970 == file.modificationTime.timeIntervalSince1970 {
                events.append(contentsOf: cached.events)
                nextEntries[cacheKey] = cached
                continue
            }

            do {
                let fileEvents: [UsageEvent]
                if let event = try loadEvent(from: file.url) {
                    fileEvents = [event]
                    events.append(event)
                } else {
                    fileEvents = []
                }
                nextEntries[cacheKey] = UsageCachedFileEntry(
                    modificationTimeIntervalSince1970: file.modificationTime.timeIntervalSince1970,
                    fileSize: file.fileSize,
                    events: fileEvents
                )
            } catch {
                warnings.append("OpenCode usage 解析失败: \(file.url.path)")
                if let cached = cachedEntries[cacheKey] {
                    events.append(contentsOf: cached.events)
                    nextEntries[cacheKey] = cached
                }
            }
        }

        if let cacheStore {
            try? cacheStore.write(
                UsageSourceFileCache(entries: nextEntries),
                source: .opencode
            )
        }
        return UsageLoadResult(events: events, warnings: warnings)
    }

    private func loadDatabaseEvents(from databaseURL: URL) throws -> [UsageEvent] {
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

        let query = """
        SELECT
            id,
            session_id,
            time_created,
            COALESCE(json_extract(data, '$.modelID'), 'unknown') AS model_id,
            json_extract(data, '$.cost') AS cost,
            COALESCE(json_extract(data, '$.tokens.input'), 0) AS input_tokens,
            COALESCE(json_extract(data, '$.tokens.output'), 0) AS output_tokens,
            COALESCE(json_extract(data, '$.tokens.cache.read'), 0) AS cache_read_tokens,
            COALESCE(json_extract(data, '$.tokens.cache.write'), 0) AS cache_write_tokens
        FROM message
        WHERE
            COALESCE(json_extract(data, '$.tokens.input'), 0) > 0 OR
            COALESCE(json_extract(data, '$.tokens.output'), 0) > 0 OR
            COALESCE(json_extract(data, '$.tokens.cache.read'), 0) > 0 OR
            COALESCE(json_extract(data, '$.tokens.cache.write'), 0) > 0
        ORDER BY time_created ASC
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteFailure(message: sqliteErrorMessage(from: database))
        }
        defer {
            sqlite3_finalize(statement)
        }

        var events: [UsageEvent] = []
        while true {
            let stepResult = sqlite3_step(statement)
            if stepResult == SQLITE_DONE {
                break
            }
            guard stepResult == SQLITE_ROW else {
                throw SQLiteFailure(message: sqliteErrorMessage(from: database))
            }

            let identifier = sqliteTextValue(statement, column: 0) ?? UUID().uuidString
            let sessionID = sqliteTextValue(statement, column: 1) ?? "unknown"
            let createdTime = Double(sqliteIntValue(statement, column: 2))
            let modelName = sqliteTextValue(statement, column: 3) ?? "unknown"
            let rawCost = sqliteDoubleValue(statement, column: 4)
            let inputTokens = sqliteIntValue(statement, column: 5)
            let outputTokens = sqliteIntValue(statement, column: 6)
            let cacheReadTokens = sqliteIntValue(statement, column: 7)
            let cacheWriteTokens = sqliteIntValue(statement, column: 8)

            let timestamp = Date(
                timeIntervalSince1970: Self.normalizedUnixTimestampSeconds(createdTime)
            )
            let costUSD = (rawCost ?? 0) > 0 ? rawCost : nil
            events.append(
                UsageEvent(
                    id: "opencode:\(identifier)",
                    source: .opencode,
                    sessionID: sessionID,
                    timestamp: timestamp,
                    modelName: modelName,
                    inputTokens: inputTokens,
                    outputTokens: outputTokens,
                    cacheReadTokens: cacheReadTokens,
                    cacheWriteTokens: cacheWriteTokens,
                    costUSD: costUSD
                )
            )
        }

        return events
    }

    private func databaseCacheSignature(for databaseURL: URL) throws -> CacheSignature {
        let databaseSignature = try fileSignature(for: databaseURL)
        let walURL = URL(fileURLWithPath: databaseURL.path + "-wal", isDirectory: false)
        let walSignature = try fileSignatureIfPresent(for: walURL)

        return CacheSignature(
            modificationTimeIntervalSince1970: max(
                databaseSignature.modificationTimeIntervalSince1970,
                walSignature?.modificationTimeIntervalSince1970 ?? 0
            ),
            fileSize: databaseSignature.fileSize + (walSignature?.fileSize ?? 0)
        )
    }

    private func fileSignature(for fileURL: URL) throws -> CacheSignature {
        let values = try fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return CacheSignature(
            modificationTimeIntervalSince1970: values.contentModificationDate?.timeIntervalSince1970 ?? 0,
            fileSize: Int64(values.fileSize ?? 0)
        )
    }

    private func fileSignatureIfPresent(for fileURL: URL) throws -> CacheSignature? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        return try fileSignature(for: fileURL)
    }

    private func resolvedRoot() -> URL? {
        if let baseDirectory {
            return FileManager.default.fileExists(atPath: baseDirectory.path) ? baseDirectory : nil
        }
        let root = defaultRoot()
        return FileManager.default.fileExists(atPath: root.path) ? root : nil
    }

    private func defaultRoot() -> URL {
        if let raw = environment["OPENCODE_DATA_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            return URL(fileURLWithPath: UsageLoaderSupport.expandedPath(raw), isDirectory: true)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".local/share/opencode", isDirectory: true)
    }

    private func loadEvent(from fileURL: URL) throws -> UsageEvent? {
        let data = try Data(contentsOf: fileURL)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let sessionID = (object["sessionID"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
        let modelName = (object["modelID"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
        let createdTime = Self.doubleValue((object["time"] as? [String: Any])?["created"])
        let timestamp = Date(
            timeIntervalSince1970: Self.normalizedUnixTimestampSeconds(
                createdTime ?? Date().timeIntervalSince1970
            )
        )

        let tokens = object["tokens"] as? [String: Any]
        let cache = tokens?["cache"] as? [String: Any]
        let inputTokens = Self.intValue(tokens?["input"])
        let outputTokens = Self.intValue(tokens?["output"])
        let cacheReadTokens = Self.intValue(cache?["read"])
        let cacheWriteTokens = Self.intValue(cache?["write"])
        if inputTokens == 0 && outputTokens == 0 && cacheReadTokens == 0 && cacheWriteTokens == 0 {
            return nil
        }

        let rawCost = Self.doubleValue(object["cost"])
        let costUSD = (rawCost ?? 0) > 0 ? rawCost : nil
        return UsageEvent(
            id: "opencode:\(fileURL.path)",
            source: .opencode,
            sessionID: sessionID,
            timestamp: timestamp,
            modelName: modelName,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: cacheReadTokens,
            cacheWriteTokens: cacheWriteTokens,
            costUSD: costUSD
        )
    }

    private static func intValue(_ value: Any?) -> Int {
        if let value = value as? Int { return max(0, value) }
        if let value = value as? NSNumber { return max(0, value.intValue) }
        if let value = value as? String, let parsed = Int(value) { return max(0, parsed) }
        return 0
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private static func normalizedUnixTimestampSeconds(_ raw: Double) -> Double {
        // OpenCode currently stores `time.created` in milliseconds.
        // Keep second-based timestamps working in case the upstream format changes.
        raw > 10_000_000_000 ? raw / 1_000.0 : raw
    }

    private func sqliteErrorMessage(from database: OpaquePointer?) -> String {
        guard let database, let message = sqlite3_errmsg(database) else {
            return "unknown sqlite error"
        }
        return String(cString: message)
    }

    private func sqliteTextValue(_ statement: OpaquePointer?, column: Int32) -> String? {
        guard let text = sqlite3_column_text(statement, column) else {
            return nil
        }
        return String(cString: text)
    }

    private func sqliteIntValue(_ statement: OpaquePointer?, column: Int32) -> Int {
        switch sqlite3_column_type(statement, column) {
        case SQLITE_INTEGER:
            return max(0, Int(sqlite3_column_int64(statement, column)))
        case SQLITE_FLOAT:
            return max(0, Int(sqlite3_column_double(statement, column)))
        case SQLITE_TEXT:
            guard let raw = sqliteTextValue(statement, column: column), let value = Int(raw) else {
                return 0
            }
            return max(0, value)
        default:
            return 0
        }
    }

    private func sqliteDoubleValue(_ statement: OpaquePointer?, column: Int32) -> Double? {
        switch sqlite3_column_type(statement, column) {
        case SQLITE_FLOAT:
            return sqlite3_column_double(statement, column)
        case SQLITE_INTEGER:
            return Double(sqlite3_column_int64(statement, column))
        case SQLITE_TEXT:
            guard let raw = sqliteTextValue(statement, column: column) else {
                return nil
            }
            return Double(raw)
        default:
            return nil
        }
    }
}
