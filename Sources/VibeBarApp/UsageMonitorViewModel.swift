import Combine
import Foundation
import VibeBarCore

@MainActor
final class UsageMonitorViewModel: ObservableObject {
    static let shared = UsageMonitorViewModel()

    @Published private(set) var snapshot: UsageSnapshot
    @Published private(set) var isRefreshing = false
    @Published private(set) var isRebuilding = false
    @Published private(set) var lastErrorMessage: String?

    private let snapshotStore = UsageSnapshotStore()
    private var timer: Timer?
    private var currentCadence: UsageRefreshCadence
    private var pendingReload = false
    private var pendingRebuild = false
    private var reloadTask: Task<Void, Never>?
    private var rebuildTask: Task<Void, Never>?
    private var lastLoadResults: [UsageLoadResult] = []
    private var lastLoadResultsVersion = 0
    private var cachedResolvedEvents: [ResolvedUsageEvent] = []
    private var cachedEstimatedCount = 0
    private var cachedUnresolvedCount = 0
    private var requestedPresentationVersion = 0
    private var refreshStartTime: Date?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        let configuration = AppSettings.shared.usageConfiguration
        self.snapshot = (try? snapshotStore.load()) ?? .empty(configuration: configuration)
        self.currentCadence = configuration.refreshCadence
        observeSettings()
        if AppSettings.shared.usageEnabled {
            startTimer(with: currentCadence)
            refreshNow()
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
        scheduleRefresh()
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
                if AppSettings.shared.usageEnabled {
                    self.startTimer(with: cadence)
                }
            }
            .store(in: &cancellables)

        let presentationChanges: [AnyPublisher<Void, Never>] = [
            AppSettings.shared.$usageSources
                .dropFirst()
                .removeDuplicates()
                .map { _ in () }
                .eraseToAnyPublisher(),
            AppSettings.shared.$usageVisualizationStyle
                .dropFirst()
                .removeDuplicates()
                .map { _ in () }
                .eraseToAnyPublisher(),
            AppSettings.shared.$usageMetric
                .dropFirst()
                .removeDuplicates()
                .map { _ in () }
                .eraseToAnyPublisher(),
            AppSettings.shared.$usageGranularity
                .dropFirst()
                .removeDuplicates()
                .map { _ in () }
                .eraseToAnyPublisher(),
            AppSettings.shared.$usageSeriesGrouping
                .dropFirst()
                .removeDuplicates()
                .map { _ in () }
                .eraseToAnyPublisher(),
        ]

        Publishers.MergeMany(presentationChanges)
            .sink { [weak self] _ in
                guard let self else { return }
                self.requestedPresentationVersion += 1

                var updatedSnapshot = self.snapshot
                updatedSnapshot.configuration = AppSettings.shared.usageConfiguration
                self.snapshot = updatedSnapshot

                if self.cachedResolvedEvents.isEmpty {
                    if !self.isRefreshing {
                        self.scheduleRefresh()
                    } else {
                        self.pendingRebuild = true
                    }
                } else {
                    self.rebuildSnapshotFromCachedResults()
                }
            }
            .store(in: &cancellables)
    }

    private func rebuildSnapshotFromCachedResults() {
        guard !cachedResolvedEvents.isEmpty else { return }
        isRebuilding = true
        let configuration = AppSettings.shared.usageConfiguration
        let resolvedEvents = cachedResolvedEvents
        let loadResults = lastLoadResults
        let estimatedCount = cachedEstimatedCount
        let unresolvedCount = cachedUnresolvedCount
        let loadVersion = lastLoadResultsVersion
        let presentationVersion = requestedPresentationVersion
        rebuildTask?.cancel()

        rebuildTask = Task { @MainActor [weak self] in
            let snapshot = await Task.detached(priority: .utility) {
                UsageAggregator().buildSnapshotFromResolved(
                    resolvedEvents: resolvedEvents,
                    loadResults: loadResults,
                    configuration: configuration,
                    estimatedCostEventCount: estimatedCount,
                    unresolvedCostEventCount: unresolvedCount
                )
            }.value
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

        isRefreshing = true
        lastErrorMessage = nil
        refreshStartTime = Date()
        reloadTask?.cancel()

        let configuration = AppSettings.shared.usageConfiguration

        let refreshOperation = Task.detached(priority: .utility) { () -> (
            loadResults: [UsageLoadResult],
            resolvedEvents: [ResolvedUsageEvent],
            estimatedCount: Int,
            unresolvedCount: Int
        ) in
            // 根据显示配置计算时间过滤点
            let calendar = Calendar(identifier: .gregorian)
            let now = Date()
            let cutoffDate = configuration.chartCutoffDate(from: now, calendar: calendar)
            let loadRequest = UsageLoadRequest(cutoffDate: cutoffDate)

            async let claude: UsageLoadResult = (try? await ClaudeUsageLoader(cacheStore: UsageFileCacheStore()).load(request: loadRequest)) ?? UsageLoadResult()
            async let codex: UsageLoadResult = (try? await CodexUsageLoader(cacheStore: UsageFileCacheStore()).load(request: loadRequest)) ?? UsageLoadResult()
            async let opencode: UsageLoadResult = (try? await OpenCodeUsageLoader(cacheStore: UsageFileCacheStore()).load(request: loadRequest)) ?? UsageLoadResult()
            let loadResults = await [claude, codex, opencode]

            let (resolvedEvents, estimatedCount, unresolvedCount) = UsageAggregator().resolveEvents(
                from: loadResults,
                sources: configuration.normalizedSources
            )

            return (loadResults, resolvedEvents, estimatedCount, unresolvedCount)
        }

        reloadTask = Task { @MainActor [weak self] in
            let result = await refreshOperation.value
            guard let self else { return }
            self.lastLoadResults = result.loadResults
            self.cachedResolvedEvents = result.resolvedEvents
            self.cachedEstimatedCount = result.estimatedCount
            self.cachedUnresolvedCount = result.unresolvedCount
            self.lastLoadResultsVersion += 1

            let loadVersion = self.lastLoadResultsVersion
            let snapshot = await Task.detached(priority: .utility) {
                UsageAggregator().buildSnapshotFromResolved(
                    resolvedEvents: result.resolvedEvents,
                    loadResults: result.loadResults,
                    configuration: configuration,
                    estimatedCostEventCount: result.estimatedCount,
                    unresolvedCostEventCount: result.unresolvedCount
                )
            }.value
            self.finishReload(with: snapshot, loadVersion: loadVersion)
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

    private func finishReload(with snapshot: UsageSnapshot, loadVersion: Int) {
        guard lastLoadResultsVersion == loadVersion else { return }

        var finalSnapshot = snapshot
        if let startTime = refreshStartTime {
            finalSnapshot.loadDuration = Date().timeIntervalSince(startTime)
        }
        refreshStartTime = nil

        applySnapshot(finalSnapshot)
        isRefreshing = false
        reloadTask = nil

        if pendingReload {
            pendingReload = false
            scheduleRefresh()
        }

        if pendingRebuild {
            pendingRebuild = false
            rebuildSnapshotFromCachedResults()
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
        isRebuilding = false
        pendingReload = false
        pendingRebuild = false
    }
}
