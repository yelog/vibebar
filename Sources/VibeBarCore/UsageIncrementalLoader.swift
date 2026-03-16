import Foundation

public struct UsageIncrementalLoadResult: Sendable {
    public var state: UsageIncrementalState
    public var isFullRefresh: Bool
    public var sourcesRefreshed: [UsageSource]

    public init(state: UsageIncrementalState, isFullRefresh: Bool, sourcesRefreshed: [UsageSource]) {
        self.state = state
        self.isFullRefresh = isFullRefresh
        self.sourcesRefreshed = sourcesRefreshed
    }
}

public struct UsageIncrementalLoader: Sendable {
    private let claudeLoader: ClaudeUsageLoader
    private let codexLoader: CodexUsageLoader
    private let opencodeLoader: OpenCodeUsageLoader
    private let aggregator: UsageAggregator

    public init(
        claudeLoader: ClaudeUsageLoader? = nil,
        codexLoader: CodexUsageLoader? = nil,
        opencodeLoader: OpenCodeUsageLoader? = nil,
        aggregator: UsageAggregator = UsageAggregator()
    ) {
        self.claudeLoader = claudeLoader ?? ClaudeUsageLoader(cacheStore: UsageFileCacheStore())
        self.codexLoader = codexLoader ?? CodexUsageLoader(cacheStore: UsageFileCacheStore())
        self.opencodeLoader = opencodeLoader ?? OpenCodeUsageLoader(cacheStore: UsageFileCacheStore())
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
            print("[UsageIncremental] loadFull(\(source)) took \(Date().timeIntervalSince(start))s, events=\(result.events.count), files=\(result.fileSignatures.count)")
            allNewEvents.append(contentsOf: result.events)
            allWarnings.append(contentsOf: result.warnings)
            allMissingDirectories.append(contentsOf: result.missingDirectories)

            newState.setFileSignatures(result.fileSignatures, for: source)
            newState.updateSourceState(source, isFullRefresh: true, now: now, loadedFileCount: result.fileSignatures.count)
        }

        for source in sourcesToIncrementalRefresh {
            let start = Date()
            let result = try await loadIncremental(
                for: source,
                existingSignatures: currentState.fileSignatures(for: source)
            )
            print("[UsageIncremental] loadIncremental(\(source)) took \(Date().timeIntervalSince(start))s, events=\(result.events.count), totalFiles=\(result.fileSignatures.count), deleted=\(result.deletedPaths.count)")
            allNewEvents.append(contentsOf: result.events)
            allWarnings.append(contentsOf: result.warnings)
            allMissingDirectories.append(contentsOf: result.missingDirectories)

            if !result.deletedPaths.isEmpty {
                deletedPathsBySource[source] = result.deletedPaths
            }

            newState.setFileSignatures(result.fileSignatures, for: source)
            newState.updateSourceState(source, isFullRefresh: false, now: now, loadedFileCount: result.fileSignatures.count)
        }

        let resolveStart = Date()
        let (resolvedNewEvents, _, _) = await aggregator.resolveEvents(
            from: [UsageLoadResult(events: allNewEvents, warnings: [], missingDirectories: [])],
            sources: sources
        )
        print("[UsageIncremental] resolveEvents took \(Date().timeIntervalSince(resolveStart))s for \(allNewEvents.count) events")

        let filterStart = Date()
        let fullRefreshSources = Set(sourcesToFullRefresh)
        newState.resolvedEvents = currentState.resolvedEvents.filter { resolved in
            let event = resolved.event
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

        print("[UsageIncremental] refresh total took \(Date().timeIntervalSince(overallStart))s")

        return UsageIncrementalLoadResult(
            state: newState,
            isFullRefresh: hasFullRefresh,
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
        let step1Start = Date()
        let roots: [URL]
        let missingDirectories: [String]
        switch source {
        case .claudeCode:
            let resolved = ClaudeUsageLoader().resolveRoots()
            roots = resolved.roots
            missingDirectories = resolved.missingDirectories
        case .codex:
            let resolved = CodexUsageLoader().resolveRoots()
            roots = resolved.roots
            missingDirectories = resolved.missingDirectories
        case .opencode:
            let resolved = OpenCodeUsageLoader().resolveRoots()
            roots = resolved.roots
            missingDirectories = resolved.missingDirectories
        }

        let pathExtension = source == .opencode ? "json" : "jsonl"
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
                    fileEvents = try ClaudeUsageLoader().loadEventsFromFile(url: url, cutoffDate: nil)
                case .codex:
                    fileEvents = try CodexUsageLoader().loadEventsFromFile(url: url, cutoffDate: nil)
                case .opencode:
                    fileEvents = try OpenCodeUsageLoader().loadEventsFromFile(url: url, cutoffDate: nil)
                }
                events.append(contentsOf: fileEvents)
            } catch {
                warnings.append("\(source.displayName) 解析失败: \(url.path)")
            }
        }
        print("[UsageIncremental] loadIncremental(\(source)): load changed files took \(Date().timeIntervalSince(step2Start))s, events=\(events.count)")

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
        }
    }
}