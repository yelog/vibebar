import Foundation

public struct GeminiUsageLoader: UsageLoader {
    public static let parserVersion = 2

    private struct SessionFile: Codable {
        var sessionId: String?
        var projectHash: String?
        var startTime: String?
        var lastUpdated: String?
        var directories: [String]?
        var messages: [MessageRecord]?
        var kind: String?
    }

    private struct MessageRecord: Codable {
        var id: String?
        var timestamp: String?
        var type: String?
        var tokens: TokensSummary?
        var model: String?
    }

    private struct TokensSummary: Codable {
        var input: Int?
        var output: Int?
        var cached: Int?
        var thoughts: Int?
        var tool: Int?
        var total: Int?
    }

    private let geminiHome: URL?
    private let environment: [String: String]
    private let cacheStore: UsageFileCacheStore?

    public var source: UsageSource { .gemini }

    public init(
        geminiHome: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        cacheStore: UsageFileCacheStore? = nil
    ) {
        self.geminiHome = geminiHome
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
        var events: [UsageEvent] = []
        var warnings: [String] = []
        var fileSignatures: [String: UsageFileSignature] = [:]
        let cachedEntries = (try? cacheStore?.load(source: .gemini))
            .flatMap { cache in
                cache.parserVersion == Self.parserVersion ? cache : nil
            }?.entries ?? [:]
        var nextEntries: [String: UsageCachedFileEntry] = [:]

        for file in UsageLoaderSupport.recursivelyEnumerateFiles(
            under: root,
            pathExtension: "json",
            cutoffDate: effectiveCutoff
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
                let fileEvents = try loadEvents(from: file.url, cutoffDate: effectiveCutoff)
                events.append(contentsOf: fileEvents)
                nextEntries[cacheKey] = UsageCachedFileEntry(
                    modificationTimeIntervalSince1970: file.modificationTime.timeIntervalSince1970,
                    fileSize: file.fileSize,
                    events: fileEvents
                )
            } catch {
                warnings.append("Gemini usage 解析失败: \(file.url.path)")
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
                source: .gemini
            )
        }
        return UsageLoadResult(events: events, warnings: warnings, fileSignatures: fileSignatures)
    }

    public func resolveRoots() -> (roots: [URL], warnings: [String], missingDirectories: [String]) {
        guard let root = resolvedRoot() else {
            return ([], [], [defaultRoot().path])
        }
        let tmpDir = root.appendingPathComponent("tmp", isDirectory: true)
        guard FileManager.default.fileExists(atPath: tmpDir.path) else {
            return ([], [], [tmpDir.path])
        }
        var chatDirs: [URL] = []
        if let enumerator = FileManager.default.enumerator(at: tmpDir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for case let url as URL in enumerator {
                guard url.lastPathComponent == "chats",
                      let values = try? url.resourceValues(forKeys: [.isDirectoryKey]),
                      values.isDirectory == true else { continue }
                chatDirs.append(url)
            }
        }
        return (chatDirs, [], [])
    }

    public func loadEventsFromFile(url: URL, cutoffDate: Date?) throws -> [UsageEvent] {
        try loadEvents(from: url, cutoffDate: cutoffDate)
    }

    private func resolvedRoot() -> URL? {
        if let geminiHome {
            return FileManager.default.fileExists(atPath: geminiHome.path) ? geminiHome : nil
        }
        let root = defaultRoot()
        return FileManager.default.fileExists(atPath: root.path) ? root : nil
    }

    private func defaultRoot() -> URL {
        if let raw = environment["GEMINI_CLI_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            return URL(fileURLWithPath: UsageLoaderSupport.expandedPath(raw), isDirectory: true)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".gemini", isDirectory: true)
    }

    private func loadEvents(from fileURL: URL, cutoffDate: Date?) throws -> [UsageEvent] {
        let data = try Data(contentsOf: fileURL)
        let session = try JSONDecoder().decode(SessionFile.self, from: data)
        let sessionID = session.sessionId ?? fileURL.deletingPathExtension().lastPathComponent
        let workingDirectory = session.directories?.first

        var events: [UsageEvent] = []
        guard let messages = session.messages else { return events }

        for message in messages {
            guard message.type == "gemini",
                  let tokens = message.tokens,
                  hasValidTokens(tokens) else { continue }

            let timestamp: Date
            if let ts = message.timestamp,
               let parsed = UsageLoaderSupport.parseDate(ts) {
                timestamp = parsed
            } else if let startTime = session.startTime,
                      let parsed = UsageLoaderSupport.parseDate(startTime) {
                timestamp = parsed
            } else {
                timestamp = Date()
            }

            if let cutoffDate, timestamp < cutoffDate { continue }

            let cacheReadTokens = tokens.cached ?? 0
            let inputTokens = max((tokens.input ?? 0) - cacheReadTokens, 0)
            let outputTokens = (tokens.output ?? 0) + (tokens.thoughts ?? 0)
            let cacheWriteTokens = 0
            let totalTokens = tokens.total ?? (inputTokens + outputTokens + cacheReadTokens)

            let modelName = message.model ?? "gemini-2.5-flash"

            let event = UsageEvent(
                id: "gemini:\(fileURL.path):\(message.id ?? UUID().uuidString)",
                source: .gemini,
                sessionID: sessionID,
                timestamp: timestamp,
                modelName: modelName,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                cacheReadTokens: cacheReadTokens,
                cacheWriteTokens: cacheWriteTokens,
                totalTokens: totalTokens,
                costUSD: nil,
                workingDirectory: workingDirectory
            )
            events.append(event)
        }

        return events
    }

    private func hasValidTokens(_ tokens: TokensSummary) -> Bool {
        (tokens.input ?? 0) > 0 ||
        (tokens.output ?? 0) > 0 ||
        (tokens.thoughts ?? 0) > 0 ||
        (tokens.cached ?? 0) > 0 ||
        (tokens.tool ?? 0) > 0
    }
}
