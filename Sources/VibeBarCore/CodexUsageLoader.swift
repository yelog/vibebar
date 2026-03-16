import Foundation

public struct CodexUsageLoader: UsageLoader {
    private struct RawUsage {
        var inputTokens: Int
        var cachedInputTokens: Int
        var outputTokens: Int
        var reasoningOutputTokens: Int
        var totalTokens: Int
    }

    private let sessionsRoot: URL?
    private let environment: [String: String]
    private let cacheStore: UsageFileCacheStore?

    public var source: UsageSource { .codex }

    public init(
        baseDirectory: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        cacheStore: UsageFileCacheStore? = nil
    ) {
        self.sessionsRoot = baseDirectory
        self.environment = environment
        self.cacheStore = cacheStore
    }

    public func load(request: UsageLoadRequest = UsageLoadRequest(cutoffDate: nil)) async throws -> UsageLoadResult {
        let root = resolvedRoot()
        guard let root else {
            let missingPath = defaultSessionsRoot().path
            return UsageLoadResult(missingDirectories: [missingPath])
        }

        let effectiveCutoff = request.effectiveCutoffDate()

        var events: [UsageEvent] = []
        var warnings: [String] = []
        var fileSignatures: [String: UsageFileSignature] = [:]
        let cachedEntries = (try? cacheStore?.load(source: .codex))?.entries ?? [:]
        var nextEntries: [String: UsageCachedFileEntry] = [:]

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
                let fileEvents = try loadEvents(from: file.url, root: root, cutoffDate: effectiveCutoff)
                events.append(contentsOf: fileEvents)
                nextEntries[cacheKey] = UsageCachedFileEntry(
                    modificationTimeIntervalSince1970: file.modificationTime.timeIntervalSince1970,
                    fileSize: file.fileSize,
                    events: fileEvents
                )
            } catch {
                warnings.append("Codex usage 解析失败: \(file.url.path)")
                if let cached = cachedEntries[cacheKey] {
                    events.append(contentsOf: cached.events)
                    nextEntries[cacheKey] = cached
                }
            }
        }

        if let cacheStore {
            try? cacheStore.write(
                UsageSourceFileCache(entries: nextEntries),
                source: .codex
            )
        }
        return UsageLoadResult(events: events, warnings: warnings, fileSignatures: fileSignatures)
    }

    public func resolveRoots() -> (roots: [URL], warnings: [String], missingDirectories: [String]) {
        if let sessionsRoot {
            if FileManager.default.fileExists(atPath: sessionsRoot.path) {
                return ([sessionsRoot], [], [])
            } else {
                return ([], [], [sessionsRoot.path])
            }
        }
        let root = defaultSessionsRoot()
        if FileManager.default.fileExists(atPath: root.path) {
            return ([root], [], [])
        } else {
            return ([], [], [root.path])
        }
    }

    public func loadEventsFromFile(url: URL, cutoffDate: Date?) throws -> [UsageEvent] {
        let root = resolvedRoot() ?? defaultSessionsRoot()
        return try loadEvents(from: url, root: root, cutoffDate: cutoffDate)
    }

    private func resolvedRoot() -> URL? {
        if let sessionsRoot {
            return FileManager.default.fileExists(atPath: sessionsRoot.path) ? sessionsRoot : nil
        }
        let root = defaultSessionsRoot()
        return FileManager.default.fileExists(atPath: root.path) ? root : nil
    }

    private func defaultSessionsRoot() -> URL {
        if let raw = environment["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            return URL(fileURLWithPath: UsageLoaderSupport.expandedPath(raw), isDirectory: true)
                .appendingPathComponent("sessions", isDirectory: true)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".codex/sessions", isDirectory: true)
    }

    public func loadEvents(from fileURL: URL, root: URL, cutoffDate: Date?) throws -> [UsageEvent] {
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let lines = content.split(whereSeparator: \.isNewline)
        let relativePath = fileURL.path.replacingOccurrences(of: root.path + "/", with: "")
        let sessionID = relativePath.replacingOccurrences(of: ".jsonl", with: "")

        var events: [UsageEvent] = []
        var previousTotals: RawUsage?
        var currentModel: String?
        var currentModelIsFallback = false
        var foundRecentEvent = false

        for (lineIndex, line) in lines.enumerated() {
            let rawLine = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawLine.isEmpty, let data = rawLine.data(using: .utf8) else { continue }
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            guard let entryType = object["type"] as? String else { continue }

            if entryType == "turn_context" {
                if let contextModel = extractModel(from: object["payload"]) {
                    currentModel = contextModel
                    currentModelIsFallback = false
                }
                continue
            }

            guard entryType == "event_msg",
                  let payload = object["payload"] as? [String: Any],
                  let payloadType = payload["type"] as? String,
                  payloadType == "token_count",
                  let timestampString = object["timestamp"] as? String,
                  let timestamp = UsageLoaderSupport.parseDate(timestampString) else {
                continue
            }

            // 如果指定了cutoffDate，进行时间过滤
            if let cutoffDate {
                if timestamp >= cutoffDate {
                    foundRecentEvent = true
                } else if foundRecentEvent {
                    // 已经找到过有效事件，现在又遇到旧数据，假设数据按时间排序，提前终止
                    break
                } else {
                    // 还没找到有效事件，继续扫描
                    continue
                }
            }

            let info = payload["info"] as? [String: Any]
            let lastUsage = normalizeRawUsage(info?["last_token_usage"])
            let totalUsage = normalizeRawUsage(info?["total_token_usage"])

            var deltaUsage = lastUsage
            if deltaUsage == nil, let totalUsage {
                deltaUsage = subtract(totalUsage, previousTotals)
            }
            if let totalUsage {
                previousTotals = totalUsage
            }
            guard let deltaUsage else { continue }

            if deltaUsage.inputTokens == 0 &&
                deltaUsage.cachedInputTokens == 0 &&
                deltaUsage.outputTokens == 0 &&
                deltaUsage.reasoningOutputTokens == 0 {
                continue
            }

            let extractedModel = extractModel(from: payload) ?? extractModel(from: info)
            if let extractedModel {
                currentModel = extractedModel
                currentModelIsFallback = false
            }

            var isFallbackModel = false
            let modelName: String
            if let extractedModel {
                modelName = extractedModel
            } else if let currentModel {
                modelName = currentModel
                isFallbackModel = currentModelIsFallback
            } else {
                modelName = "gpt-5"
                currentModel = modelName
                currentModelIsFallback = true
                isFallbackModel = true
            }

            let event = UsageEvent(
                id: "codex:\(fileURL.path):\(lineIndex)",
                source: .codex,
                sessionID: sessionID,
                timestamp: timestamp,
                modelName: modelName,
                inputTokens: deltaUsage.inputTokens,
                outputTokens: deltaUsage.outputTokens,
                cacheReadTokens: deltaUsage.cachedInputTokens,
                cacheWriteTokens: 0,
                totalTokens: max(deltaUsage.totalTokens, deltaUsage.inputTokens + deltaUsage.outputTokens + deltaUsage.cachedInputTokens),
                costUSD: nil,
                costIsIncomplete: isFallbackModel
            )
            events.append(event)
        }

        return events
    }

    private func normalizeRawUsage(_ value: Any?) -> RawUsage? {
        guard let record = value as? [String: Any] else { return nil }
        let inputTokens = Self.intValue(record["input_tokens"])
        let cachedInputTokens = Self.intValue(record["cached_input_tokens"] ?? record["cache_read_input_tokens"])
        let outputTokens = Self.intValue(record["output_tokens"])
        let reasoningOutputTokens = Self.intValue(record["reasoning_output_tokens"])
        let totalTokens = Self.intValue(record["total_tokens"])
        return RawUsage(
            inputTokens: inputTokens,
            cachedInputTokens: cachedInputTokens,
            outputTokens: outputTokens,
            reasoningOutputTokens: reasoningOutputTokens,
            totalTokens: totalTokens > 0 ? totalTokens : inputTokens + outputTokens
        )
    }

    private func subtract(_ current: RawUsage, _ previous: RawUsage?) -> RawUsage {
        RawUsage(
            inputTokens: max(current.inputTokens - (previous?.inputTokens ?? 0), 0),
            cachedInputTokens: max(current.cachedInputTokens - (previous?.cachedInputTokens ?? 0), 0),
            outputTokens: max(current.outputTokens - (previous?.outputTokens ?? 0), 0),
            reasoningOutputTokens: max(current.reasoningOutputTokens - (previous?.reasoningOutputTokens ?? 0), 0),
            totalTokens: max(current.totalTokens - (previous?.totalTokens ?? 0), 0)
        )
    }

    private func extractModel(from value: Any?) -> String? {
        guard let value else { return nil }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        guard let record = value as? [String: Any] else { return nil }

        for key in ["model", "model_name"] {
            if let model = extractModel(from: record[key]) {
                return model
            }
        }

        if let info = record["info"] as? [String: Any], let model = extractModel(from: info) {
            return model
        }

        if let metadata = record["metadata"] as? [String: Any],
           let output = metadata["output"] as? [String: Any],
           let model = extractModel(from: output["model"]) {
            return model
        }

        if let output = record["output"] as? [String: Any],
           let model = extractModel(from: output["model"]) {
            return model
        }

        return nil
    }

    private static func intValue(_ value: Any?) -> Int {
        if let value = value as? Int { return max(0, value) }
        if let value = value as? NSNumber { return max(0, value.intValue) }
        if let value = value as? String, let parsed = Int(value) { return max(0, parsed) }
        return 0
    }
}
