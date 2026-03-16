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
    @Published private(set) var lastRefreshInfo: RefreshInfo?

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
    private var cancellables = Set<AnyCancellable>()

    struct RefreshInfo: Sendable {
        var timestamp: Date
        var isFullRefresh: Bool
        var sourcesRefreshed: [UsageSource]
        var duration: TimeInterval
    }

    private init() {
        let configuration = AppSettings.shared.usageConfiguration
        self.snapshot = (try? snapshotStore.load()) ?? .empty(configuration: configuration)
        self.currentCadence = configuration.refreshCadence
        self.incrementalState = incrementalStore.load() ?? .empty
        reconcileLoadedSnapshot(with: configuration)
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

    func forceFullRefresh() {
        forceFullRefreshNext = true
        scheduleRefresh()
    }

    func clearCacheAndRefresh() {
        incrementalStore.delete()
        snapshotStore.delete()
        incrementalState = .empty
        forceFullRefreshNext = true
        scheduleRefresh()
    }

    private func reconcileLoadedSnapshot(with configuration: UsageDisplayConfiguration) {
        guard snapshot.configuration != configuration else { return }

        guard !incrementalState.resolvedEvents.isEmpty else {
            snapshot = .empty(configuration: configuration)
            return
        }

        let rebuiltUpdatedAt = snapshot.updatedAt == .distantPast ? Date() : snapshot.updatedAt
        var rebuiltSnapshot = UsageAggregator().buildSnapshotFromResolved(
            resolvedEvents: incrementalState.resolvedEvents,
            loadResults: [UsageLoadResult(
                events: incrementalState.resolvedEvents.map(\.event),
                warnings: incrementalState.warnings,
                missingDirectories: incrementalState.missingDirectories
            )],
            configuration: configuration,
            now: rebuiltUpdatedAt
        )
        rebuiltSnapshot.loadDuration = snapshot.loadDuration
        snapshot = rebuiltSnapshot
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

    private func handlePresentationChange(to configuration: UsageDisplayConfiguration) {
        requestedPresentationVersion += 1

        var updatedSnapshot = snapshot
        updatedSnapshot.configuration = configuration
        snapshot = updatedSnapshot

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
                self.handlePresentationChange(
                    to: self.configurationByUpdating(sources: sources)
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
        isRebuilding = true
        let configuration = snapshot.configuration
        let state = incrementalState
        let loadVersion = lastLoadResultsVersion
        let presentationVersion = requestedPresentationVersion
        rebuildTask?.cancel()

        rebuildTask = Task { @MainActor [weak self] in
            let snapshot = await Task.detached(priority: .utility) {
                UsageAggregator().buildSnapshotFromResolved(
                    resolvedEvents: state.resolvedEvents,
                    loadResults: [UsageLoadResult(
                        events: state.resolvedEvents.map(\.event),
                        warnings: state.warnings,
                        missingDirectories: state.missingDirectories
                    )],
                    configuration: configuration
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

        let refreshConfiguration = snapshot.configuration
        let fullRefreshInterval = AppSettings.shared.usageFullRefreshInterval
        let currentState = incrementalState
        let forceFull = forceFullRefreshNext
        forceFullRefreshNext = false

        let refreshOperation = Task.detached(priority: .utility) { () -> (
            state: UsageIncrementalState,
            isFullRefresh: Bool,
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
                return (result.state, result.isFullRefresh, result.sourcesRefreshed)
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
                let snapshot = await Task.detached(priority: .utility) {
                    UsageAggregator().buildSnapshotFromResolved(
                        resolvedEvents: result.state.resolvedEvents,
                        loadResults: [UsageLoadResult(
                            events: result.state.resolvedEvents.map(\.event),
                            warnings: result.state.warnings,
                            missingDirectories: result.state.missingDirectories
                        )],
                        configuration: presentationConfiguration
                    )
                }.value

                let refreshInfo = RefreshInfo(
                    timestamp: Date(),
                    isFullRefresh: result.isFullRefresh,
                    sourcesRefreshed: result.sourcesRefreshed,
                    duration: self.refreshStartTime.map { Date().timeIntervalSince($0) } ?? 0
                )
                self.finishReload(
                    with: snapshot,
                    loadVersion: loadVersion,
                    refreshInfo: refreshInfo,
                    presentationVersion: presentationVersion
                )
            } catch {
                guard let self else { return }
                self.lastErrorMessage = error.localizedDescription
                self.isRefreshing = false
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
        presentationVersion: Int
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
        reloadTask = nil

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
        isRebuilding = false
        pendingReload = false
        pendingRebuild = false
    }
}
