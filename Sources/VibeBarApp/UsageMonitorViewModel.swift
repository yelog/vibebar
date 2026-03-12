import Combine
import Foundation
import VibeBarCore

@MainActor
final class UsageMonitorViewModel: ObservableObject {
    static let shared = UsageMonitorViewModel()

    @Published private(set) var snapshot: UsageSnapshot
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastErrorMessage: String?

    private let snapshotStore = UsageSnapshotStore()
    private var timer: Timer?
    private var currentCadence: UsageRefreshCadence
    private var isRebuildingSnapshot = false
    private var pendingReload = false
    private var pendingRebuild = false
    private var refreshTask: Task<Void, Never>?
    private var lastLoadResults: [UsageLoadResult] = []
    private var cancellables = Set<AnyCancellable>()

    private init() {
        let configuration = AppSettings.shared.usageConfiguration
        self.snapshot = (try? snapshotStore.load()) ?? .empty(configuration: configuration)
        self.currentCadence = configuration.refreshCadence
        observeSettings()
        startTimer(with: currentCadence)
        refreshNow()
    }

    func refreshNow() {
        scheduleRefresh()
    }

    private func observeSettings() {
        AppSettings.shared.$usageRefreshCadence
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] cadence in
                guard let self else { return }
                self.startTimer(with: cadence)
            }
            .store(in: &cancellables)

        AppSettings.shared.$usageSources
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self else { return }
                self.scheduleRefresh()
            }
            .store(in: &cancellables)

        let presentationChanges: [AnyPublisher<Void, Never>] = [
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
                if self.lastLoadResults.isEmpty {
                    if self.isRefreshing || self.isRebuildingSnapshot {
                        self.pendingRebuild = true
                    } else {
                        self.scheduleRefresh()
                    }
                } else {
                    self.rebuildSnapshotFromCachedResults()
                }
            }
            .store(in: &cancellables)
    }

    private func rebuildSnapshotFromCachedResults() {
        guard !lastLoadResults.isEmpty else {
            if isRefreshing || isRebuildingSnapshot {
                pendingRebuild = true
            } else {
                scheduleRefresh()
            }
            return
        }

        guard !isRefreshing, !isRebuildingSnapshot else {
            pendingRebuild = true
            return
        }

        isRebuildingSnapshot = true
        let configuration = AppSettings.shared.usageConfiguration
        let loadResults = lastLoadResults
        refreshTask?.cancel()

        let rebuildOperation = Task.detached(priority: .utility) {
            await UsageAggregator().buildSnapshot(from: loadResults, configuration: configuration)
        }

        refreshTask = Task { @MainActor [weak self] in
            let snapshot = await rebuildOperation.value
            self?.applySnapshot(snapshot)
        }
    }

    private func scheduleRefresh() {
        guard !isRefreshing, !isRebuildingSnapshot else {
            pendingReload = true
            return
        }

        isRefreshing = true
        lastErrorMessage = nil
        let configuration = AppSettings.shared.usageConfiguration
        refreshTask?.cancel()

        let refreshOperation = Task.detached(priority: .utility) { () -> ([UsageLoadResult], UsageSnapshot) in
            async let claude: UsageLoadResult = (try? await ClaudeUsageLoader(cacheStore: UsageFileCacheStore()).load()) ?? UsageLoadResult()
            async let codex: UsageLoadResult = (try? await CodexUsageLoader(cacheStore: UsageFileCacheStore()).load()) ?? UsageLoadResult()
            async let opencode: UsageLoadResult = (try? await OpenCodeUsageLoader(cacheStore: UsageFileCacheStore()).load()) ?? UsageLoadResult()
            let loadResults = await [claude, codex, opencode]
            let snapshot = await UsageAggregator().buildSnapshot(from: loadResults, configuration: configuration)
            return (loadResults, snapshot)
        }

        refreshTask = Task { @MainActor [weak self] in
            let (loadResults, snapshot) = await refreshOperation.value
            self?.applySnapshot(snapshot, loadResults: loadResults)
        }
    }

    private func applySnapshot(_ snapshot: UsageSnapshot, loadResults: [UsageLoadResult]? = nil) {
        self.snapshot = snapshot
        if let loadResults {
            self.lastLoadResults = loadResults
        }
        try? snapshotStore.write(snapshot)
        self.isRefreshing = false
        self.isRebuildingSnapshot = false
        self.refreshTask = nil

        if pendingReload {
            pendingReload = false
            pendingRebuild = false
            scheduleRefresh()
            return
        }

        if pendingRebuild {
            pendingRebuild = false
            rebuildSnapshotFromCachedResults()
        }
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
}
