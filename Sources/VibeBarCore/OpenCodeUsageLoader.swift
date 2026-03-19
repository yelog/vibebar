import Foundation
import SQLite3

public struct OpenCodeUsageLoader: UsageLoader {
    public static let parserVersion = 1

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

    public var source: UsageSource { .opencode }

    public init(
        baseDirectory: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        cacheStore: UsageFileCacheStore? = nil
    ) {
        self.baseDirectory = baseDirectory
        self.environment = environment
        self.cacheStore = cacheStore
    }

    public func load(request: UsageLoadRequest = UsageLoadRequest(cutoffDate: nil)) async throws -> UsageLoadResult {
        let root = resolvedRoot()
        guard let root else {
            let missingPath = defaultRoot().path
            return UsageLoadResult(missingDirectories: [missingPath])
        }

        let effectiveCutoff = request.effectiveCutoffDate()
        let databaseURL = root.appendingPathComponent("opencode.db", isDirectory: false)

        do {
            if let databaseResult = try loadDatabaseIfAvailable(at: root, cutoffDate: effectiveCutoff) {
                return databaseResult
            }
        } catch {
            return UsageLoadResult(
                warnings: ["OpenCode usage 数据库解析失败: \(databaseURL.path)"]
            )
        }

        // Database doesn't exist - return empty result (skip legacy JSON files)
        return UsageLoadResult(
            missingDirectories: [databaseURL.path]
        )
    }

    private func loadDatabaseIfAvailable(at root: URL, cutoffDate: Date?) throws -> UsageLoadResult? {
        let databaseURL = root.appendingPathComponent("opencode.db", isDirectory: false)
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            return nil
        }

        let cacheKey = "sqlite:\(databaseURL.path)"
        let signature = try databaseCacheSignature(for: databaseURL)
        let cachedEntries = (try? cacheStore?.load(source: .opencode))
            .flatMap { cache in
                cache.parserVersion == Self.parserVersion ? cache : nil
            }?.entries ?? [:]

        if cutoffDate == nil,
           let cached = cachedEntries[cacheKey],
           cached.fileSize == signature.fileSize,
           cached.modificationTimeIntervalSince1970 == signature.modificationTimeIntervalSince1970 {
            return UsageLoadResult(
                events: cached.events,
                fileSignatures: [cacheKey: UsageFileSignature(
                    modificationTime: Date(timeIntervalSince1970: signature.modificationTimeIntervalSince1970),
                    fileSize: signature.fileSize
                )]
            )
        }

        let events = try loadDatabaseEvents(from: databaseURL, cutoffDate: cutoffDate)

        if cutoffDate == nil, let cacheStore {
            let entry = UsageCachedFileEntry(
                modificationTimeIntervalSince1970: signature.modificationTimeIntervalSince1970,
                fileSize: signature.fileSize,
                events: events
            )
            try? cacheStore.write(
                UsageSourceFileCache(
                    parserVersion: Self.parserVersion,
                    entries: [cacheKey: entry]
                ),
                source: .opencode
            )
        }
        return UsageLoadResult(
            events: events,
            fileSignatures: [cacheKey: UsageFileSignature(
                modificationTime: Date(timeIntervalSince1970: signature.modificationTimeIntervalSince1970),
                fileSize: signature.fileSize
            )]
        )
    }

    private func loadLegacyMessages(at root: URL, cutoffDate: Date?) throws -> (
        events: [UsageEvent],
        warnings: [String],
        missingDirectories: [String],
        fileSignatures: [String: UsageFileSignature]
    ) {
        let messagesRoot = root.appendingPathComponent("storage/message", isDirectory: true)
        guard FileManager.default.fileExists(atPath: messagesRoot.path) else {
            return ([], [], [messagesRoot.path], [:])
        }

        var events: [UsageEvent] = []
        var warnings: [String] = []
        var fileSignatures: [String: UsageFileSignature] = [:]
        let cachedEntries = (try? cacheStore?.load(source: .opencode))
            .flatMap { cache in
                cache.parserVersion == Self.parserVersion ? cache : nil
            }?.entries ?? [:]
        var nextEntries: [String: UsageCachedFileEntry] = [:]

        for file in UsageLoaderSupport.recursivelyEnumerateFiles(
            under: messagesRoot,
            pathExtension: "json",
            cutoffDate: cutoffDate
        ) {
            let cacheKey = file.url.path
            fileSignatures[cacheKey] = UsageFileSignature(
                modificationTime: file.modificationTime,
                fileSize: file.fileSize
            )
            if let cached = cachedEntries[cacheKey],
               cached.fileSize == file.fileSize,
               cached.modificationTimeIntervalSince1970 == file.modificationTime.timeIntervalSince1970 {
                events.append(contentsOf: cached.events)
                nextEntries[cacheKey] = cached
                continue
            }

            do {
                let fileEvents: [UsageEvent]
                if let event = try loadEvent(from: file.url, cutoffDate: cutoffDate) {
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
                UsageSourceFileCache(
                    parserVersion: Self.parserVersion,
                    entries: nextEntries
                ),
                source: .opencode
            )
        }
        return (events, warnings, [], fileSignatures)
    }

    private func loadDatabaseEvents(from databaseURL: URL, cutoffDate: Date?) throws -> [UsageEvent] {
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

        // 构建查询，支持时间过滤
        var query: String
        if let cutoffDate {
            // OpenCode 的 time_created 是毫秒级时间戳
            let cutoffMillis = Int64(cutoffDate.timeIntervalSince1970 * 1000)
            query = """
            SELECT
                m.id,
                m.session_id,
                m.time_created,
                COALESCE(json_extract(m.data, '$.modelID'), 'unknown') AS model_id,
                json_extract(m.data, '$.cost') AS cost,
                COALESCE(json_extract(m.data, '$.tokens.input'), 0) AS input_tokens,
                COALESCE(json_extract(m.data, '$.tokens.output'), 0) AS output_tokens,
                COALESCE(json_extract(m.data, '$.tokens.cache.read'), 0) AS cache_read_tokens,
                COALESCE(json_extract(m.data, '$.tokens.cache.write'), 0) AS cache_write_tokens,
                s.directory AS working_directory
            FROM message m
            LEFT JOIN session s ON m.session_id = s.id
            WHERE
                m.time_created >= \(cutoffMillis)
                AND (
                    COALESCE(json_extract(m.data, '$.tokens.input'), 0) > 0 OR
                    COALESCE(json_extract(m.data, '$.tokens.output'), 0) > 0 OR
                    COALESCE(json_extract(m.data, '$.tokens.cache.read'), 0) > 0 OR
                    COALESCE(json_extract(m.data, '$.tokens.cache.write'), 0) > 0
                )
            ORDER BY m.time_created ASC
            """
        } else {
            query = """
            SELECT
                m.id,
                m.session_id,
                m.time_created,
                COALESCE(json_extract(m.data, '$.modelID'), 'unknown') AS model_id,
                json_extract(m.data, '$.cost') AS cost,
                COALESCE(json_extract(m.data, '$.tokens.input'), 0) AS input_tokens,
                COALESCE(json_extract(m.data, '$.tokens.output'), 0) AS output_tokens,
                COALESCE(json_extract(m.data, '$.tokens.cache.read'), 0) AS cache_read_tokens,
                COALESCE(json_extract(m.data, '$.tokens.cache.write'), 0) AS cache_write_tokens,
                s.directory AS working_directory
            FROM message m
            LEFT JOIN session s ON m.session_id = s.id
            WHERE
                COALESCE(json_extract(m.data, '$.tokens.input'), 0) > 0 OR
                COALESCE(json_extract(m.data, '$.tokens.output'), 0) > 0 OR
                COALESCE(json_extract(m.data, '$.tokens.cache.read'), 0) > 0 OR
                COALESCE(json_extract(m.data, '$.tokens.cache.write'), 0) > 0
            ORDER BY m.time_created ASC
            """
        }

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
            let workingDirectory = sqliteTextValue(statement, column: 9)

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
                    costUSD: costUSD,
                    workingDirectory: workingDirectory
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

    public func resolveRoots() -> (roots: [URL], warnings: [String], missingDirectories: [String]) {
        // Return empty roots to prevent incremental loader from scanning legacy JSON files
        // Only SQLite database should be used (via load() method)
        return ([], [], [])
    }

    public func loadEventsFromFile(url: URL, cutoffDate: Date?) throws -> [UsageEvent] {
        if url.pathExtension == "json" {
            if let event = try loadEvent(from: url, cutoffDate: cutoffDate) {
                return [event]
            }
            return []
        }
        return []
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

    public func loadEvent(from fileURL: URL, cutoffDate: Date?) throws -> UsageEvent? {
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

        // 如果指定了cutoffDate，过滤掉旧数据
        if let cutoffDate, timestamp < cutoffDate {
            return nil
        }

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
