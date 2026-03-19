import Foundation

public struct UsageIncrementalLoadResult: Sendable {
    public var state: UsageIncrementalState
    public var isFullRefresh: Bool
    public var isCompleteFullRefresh: Bool
    public var sourcesRefreshed: [UsageSource]

    public init(state: UsageIncrementalState, isFullRefresh: Bool, isCompleteFullRefresh: Bool = false, sourcesRefreshed: [UsageSource]) {
        self.state = state
        self.isFullRefresh = isFullRefresh
        self.isCompleteFullRefresh = isCompleteFullRefresh
        self.sourcesRefreshed = sourcesRefreshed
    }
}

private enum SourceLoadResult: Sendable {
    case full(
        source: UsageSource,
        events: [UsageEvent],
        signatures: [String: UsageFileSignature],
        warnings: [String],
        missingDirectories: [String],
        duration: TimeInterval,
        fileCount: Int
    )
    case incremental(
        source: UsageSource,
        events: [UsageEvent],
        signatures: [String: UsageFileSignature],
        deletedPaths: Set<String>,
        warnings: [String],
        missingDirectories: [String],
        duration: TimeInterval,
        fileCount: Int
    )
    case error(source: UsageSource, isFullRefresh: Bool, error: Error)
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
                || !currentState.hasMatchingParserVersion(for: source, version: parserVersion(for: source))
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
        var sourcesWithErrors: [UsageSource] = []

        let parallelStart = Date()
        let loadResults = await withTaskGroup(of: SourceLoadResult.self) { group in
            for source in sourcesToFullRefresh {
                group.addTask { [self] in
                    let start = Date()
                    do {
                        let result = try await self.loadFull(for: source, currentState: currentState)
                        let duration = Date().timeIntervalSince(start)
                        return .full(
                            source: source,
                            events: result.events,
                            signatures: result.fileSignatures,
                            warnings: result.warnings,
                            missingDirectories: result.missingDirectories,
                            duration: duration,
                            fileCount: result.fileSignatures.count
                        )
                    } catch {
                        return .error(source: source, isFullRefresh: true, error: error)
                    }
                }
            }

            for source in sourcesToIncrementalRefresh {
                let existingSignatures = currentState.fileSignatures(for: source)
                group.addTask { [self] in
                    let start = Date()
                    do {
                        let result = try await self.loadIncremental(for: source, existingSignatures: existingSignatures)
                        let duration = Date().timeIntervalSince(start)
                        return .incremental(
                            source: source,
                            events: result.events,
                            signatures: result.fileSignatures,
                            deletedPaths: result.deletedPaths,
                            warnings: result.warnings,
                            missingDirectories: result.missingDirectories,
                            duration: duration,
                            fileCount: result.fileSignatures.count
                        )
                    } catch {
                        return .error(source: source, isFullRefresh: false, error: error)
                    }
                }
            }

            var results: [SourceLoadResult] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
        print("[UsageIncremental] parallel load took \(Date().timeIntervalSince(parallelStart))s for \(loadResults.count) sources")

        for result in loadResults {
            switch result {
            case let .full(source, events, signatures, warnings, missingDirectories, duration, fileCount):
                print("[UsageIncremental] loadFull(\(source)) took \(duration)s, events=\(events.count), files=\(fileCount)")
                allNewEvents.append(contentsOf: events)
                allWarnings.append(contentsOf: warnings)
                allMissingDirectories.append(contentsOf: missingDirectories)
                newState.setFileSignatures(signatures, for: source)
                newState.setParserVersion(parserVersion(for: source), for: source)
                newState.updateSourceState(source, isFullRefresh: true, now: now, loadedFileCount: fileCount, duration: duration)

            case let .incremental(source, events, signatures, deletedPaths, warnings, missingDirectories, duration, fileCount):
                print("[UsageIncremental] loadIncremental(\(source)) took \(duration)s, events=\(events.count), totalFiles=\(fileCount), deleted=\(deletedPaths.count)")
                allNewEvents.append(contentsOf: events)
                allWarnings.append(contentsOf: warnings)
                allMissingDirectories.append(contentsOf: missingDirectories)
                if !deletedPaths.isEmpty {
                    deletedPathsBySource[source] = deletedPaths
                }
                newState.setFileSignatures(signatures, for: source)
                newState.setParserVersion(parserVersion(for: source), for: source)
                newState.updateSourceState(source, isFullRefresh: false, now: now, loadedFileCount: fileCount, duration: duration)

            case let .error(source, isFullRefresh, error):
                let refreshType = isFullRefresh ? "full" : "incremental"
                print("[UsageIncremental] load\(refreshType)(\(source)) failed: \(error.localizedDescription)")
                allWarnings.append("\(source.displayName) 加载失败: \(error.localizedDescription)")
                sourcesWithErrors.append(source)
            }
        }

        let resolveStart = Date()
        let (resolvedNewEvents, _, _) = await aggregator.resolveEvents(
            from: [UsageLoadResult(events: allNewEvents, warnings: [], missingDirectories: [])],
            sources: sources
        )
        print("[UsageIncremental] resolveEvents took \(Date().timeIntervalSince(resolveStart))s for \(allNewEvents.count) events")

        let filterStart = Date()
        let sourcesWithErrorsSet = Set(sourcesWithErrors)
        let fullRefreshSources = Set(sourcesToFullRefresh).subtracting(sourcesWithErrorsSet)
        let selectedSources = Set(sources)
        newState.resolvedEvents = currentState.resolvedEvents.filter { resolved in
            let event = resolved.event
            if hasFullRefresh {
                guard selectedSources.contains(event.source) else {
                    return false
                }
            }
            if fullRefreshSources.contains(event.source) {
                return false
            }
            if let deletedPaths = deletedPathsBySource[event.source], !deletedPaths.isEmpty {
                if let filePath = UsageLoaderSupport.trackedFilePath(for: event),
                   deletedPaths.contains(filePath) {
                    return false
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

        let isCompleteFullRefresh = hasFullRefresh && sourcesToIncrementalRefresh.isEmpty && sourcesWithErrors.isEmpty
        if isCompleteFullRefresh {
            newState.globalLastFullRefreshAt = now
            newState.globalLastFullRefreshDuration = totalDuration
        } else if !hasFullRefresh && sourcesWithErrors.isEmpty {
            newState.globalLastIncrementalRefreshAt = now
            newState.globalLastIncrementalRefreshDuration = totalDuration
        }

        let successfulSources = (sourcesToFullRefresh + sourcesToIncrementalRefresh).filter { !sourcesWithErrorsSet.contains($0) }
        return UsageIncrementalLoadResult(
            state: newState,
            isFullRefresh: hasFullRefresh,
            isCompleteFullRefresh: isCompleteFullRefresh,
            sourcesRefreshed: successfulSources
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

    private func loadFull(
        for source: UsageSource,
        currentState: UsageIncrementalState
    ) async throws -> (
        events: [UsageEvent],
        fileSignatures: [String: UsageFileSignature],
        warnings: [String],
        missingDirectories: [String]
    ) {
        if canReuseCurrentStateForFullRefresh(source: source, currentState: currentState) {
            switch source {
            case .claudeCode, .codex, .gemini:
                return try await rebuildFullFromCurrentState(for: source, currentState: currentState)
            case .opencode:
                break
            }
        }

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

    private func canReuseCurrentStateForFullRefresh(
        source: UsageSource,
        currentState: UsageIncrementalState
    ) -> Bool {
        currentState.hasData(for: source)
            && currentState.hasMatchingParserVersion(for: source, version: parserVersion(for: source))
    }

    private func rebuildFullFromCurrentState(
        for source: UsageSource,
        currentState: UsageIncrementalState
    ) async throws -> (
        events: [UsageEvent],
        fileSignatures: [String: UsageFileSignature],
        warnings: [String],
        missingDirectories: [String]
    ) {
        guard let context = enumerationContext(for: source) else {
            let result = try await loader(for: source).load(request: UsageLoadRequest(cutoffDate: nil))
            return (result.events, result.fileSignatures, result.warnings, result.missingDirectories)
        }

        let existingSignatures = currentState.fileSignatures(for: source)
        var newSignatures: [String: UsageFileSignature] = [:]
        var changedFiles: [URL] = []

        for root in context.roots {
            for file in UsageLoaderSupport.recursivelyEnumerateFiles(
                under: root,
                pathExtension: context.pathExtension,
                cutoffDate: nil
            ) {
                let signature = UsageFileSignature(
                    modificationTime: file.modificationTime,
                    fileSize: file.fileSize
                )
                newSignatures[file.url.path] = signature
                if let existing = existingSignatures[file.url.path], existing == signature {
                    continue
                }
                changedFiles.append(file.url)
            }
        }

        var events = currentState.resolvedEvents.compactMap { resolved -> UsageEvent? in
            guard resolved.event.source == source,
                  let filePath = UsageLoaderSupport.trackedFilePath(for: resolved.event),
                  let newSignature = newSignatures[filePath],
                  let existingSignature = existingSignatures[filePath],
                  existingSignature == newSignature else {
                return nil
            }
            return resolved.event
        }
        var warnings: [String] = []

        for url in changedFiles {
            do {
                events.append(contentsOf: try loadEventsFromFile(for: source, url: url))
            } catch {
                warnings.append("\(source.displayName) 解析失败: \(url.path)")
            }
        }

        return (events, newSignatures, warnings, context.missingDirectories)
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

    private func parserVersion(for source: UsageSource) -> Int {
        switch source {
        case .claudeCode:
            return ClaudeUsageLoader.parserVersion
        case .codex:
            return CodexUsageLoader.parserVersion
        case .opencode:
            return OpenCodeUsageLoader.parserVersion
        case .gemini:
            return GeminiUsageLoader.parserVersion
        }
    }

    private func enumerationContext(for source: UsageSource) -> (roots: [URL], missingDirectories: [String], pathExtension: String)? {
        switch source {
        case .claudeCode:
            let resolved = claudeLoader.resolveRoots()
            return (resolved.roots, resolved.missingDirectories, "jsonl")
        case .codex:
            let resolved = codexLoader.resolveRoots()
            return (resolved.roots, resolved.missingDirectories, "jsonl")
        case .gemini:
            let resolved = geminiLoader.resolveRoots()
            return (resolved.roots, resolved.missingDirectories, "json")
        case .opencode:
            return nil
        }
    }

    private func loadEventsFromFile(for source: UsageSource, url: URL) throws -> [UsageEvent] {
        switch source {
        case .claudeCode:
            return try claudeLoader.loadEventsFromFile(url: url, cutoffDate: nil)
        case .codex:
            return try codexLoader.loadEventsFromFile(url: url, cutoffDate: nil)
        case .gemini:
            return try geminiLoader.loadEventsFromFile(url: url, cutoffDate: nil)
        case .opencode:
            return try opencodeLoader.loadEventsFromFile(url: url, cutoffDate: nil)
        }
    }
}
