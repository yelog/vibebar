import Combine
import Foundation
import VibeBarCore

@MainActor
final class UsageMonitorViewModel: ObservableObject {
    static let shared = UsageMonitorViewModel()

    @Published private(set) var snapshot: UsageSnapshot
    @Published private(set) var isRefreshing = false
    @Published private(set) var isFullRefreshing = false
    @Published private(set) var isRebuilding = false
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var lastRefreshInfo: RefreshInfo?
    @Published private(set) var incrementalRefreshTime: Date?
    @Published private(set) var incrementalRefreshDuration: TimeInterval?
    @Published private(set) var fullRefreshTime: Date?
    @Published private(set) var fullRefreshDuration: TimeInterval?

    private let snapshotStore = UsageSnapshotStore()
    private let incrementalStore = UsageIncrementalStore()
    private let incrementalLoader = UsageIncrementalLoader()
    private var timer: Timer?
    private var currentCadence: UsageRefreshCadence
    private var pendingReload = false
    private var pendingRebuild = false
    private var reloadTask: Task<Void, Never>?
    private var rebuildTask: Task<Void, Never>?
    private var incrementalState: UsageIncrementalState
    private var lastLoadResultsVersion = 0
    private var requestedPresentationVersion = 0
    private var refreshStartTime: Date?
    private var forceFullRefreshNext = false
    private var isManualFullRefresh = false
    private var isInitialAutoRefresh = false
    private var cancellables = Set<AnyCancellable>()

    struct RefreshInfo: Sendable {
        var timestamp: Date
        var isFullRefresh: Bool
        var isCompleteFullRefresh: Bool  // 所有 sources 都是全量刷新
        var sourcesRefreshed: [UsageSource]
        var duration: TimeInterval
    }

    private init() {
        let configuration = AppSettings.shared.usageConfiguration
        self.snapshot = (try? snapshotStore.load()) ?? .empty(configuration: configuration)
        self.currentCadence = configuration.refreshCadence
        self.incrementalState = incrementalStore.load() ?? .empty
        restoreRefreshTimesFromState()
        reconcileLoadedSnapshot(with: configuration)
        observeSettings()
        if AppSettings.shared.usageEnabled {
            startTimer(with: currentCadence)
            isInitialAutoRefresh = true
            refreshNow()
        }
    }

    private func restoreRefreshTimesFromState() {
        // 优先使用全局刷新时间（更准确，代表整个刷新操作）
        if let globalFullTime = incrementalState.globalLastFullRefreshAt {
            fullRefreshTime = globalFullTime
            fullRefreshDuration = incrementalState.globalLastFullRefreshDuration
        }
        if let globalIncrTime = incrementalState.globalLastIncrementalRefreshAt {
            incrementalRefreshTime = globalIncrTime
            incrementalRefreshDuration = incrementalState.globalLastIncrementalRefreshDuration
        }
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            startTimer(with: currentCadence)
            refreshNow()
        } else {
            stopTimer()
        }
    }

    func refreshNow() {
        isManualFullRefresh = false
        scheduleRefresh()
    }

    func forceFullRefresh() {
        forceFullRefreshNext = true
        isManualFullRefresh = true
        scheduleRefresh()
    }

    func clearCacheAndRefresh() {
        incrementalStore.delete()
        snapshotStore.delete()
        incrementalState = .empty
        incrementalLoader.clearFileCaches(for: snapshot.configuration.normalizedSources)
        forceFullRefreshNext = true
        isManualFullRefresh = true
        scheduleRefresh()
    }

    private func reconcileLoadedSnapshot(with configuration: UsageDisplayConfiguration) {
        guard snapshot.configuration != configuration else { return }

        guard !incrementalState.resolvedEvents.isEmpty else {
            snapshot = .empty(configuration: configuration)
            return
        }

        let (updatedBucketsCache, rebuiltSnapshot) = UsageAggregator().buildSnapshotFromResolved(
            resolvedEvents: incrementalState.resolvedEvents,
            loadResults: [UsageLoadResult(
                events: incrementalState.resolvedEvents.map(\.event),
                warnings: incrementalState.warnings,
                missingDirectories: incrementalState.missingDirectories
            )],
            configuration: configuration,
            dailyAggregations: incrementalState.dailyAggregations,
            dailyAggregationsSources: incrementalState.dailyAggregationsSources,
            bucketsCache: incrementalState.bucketsCache,
            previousSnapshot: snapshot,
            now: Date()
        )
        snapshot = rebuiltSnapshot
        incrementalState.bucketsCache = updatedBucketsCache
        try? snapshotStore.write(rebuiltSnapshot)
    }

    private func configurationByUpdating(
        sources: [UsageSource]? = nil,
        refreshCadence: UsageRefreshCadence? = nil,
        visualizationStyle: UsageVisualizationStyle? = nil,
        metric: UsageMetric? = nil,
        granularity: UsageGranularity? = nil,
        seriesGrouping: UsageSeriesGrouping? = nil
    ) -> UsageDisplayConfiguration {
        var configuration = snapshot.configuration
        if let sources {
            configuration.sources = sources
        }
        if let refreshCadence {
            configuration.refreshCadence = refreshCadence
        }
        if let visualizationStyle {
            configuration.visualizationStyle = visualizationStyle
        }
        if let metric {
            configuration.metric = metric
        }
        if let granularity {
            configuration.granularity = granularity
        }
        if let seriesGrouping {
            configuration.seriesGrouping = seriesGrouping
        }
        return configuration
    }

    private func handlePresentationChange(
        to configuration: UsageDisplayConfiguration,
        previousSources: [UsageSource]? = nil
    ) {
        requestedPresentationVersion += 1

        var updatedSnapshot = snapshot
        updatedSnapshot.configuration = configuration
        snapshot = updatedSnapshot

        // 检测新增且无缓存的数据源，立即触发刷新
        if let previous = previousSources {
            let newSources = configuration.normalizedSources.filter { !previous.contains($0) }
            let sourcesWithoutCache = newSources.filter { !incrementalState.hasData(for: $0) }
            if !sourcesWithoutCache.isEmpty {
                if !isRefreshing {
                    scheduleRefresh()
                } else {
                    pendingReload = true
                }
                return
            }
        }

        if incrementalState.resolvedEvents.isEmpty {
            if !isRefreshing {
                scheduleRefresh()
            } else {
                pendingRebuild = true
            }
        } else {
            rebuildSnapshotFromCachedResults()
        }
    }

    private func observeSettings() {
        AppSettings.shared.$usageEnabled
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] enabled in
                self?.setEnabled(enabled)
            }
            .store(in: &cancellables)

        AppSettings.shared.$usageRefreshCadence
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] cadence in
                guard let self else { return }
                var updatedSnapshot = self.snapshot
                updatedSnapshot.configuration = self.configurationByUpdating(refreshCadence: cadence)
                self.snapshot = updatedSnapshot
                self.currentCadence = cadence
                if AppSettings.shared.usageEnabled {
                    self.startTimer(with: cadence)
                }
            }
            .store(in: &cancellables)

        AppSettings.shared.$usageFullRefreshInterval
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self else { return }
                self.requestedPresentationVersion += 1
            }
            .store(in: &cancellables)

        AppSettings.shared.$usageSources
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] sources in
                guard let self else { return }
                let previousSources = self.snapshot.configuration.normalizedSources
                self.handlePresentationChange(
                    to: self.configurationByUpdating(sources: sources),
                    previousSources: previousSources
                )
            }
            .store(in: &cancellables)

        AppSettings.shared.$usageVisualizationStyle
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] visualizationStyle in
                guard let self else { return }
                self.handlePresentationChange(
                    to: self.configurationByUpdating(visualizationStyle: visualizationStyle)
                )
            }
            .store(in: &cancellables)

        AppSettings.shared.$usageMetric
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] metric in
                guard let self else { return }
                self.handlePresentationChange(
                    to: self.configurationByUpdating(metric: metric)
                )
            }
            .store(in: &cancellables)

        AppSettings.shared.$usageGranularity
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] granularity in
                guard let self else { return }
                self.handlePresentationChange(
                    to: self.configurationByUpdating(granularity: granularity)
                )
            }
            .store(in: &cancellables)

        AppSettings.shared.$usageSeriesGrouping
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] seriesGrouping in
                guard let self else { return }
                self.handlePresentationChange(
                    to: self.configurationByUpdating(seriesGrouping: seriesGrouping)
                )
            }
            .store(in: &cancellables)
    }

    private func rebuildSnapshotFromCachedResults() {
        guard !incrementalState.resolvedEvents.isEmpty else { return }
        let rebuildStart = Date()
        isRebuilding = true
        let configuration = snapshot.configuration
        let currentSnapshot = snapshot
        let state = incrementalState
        let hasDailyCache = !state.dailyAggregations.isEmpty
        let hasBucketsCache = !state.bucketsCache.isEmpty
        print("[UsageMonitor] rebuildSnapshotFromCachedResults started, style=\(configuration.visualizationStyle), hasDailyCache=\(hasDailyCache), hasBucketsCache=\(hasBucketsCache), events=\(state.resolvedEvents.count)")
        let loadVersion = lastLoadResultsVersion
        let presentationVersion = requestedPresentationVersion
        rebuildTask?.cancel()

        rebuildTask = Task { @MainActor [weak self] in
            let (updatedBucketsCache, snapshot) = await Task.detached(priority: .utility) {
                UsageAggregator().buildSnapshotFromResolved(
                    resolvedEvents: state.resolvedEvents,
                    loadResults: [UsageLoadResult(
                        events: state.resolvedEvents.map(\.event),
                        warnings: state.warnings,
                        missingDirectories: state.missingDirectories
                    )],
                    configuration: configuration,
                    dailyAggregations: state.dailyAggregations,
                    dailyAggregationsSources: state.dailyAggregationsSources,
                    bucketsCache: state.bucketsCache,
                    previousSnapshot: currentSnapshot
                )
            }.value
            print("[UsageMonitor] rebuildSnapshotFromCachedResults finished in \(Date().timeIntervalSince(rebuildStart))s")
            self?.incrementalState.bucketsCache = updatedBucketsCache
            self?.finishRebuild(
                with: snapshot,
                loadVersion: loadVersion,
                presentationVersion: presentationVersion
            )
        }
    }

    private func scheduleRefresh() {
        guard !isRefreshing else {
            pendingReload = true
            return
        }

        let isFullRefreshRequest = isManualFullRefresh
        if isFullRefreshRequest {
            isFullRefreshing = true
        } else {
            isRefreshing = true
        }
        lastErrorMessage = nil
        refreshStartTime = Date()
        reloadTask?.cancel()

        let refreshConfiguration = snapshot.configuration
        let fullRefreshInterval = AppSettings.shared.usageFullRefreshInterval
        let currentState = incrementalState
        let forceFull = forceFullRefreshNext
        forceFullRefreshNext = false
        isManualFullRefresh = false

        let refreshOperation = Task.detached(priority: .utility) { () -> (
            state: UsageIncrementalState,
            isFullRefresh: Bool,
            isCompleteFullRefresh: Bool,
            sourcesRefreshed: [UsageSource]
        ) in
            let sources = refreshConfiguration.normalizedSources
            do {
                let result = try await self.incrementalLoader.refresh(
                    currentState: currentState,
                    sources: sources,
                    fullRefreshInterval: fullRefreshInterval,
                    forceFullRefresh: forceFull
                )
                return (result.state, result.isFullRefresh, result.isCompleteFullRefresh, result.sourcesRefreshed)
            } catch {
                throw error
            }
        }

        reloadTask = Task { @MainActor [weak self] in
            do {
                let result = try await refreshOperation.value
                guard let self else { return }
                self.incrementalState = result.state
                self.lastLoadResultsVersion += 1

                try? self.incrementalStore.write(result.state)

                let loadVersion = self.lastLoadResultsVersion
                let presentationVersion = self.requestedPresentationVersion
                let presentationConfiguration = self.snapshot.configuration
                let (updatedBucketsCache, snapshot) = await Task.detached(priority: .utility) {
                    UsageAggregator().buildSnapshotFromResolved(
                        resolvedEvents: result.state.resolvedEvents,
                        loadResults: [UsageLoadResult(
                            events: result.state.resolvedEvents.map(\.event),
                            warnings: result.state.warnings,
                            missingDirectories: result.state.missingDirectories
                        )],
                        configuration: presentationConfiguration,
                        dailyAggregations: result.state.dailyAggregations,
                        dailyAggregationsSources: result.state.dailyAggregationsSources,
                        bucketsCache: result.state.bucketsCache
                    )
                }.value
                self.incrementalState.bucketsCache = updatedBucketsCache

                let refreshInfo = RefreshInfo(
                    timestamp: Date(),
                    isFullRefresh: result.isFullRefresh,
                    isCompleteFullRefresh: result.isCompleteFullRefresh,
                    sourcesRefreshed: result.sourcesRefreshed,
                    duration: self.refreshStartTime.map { Date().timeIntervalSince($0) } ?? 0
                )
                self.finishReload(
                    with: snapshot,
                    loadVersion: loadVersion,
                    refreshInfo: refreshInfo,
                    presentationVersion: presentationVersion,
                    isFullRefreshRequest: isFullRefreshRequest
                )
            } catch {
                guard let self else { return }
                self.lastErrorMessage = error.localizedDescription
                self.isRefreshing = false
                self.isFullRefreshing = false
                self.reloadTask = nil
                self.refreshStartTime = nil

                if self.pendingReload {
                    self.pendingReload = false
                    self.scheduleRefresh()
                }
            }
        }
    }

    private func finishRebuild(
        with snapshot: UsageSnapshot,
        loadVersion: Int,
        presentationVersion: Int
    ) {
        isRebuilding = false
        rebuildTask = nil

        guard lastLoadResultsVersion == loadVersion,
              requestedPresentationVersion == presentationVersion else {
            return
        }

        var finalSnapshot = snapshot
        finalSnapshot.loadDuration = self.snapshot.loadDuration
        applySnapshot(finalSnapshot)
    }

    private func finishReload(
        with snapshot: UsageSnapshot,
        loadVersion: Int,
        refreshInfo: RefreshInfo,
        presentationVersion: Int,
        isFullRefreshRequest: Bool = false
    ) {
        guard lastLoadResultsVersion == loadVersion else { return }

        let loadDuration = refreshStartTime.map { Date().timeIntervalSince($0) }
        if let loadDuration {
            var updatedSnapshot = self.snapshot
            updatedSnapshot.loadDuration = loadDuration
            self.snapshot = updatedSnapshot
        }
        refreshStartTime = nil

        lastRefreshInfo = refreshInfo
        isRefreshing = false
        isFullRefreshing = false
        reloadTask = nil

        // 更新 UI 显示的时间（所有刷新操作统一处理）
        if refreshInfo.isCompleteFullRefresh {
            // 完整全量刷新：更新全量时间和增量时间（因为数据都刷新了）
            fullRefreshTime = refreshInfo.timestamp
            fullRefreshDuration = refreshInfo.duration
            incrementalRefreshTime = refreshInfo.timestamp
            incrementalRefreshDuration = refreshInfo.duration
            // 保存到全局状态（下次启动恢复）
            incrementalState.globalLastFullRefreshAt = refreshInfo.timestamp
            incrementalState.globalLastFullRefreshDuration = refreshInfo.duration
            incrementalState.globalLastIncrementalRefreshAt = refreshInfo.timestamp
            incrementalState.globalLastIncrementalRefreshDuration = refreshInfo.duration
        } else {
            // 完整增量刷新 或 部分全量部分增量：都更新增量时间
            // 因为数据确实被刷新了，用户需要知道最近一次数据更新时间
            incrementalRefreshTime = refreshInfo.timestamp
            incrementalRefreshDuration = refreshInfo.duration
            incrementalState.globalLastIncrementalRefreshAt = refreshInfo.timestamp
            incrementalState.globalLastIncrementalRefreshDuration = refreshInfo.duration
        }
        
        isInitialAutoRefresh = false

        guard requestedPresentationVersion == presentationVersion else {
            pendingRebuild = false
            rebuildSnapshotFromCachedResults()

            if pendingReload {
                pendingReload = false
                scheduleRefresh()
            }
            return
        }

        var finalSnapshot = snapshot
        finalSnapshot.loadDuration = loadDuration
        applySnapshot(finalSnapshot)
        pendingRebuild = false

        if pendingReload {
            pendingReload = false
            scheduleRefresh()
        }
    }

    private func applySnapshot(_ snapshot: UsageSnapshot) {
        self.snapshot = snapshot
        try? snapshotStore.write(snapshot)
    }

    private func startTimer(with cadence: UsageRefreshCadence) {
        timer?.invalidate()
        currentCadence = cadence
        let newTimer = Timer(timeInterval: cadence.timeInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduleRefresh()
            }
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        reloadTask?.cancel()
        reloadTask = nil
        rebuildTask?.cancel()
        rebuildTask = nil
        isRefreshing = false
        isFullRefreshing = false
        isRebuilding = false
        pendingReload = false
        pendingRebuild = false
    }
}
