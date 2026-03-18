import Foundation

public struct UsageIncrementalLoadResult: Sendable {
    public var state: UsageIncrementalState
    public var isFullRefresh: Bool
    public var isCompleteFullRefresh: Bool  // 所有 sources 都是全量刷新
    public var sourcesRefreshed: [UsageSource]

    public init(state: UsageIncrementalState, isFullRefresh: Bool, isCompleteFullRefresh: Bool = false, sourcesRefreshed: [UsageSource]) {
        self.state = state
        self.isFullRefresh = isFullRefresh
        self.isCompleteFullRefresh = isCompleteFullRefresh
        self.sourcesRefreshed = sourcesRefreshed
    }
}

public struct UsageIncrementalLoader: Sendable {
    private let claudeLoader: ClaudeUsageLoader
    private let codexLoader: CodexUsageLoader
    private let opencodeLoader: OpenCodeUsageLoader
    private let geminiLoader: GeminiUsageLoader
    private let aggregator: UsageAggregator

    public init(
        claudeLoader: ClaudeUsageLoader? = nil,
        codexLoader: CodexUsageLoader? = nil,
        opencodeLoader: OpenCodeUsageLoader? = nil,
        geminiLoader: GeminiUsageLoader? = nil,
        aggregator: UsageAggregator = UsageAggregator()
    ) {
        self.claudeLoader = claudeLoader ?? ClaudeUsageLoader(cacheStore: UsageFileCacheStore())
        self.codexLoader = codexLoader ?? CodexUsageLoader(cacheStore: UsageFileCacheStore())
        self.opencodeLoader = opencodeLoader ?? OpenCodeUsageLoader(cacheStore: UsageFileCacheStore())
        self.geminiLoader = geminiLoader ?? GeminiUsageLoader(cacheStore: UsageFileCacheStore())
        self.aggregator = aggregator
    }

    public func refresh(
        currentState: UsageIncrementalState,
        sources: [UsageSource],
        fullRefreshInterval: UsageFullRefreshInterval,
        forceFullRefresh: Bool = false
    ) async throws -> UsageIncrementalLoadResult {
        let overallStart = Date()
        let now = Date()
        var sourcesToFullRefresh: [UsageSource] = []
        var sourcesToIncrementalRefresh: [UsageSource] = []

        for source in sources {
            let needsFull = forceFullRefresh 
                || currentState.needsFullRefresh(for: source, interval: fullRefreshInterval, now: now)
                || !currentState.hasData(for: source)
            if needsFull {
                sourcesToFullRefresh.append(source)
            } else {
                sourcesToIncrementalRefresh.append(source)
            }
        }

        print("[UsageIncremental] refresh: fullRefresh=\(sourcesToFullRefresh), incremental=\(sourcesToIncrementalRefresh)")

        let hasFullRefresh = !sourcesToFullRefresh.isEmpty
        var newState = currentState
        var allNewEvents: [UsageEvent] = []
        var allWarnings: [String] = []
        var allMissingDirectories: [String] = []
        var deletedPathsBySource: [UsageSource: Set<String>] = [:]

        for source in sourcesToFullRefresh {
            let start = Date()
            let result = try await loadFull(for: source)
            let duration = Date().timeIntervalSince(start)
            print("[UsageIncremental] loadFull(\(source)) took \(duration)s, events=\(result.events.count), files=\(result.fileSignatures.count)")
            allNewEvents.append(contentsOf: result.events)
            allWarnings.append(contentsOf: result.warnings)
            allMissingDirectories.append(contentsOf: result.missingDirectories)

            newState.setFileSignatures(result.fileSignatures, for: source)
            newState.updateSourceState(source, isFullRefresh: true, now: now, loadedFileCount: result.fileSignatures.count, duration: duration)
        }

        for source in sourcesToIncrementalRefresh {
            let start = Date()
            let result = try await loadIncremental(
                for: source,
                existingSignatures: currentState.fileSignatures(for: source)
            )
            let duration = Date().timeIntervalSince(start)
            print("[UsageIncremental] loadIncremental(\(source)) took \(duration)s, events=\(result.events.count), totalFiles=\(result.fileSignatures.count), deleted=\(result.deletedPaths.count)")
            allNewEvents.append(contentsOf: result.events)
            allWarnings.append(contentsOf: result.warnings)
            allMissingDirectories.append(contentsOf: result.missingDirectories)

            if !result.deletedPaths.isEmpty {
                deletedPathsBySource[source] = result.deletedPaths
            }

            newState.setFileSignatures(result.fileSignatures, for: source)
            newState.updateSourceState(source, isFullRefresh: false, now: now, loadedFileCount: result.fileSignatures.count, duration: duration)
        }

        let resolveStart = Date()
        let (resolvedNewEvents, _, _) = await aggregator.resolveEvents(
            from: [UsageLoadResult(events: allNewEvents, warnings: [], missingDirectories: [])],
            sources: sources
        )
        print("[UsageIncremental] resolveEvents took \(Date().timeIntervalSince(resolveStart))s for \(allNewEvents.count) events")

        let filterStart = Date()
        let fullRefreshSources = Set(sourcesToFullRefresh)
        let selectedSources = Set(sources)
        newState.resolvedEvents = currentState.resolvedEvents.filter { resolved in
            let event = resolved.event
            // 仅在全量刷新时过滤掉未选中的 sources 的数据
            // 增量刷新时保留，等下次全量刷新时再清除
            if hasFullRefresh {
                guard selectedSources.contains(event.source) else {
                    return false
                }
            }
            // 过滤掉全量刷新的 sources 的旧数据
            if fullRefreshSources.contains(event.source) {
                return false
            }
            if let deletedPaths = deletedPathsBySource[event.source], !deletedPaths.isEmpty {
                let eventID = event.id
                let prefix = event.source.rawValue + ":"
                guard eventID.hasPrefix(prefix) else { return true }
                let afterSource = String(eventID.dropFirst(prefix.count))
                if let colonIndex = afterSource.lastIndex(of: ":") {
                    let filePath = String(afterSource[..<colonIndex])
                    if deletedPaths.contains(filePath) {
                        return false
                    }
                }
            }
            return true
        }
        print("[UsageIncremental] filter existing events took \(Date().timeIntervalSince(filterStart))s, remaining=\(newState.resolvedEvents.count)")

        let mergeStart = Date()
        var existingEventIDs = Set(newState.resolvedEvents.map(\.event.id))
        for resolved in resolvedNewEvents {
            if !existingEventIDs.contains(resolved.event.id) {
                newState.resolvedEvents.append(resolved)
                existingEventIDs.insert(resolved.event.id)
            }
        }
        print("[UsageIncremental] merge events took \(Date().timeIntervalSince(mergeStart))s, total=\(newState.resolvedEvents.count)")

        newState.estimatedCostEventCount = newState.resolvedEvents.filter(\.costIsEstimated).count
        newState.unresolvedCostEventCount = newState.resolvedEvents.filter(\.costIsIncomplete).count
        newState.warnings = Array(Set(allWarnings)).sorted()
        newState.missingDirectories = Array(Set(allMissingDirectories)).sorted()

        // 重建日聚合缓存
        let aggregationStart = Date()
        newState.rebuildDailyAggregations()
        print("[UsageIncremental] rebuildDailyAggregations took \(Date().timeIntervalSince(aggregationStart))s, count=\(newState.dailyAggregations.count)")

        let totalDuration = Date().timeIntervalSince(overallStart)
        print("[UsageIncremental] refresh total took \(totalDuration)s")

        // 更新全局刷新时间（用于 UI 显示）
        // 只有所有选中的 sources 都进行了全量刷新，才更新全局全量刷新时间
        let isCompleteFullRefresh = hasFullRefresh && sourcesToIncrementalRefresh.isEmpty
        if isCompleteFullRefresh {
            newState.globalLastFullRefreshAt = now
            newState.globalLastFullRefreshDuration = totalDuration
        } else if !hasFullRefresh {
            // 只有所有 sources 都是增量刷新，才更新全局增量刷新时间
            newState.globalLastIncrementalRefreshAt = now
            newState.globalLastIncrementalRefreshDuration = totalDuration
        }
        // 部分全量部分增量时，不更新全局时间

        return UsageIncrementalLoadResult(
            state: newState,
            isFullRefresh: hasFullRefresh,
            isCompleteFullRefresh: isCompleteFullRefresh,
            sourcesRefreshed: sourcesToFullRefresh + sourcesToIncrementalRefresh
        )
    }

    public func fullRefresh(sources: [UsageSource]) async throws -> UsageIncrementalState {
        let state = UsageIncrementalState.empty
        let result = try await refresh(
            currentState: state,
            sources: sources,
            fullRefreshInterval: .sixHours,
            forceFullRefresh: true
        )
        return result.state
    }

    public func clearFileCaches(for sources: [UsageSource]) {
        let store = UsageFileCacheStore()
        for source in sources {
            store.delete(source: source)
        }
    }

    private func loadFull(for source: UsageSource) async throws -> (
        events: [UsageEvent],
        fileSignatures: [String: UsageFileSignature],
        warnings: [String],
        missingDirectories: [String]
    ) {
        let result = try await loader(for: source).load(request: UsageLoadRequest(cutoffDate: nil))
        return (result.events, result.fileSignatures, result.warnings, result.missingDirectories)
    }

    private func loadIncremental(
        for source: UsageSource,
        existingSignatures: [String: UsageFileSignature]
    ) async throws -> (
        events: [UsageEvent],
        fileSignatures: [String: UsageFileSignature],
        deletedPaths: Set<String>,
        warnings: [String],
        missingDirectories: [String]
    ) {
        // OpenCode uses SQLite database, handle separately
        if source == .opencode {
            return try await loadIncrementalOpenCode(existingSignatures: existingSignatures)
        }
        // Gemini uses JSON session files, handle separately
        if source == .gemini {
            return try await loadIncrementalGemini(existingSignatures: existingSignatures)
        }

        let step1Start = Date()
        let roots: [URL]
        let missingDirectories: [String]
        switch source {
        case .claudeCode:
            let resolved = claudeLoader.resolveRoots()
            roots = resolved.roots
            missingDirectories = resolved.missingDirectories
        case .codex:
            let resolved = codexLoader.resolveRoots()
            roots = resolved.roots
            missingDirectories = resolved.missingDirectories
        default:
            roots = []
            missingDirectories = []
        }

        let pathExtension = "jsonl"
        var newSignatures: [String: UsageFileSignature] = [:]
        var changedFiles: [(url: URL, signature: UsageFileSignature)] = []
        var deletedPaths: Set<String> = Set(existingSignatures.keys)

        for root in roots {
            for file in UsageLoaderSupport.recursivelyEnumerateFiles(
                under: root,
                pathExtension: pathExtension,
                cutoffDate: nil
            ) {
                let path = file.url.path
                let signature = UsageFileSignature(
                    modificationTime: file.modificationTime,
                    fileSize: file.fileSize
                )
                newSignatures[path] = signature
                deletedPaths.remove(path)

                if let existing = existingSignatures[path], existing == signature {
                    continue
                }
                changedFiles.append((file.url, signature))
            }
        }
        print("[UsageIncremental] loadIncremental(\(source)): enumerate files took \(Date().timeIntervalSince(step1Start))s, total=\(newSignatures.count), changed=\(changedFiles.count), deleted=\(deletedPaths.count)")

        if changedFiles.isEmpty && deletedPaths.isEmpty && newSignatures.count == existingSignatures.count {
            print("[UsageIncremental] loadIncremental(\(source)): no changes, returning early")
            return ([], existingSignatures, [], [], [])
        }

        let step2Start = Date()
        var events: [UsageEvent] = []
        var warnings: [String] = []

        for (url, _) in changedFiles {
            do {
                let fileEvents: [UsageEvent]
                switch source {
                case .claudeCode:
                    fileEvents = try claudeLoader.loadEventsFromFile(url: url, cutoffDate: nil)
                case .codex:
                    fileEvents = try codexLoader.loadEventsFromFile(url: url, cutoffDate: nil)
                default:
                    fileEvents = []
                }
                events.append(contentsOf: fileEvents)
            } catch {
                warnings.append("\(source.displayName) 解析失败: \(url.path)")
            }
        }
        print("[UsageIncremental] loadIncremental(\(source)): load changed files took \(Date().timeIntervalSince(step2Start))s, events=\(events.count)")

        return (events, newSignatures, deletedPaths, warnings, missingDirectories)
    }

    private func loadIncrementalOpenCode(
        existingSignatures: [String: UsageFileSignature]
    ) async throws -> (
        events: [UsageEvent],
        fileSignatures: [String: UsageFileSignature],
        deletedPaths: Set<String>,
        warnings: [String],
        missingDirectories: [String]
    ) {
        let result = try await opencodeLoader.load(request: UsageLoadRequest(cutoffDate: nil))

        if result.missingDirectories.count > 0 {
            return ([], [:], Set(existingSignatures.keys), result.warnings, result.missingDirectories)
        }

        let newSignatures = result.fileSignatures
        let cacheKey = newSignatures.keys.first ?? "opencode:db"

        if let existing = existingSignatures[cacheKey],
           let newSig = newSignatures[cacheKey],
           existing == newSig {
            print("[UsageIncremental] loadIncremental(opencode): database unchanged, returning early")
            return ([], existingSignatures, [], [], [])
        }

        print("[UsageIncremental] loadIncremental(opencode): database changed, loaded \(result.events.count) events")
        return (result.events, newSignatures, Set(existingSignatures.keys).subtracting(newSignatures.keys), result.warnings, result.missingDirectories)
    }

    private func loadIncrementalGemini(
        existingSignatures: [String: UsageFileSignature]
    ) async throws -> (
        events: [UsageEvent],
        fileSignatures: [String: UsageFileSignature],
        deletedPaths: Set<String>,
        warnings: [String],
        missingDirectories: [String]
    ) {
        let resolved = geminiLoader.resolveRoots()
        let roots = resolved.roots
        let missingDirectories = resolved.missingDirectories

        var newSignatures: [String: UsageFileSignature] = [:]
        var changedFiles: [(url: URL, signature: UsageFileSignature)] = []
        var deletedPaths: Set<String> = Set(existingSignatures.keys)

        for root in roots {
            for file in UsageLoaderSupport.recursivelyEnumerateFiles(
                under: root,
                pathExtension: "json",
                cutoffDate: nil
            ) {
                let path = file.url.path
                let signature = UsageFileSignature(
                    modificationTime: file.modificationTime,
                    fileSize: file.fileSize
                )
                newSignatures[path] = signature
                deletedPaths.remove(path)

                if let existing = existingSignatures[path], existing == signature {
                    continue
                }
                changedFiles.append((file.url, signature))
            }
        }

        if changedFiles.isEmpty && deletedPaths.isEmpty && newSignatures.count == existingSignatures.count {
            return ([], existingSignatures, [], [], [])
        }

        var events: [UsageEvent] = []
        var warnings: [String] = []

        for (url, _) in changedFiles {
            do {
                let fileEvents = try geminiLoader.loadEventsFromFile(url: url, cutoffDate: nil)
                events.append(contentsOf: fileEvents)
            } catch {
                warnings.append("Gemini 解析失败: \(url.path)")
            }
        }

        return (events, newSignatures, deletedPaths, warnings, missingDirectories)
    }

    private func loader(for source: UsageSource) -> any UsageLoader {
        switch source {
        case .claudeCode:
            return claudeLoader
        case .codex:
            return codexLoader
        case .opencode:
            return opencodeLoader
        case .gemini:
            return geminiLoader
        }
    }
}