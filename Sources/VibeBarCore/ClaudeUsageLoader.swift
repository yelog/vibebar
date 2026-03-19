import Foundation

public struct ClaudeUsageLoader: UsageLoader {
    public static let parserVersion = 1

    private let searchRoots: [URL]?
    private let environment: [String: String]
    private let cacheStore: UsageFileCacheStore?

    public var source: UsageSource { .claudeCode }

    public init(
        searchRoots: [URL]? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        cacheStore: UsageFileCacheStore? = nil
    ) {
        self.searchRoots = searchRoots
        self.environment = environment
        self.cacheStore = cacheStore
    }

    public func load(request: UsageLoadRequest = UsageLoadRequest(cutoffDate: nil)) async throws -> UsageLoadResult {
        let resolved = resolveRoots()
        var events: [UsageEvent] = []
        var warnings: [String] = resolved.warnings
        var fileSignatures: [String: UsageFileSignature] = [:]
        let cachedEntries = (try? cacheStore?.load(source: .claudeCode))
            .flatMap { cache in
                cache.parserVersion == Self.parserVersion ? cache : nil
            }?.entries ?? [:]
        var nextEntries: [String: UsageCachedFileEntry] = [:]

        let effectiveCutoff = request.effectiveCutoffDate()

        for root in resolved.roots {
            for file in UsageLoaderSupport.recursivelyEnumerateFiles(
                under: root,
                pathExtension: "jsonl",
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
                UsageSourceFileCache(
                    parserVersion: Self.parserVersion,
                    entries: nextEntries
                ),
                source: .claudeCode
            )
        }
        return UsageLoadResult(
            events: events,
            warnings: warnings,
            missingDirectories: resolved.missingDirectories,
            fileSignatures: fileSignatures
        )
    }

    public func resolveRoots() -> (roots: [URL], warnings: [String], missingDirectories: [String]) {
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

    public func loadEventsFromFile(url: URL, cutoffDate: Date?) throws -> [UsageEvent] {
        try loadEvents(from: url, cutoffDate: cutoffDate)
    }

    public func loadEvents(from fileURL: URL, cutoffDate: Date?) throws -> [UsageEvent] {
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let lines = content.split(whereSeparator: \.isNewline)
        let fallbackSessionID = fileURL.deletingPathExtension().lastPathComponent
        var events: [UsageEvent] = []
        var foundRecentEvent = false
        var lastKnownWorkingDirectory: String?

        for (lineIndex, line) in lines.enumerated() {
            let rawLine = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawLine.isEmpty, let data = rawLine.data(using: .utf8) else { continue }
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            guard let timestampString = object["timestamp"] as? String,
                  let timestamp = UsageLoaderSupport.parseDate(timestampString) else {
                continue
            }

            // 优先从顶层 cwd 字段获取工作目录
            if let cwd = object["cwd"] as? String, !cwd.isEmpty {
                lastKnownWorkingDirectory = cwd
            }

            // 如果指定了cutoffDate，进行时间过滤
            if let cutoffDate {
                if timestamp >= cutoffDate {
                    foundRecentEvent = true
                } else if foundRecentEvent {
                    // 已经找到过有效事件，现在又遇到旧数据
                    // 假设数据是按时间排序的，可以提前终止
                    break
                } else {
                    // 还没找到有效事件，继续扫描
                    continue
                }
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

            // 使用最后已知的工作目录，或从路径解析
            let workingDirectory = lastKnownWorkingDirectory ?? extractWorkingDirectory(from: fileURL)

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
                costUSD: costUSD,
                workingDirectory: workingDirectory
            )
            events.append(event)
        }

        return events
    }

    private func extractWorkingDirectory(from fileURL: URL) -> String? {
        let path = fileURL.path
        guard let projectsRange = path.range(of: "/projects/") else { return nil }
        let afterProjects = path[projectsRange.upperBound...]
        guard let nextSlash = afterProjects.firstIndex(of: "/") else { return nil }
        let encodedPath = String(afterProjects[..<nextSlash])

        guard encodedPath.hasPrefix("-") else { return nil }
        let withoutPrefix = String(encodedPath.dropFirst())

        // 将编码的路径转换回完整路径
        // 例如: "Users-yelog-workspace-swift-VibeBar" -> "/Users/yelog/workspace/swift/VibeBar"
        let components = withoutPrefix.split(separator: "-")
        guard !components.isEmpty else { return nil }

        return "/" + components.joined(separator: "/")
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
