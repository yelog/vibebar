import Foundation

public struct ClaudeUsageLoader {
    private let searchRoots: [URL]?
    private let environment: [String: String]
    private let cacheStore: UsageFileCacheStore?

    public init(
        searchRoots: [URL]? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        cacheStore: UsageFileCacheStore? = nil
    ) {
        self.searchRoots = searchRoots
        self.environment = environment
        self.cacheStore = cacheStore
    }

    public func load() async throws -> UsageLoadResult {
        let resolved = resolveRoots()
        var events: [UsageEvent] = []
        var warnings: [String] = resolved.warnings
        let cachedEntries = (try? cacheStore?.load(source: .claudeCode))?.entries ?? [:]
        var nextEntries: [String: UsageCachedFileEntry] = [:]

        for root in resolved.roots {
            for file in UsageLoaderSupport.recursivelyEnumerateFiles(under: root, pathExtension: "jsonl") {
                let cacheKey = file.url.path
                if let cached = cachedEntries[cacheKey],
                   cached.fileSize == file.fileSize,
                   cached.modificationTimeIntervalSince1970 == file.modificationTime.timeIntervalSince1970 {
                    events.append(contentsOf: cached.events)
                    nextEntries[cacheKey] = cached
                    continue
                }

                do {
                    let fileEvents = try loadEvents(from: file.url)
                    events.append(contentsOf: fileEvents)
                    nextEntries[cacheKey] = UsageCachedFileEntry(
                        modificationTimeIntervalSince1970: file.modificationTime.timeIntervalSince1970,
                        fileSize: file.fileSize,
                        events: fileEvents
                    )
                } catch {
                    warnings.append("Claude usage 解析失败: \(file.url.path)")
                    if let cached = cachedEntries[cacheKey] {
                        events.append(contentsOf: cached.events)
                        nextEntries[cacheKey] = cached
                    }
                }
            }
        }

        if let cacheStore {
            try? cacheStore.write(
                UsageSourceFileCache(entries: nextEntries),
                source: .claudeCode
            )
        }
        return UsageLoadResult(
            events: events,
            warnings: warnings,
            missingDirectories: resolved.missingDirectories
        )
    }

    private func resolveRoots() -> (roots: [URL], warnings: [String], missingDirectories: [String]) {
        if let searchRoots {
            let existingRoots = searchRoots.filter {
                FileManager.default.fileExists(atPath: $0.path)
            }
            let missing = searchRoots.filter { !FileManager.default.fileExists(atPath: $0.path) }.map(\.path)
            return (existingRoots, [], missing)
        }

        let fileManager = FileManager.default
        let configuredPaths = (environment["CLAUDE_CONFIG_DIR"] ?? "")
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let candidateConfigRoots: [String]
        if configuredPaths.isEmpty {
            let home = fileManager.homeDirectoryForCurrentUser.path
            candidateConfigRoots = [
                home + "/.config/claude",
                home + "/.claude",
            ]
        } else {
            candidateConfigRoots = configuredPaths
        }

        var roots: [URL] = []
        var missingDirectories: [String] = []
        for rawPath in candidateConfigRoots {
            let configRoot = URL(fileURLWithPath: UsageLoaderSupport.expandedPath(rawPath), isDirectory: true)
            let projectsRoot = configRoot.appendingPathComponent("projects", isDirectory: true)
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: projectsRoot.path, isDirectory: &isDirectory), isDirectory.boolValue {
                roots.append(projectsRoot)
            } else {
                missingDirectories.append(projectsRoot.path)
            }
        }

        return (roots, [], missingDirectories)
    }

    private func loadEvents(from fileURL: URL) throws -> [UsageEvent] {
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let lines = content.split(whereSeparator: \.isNewline)
        let fallbackSessionID = fileURL.deletingPathExtension().lastPathComponent
        var events: [UsageEvent] = []

        for (lineIndex, line) in lines.enumerated() {
            let rawLine = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawLine.isEmpty, let data = rawLine.data(using: .utf8) else { continue }
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            guard let timestampString = object["timestamp"] as? String,
                  let timestamp = UsageLoaderSupport.parseDate(timestampString) else {
                continue
            }
            guard let message = object["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any] else {
                continue
            }

            let inputTokens = Self.intValue(usage["input_tokens"])
            let outputTokens = Self.intValue(usage["output_tokens"])
            let cacheWriteTokens = Self.intValue(usage["cache_creation_input_tokens"])
            let cacheReadTokens = Self.intValue(usage["cache_read_input_tokens"])
            if inputTokens == 0 && outputTokens == 0 && cacheWriteTokens == 0 && cacheReadTokens == 0 {
                continue
            }

            let sessionID = (object["sessionId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let modelName = ((message["model"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap {
                $0.isEmpty ? nil : $0
            } ?? "unknown"
            let costUSD = Self.doubleValue(object["costUSD"])

            let event = UsageEvent(
                id: "claude:\(fileURL.path):\(lineIndex)",
                source: .claudeCode,
                sessionID: sessionID?.isEmpty == false ? sessionID! : fallbackSessionID,
                timestamp: timestamp,
                modelName: modelName,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                cacheReadTokens: cacheReadTokens,
                cacheWriteTokens: cacheWriteTokens,
                costUSD: costUSD
            )
            events.append(event)
        }

        return events
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
}
