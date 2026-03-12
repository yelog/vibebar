import Foundation

public struct OpenCodeUsageLoader {
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
}
