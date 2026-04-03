import Foundation
import Testing
@testable import VibeBarCore

@Test func usageSnapshotDefaultsAreEmpty() {
    let snapshot = UsageSnapshot.empty
    #expect(snapshot.totalTokens == 0)
    #expect(snapshot.totalCostUSD == 0)
    #expect(snapshot.buckets.isEmpty)
    #expect(snapshot.series.isEmpty)
}

@Test func usageSnapshotStoreRoundTrips() throws {
    let directory = try makeTemporaryDirectory(prefix: "usage-snapshot")
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = UsageSnapshotStore(baseURL: directory)
    let snapshot = UsageSnapshot.empty(configuration: .default)

    try store.write(snapshot)
    let loaded = try store.load()

    #expect(loaded != nil)
    #expect(loaded?.totalTokens == 0)
    #expect(loaded?.configuration.refreshCadence == .fiveMinutes)
}

@Test func usageAggregatorGroupsByDayAndModel() async {
    let events = [
        UsageEvent(
            id: "claude-1",
            source: .claudeCode,
            sessionID: "claude-session",
            timestamp: date("2026-03-10T12:00:00Z"),
            modelName: "claude-sonnet-4-5-20250929",
            inputTokens: 2_000,
            outputTokens: 500,
            cacheReadTokens: 200,
            cacheWriteTokens: 100,
            costUSD: 0.012
        ),
        UsageEvent(
            id: "codex-1",
            source: .codex,
            sessionID: "codex-session",
            timestamp: date("2026-03-11T01:00:00Z"),
            modelName: "gpt-5-codex",
            inputTokens: 1_000,
            outputTokens: 300,
            cacheReadTokens: 100,
            cacheWriteTokens: 0
        ),
        UsageEvent(
            id: "opencode-1",
            source: .opencode,
            sessionID: "opencode-session",
            timestamp: date("2026-03-11T02:00:00Z"),
            modelName: "custom-model",
            inputTokens: 800,
            outputTokens: 200,
            cacheReadTokens: 0,
            cacheWriteTokens: 0
        ),
    ]

    let configuration = UsageDisplayConfiguration(
        sources: [.claudeCode, .codex, .opencode],
        refreshCadence: .fiveMinutes,
        visualizationStyle: .barChart,
        metric: .tokens,
        granularity: .day,
        seriesGrouping: .model,
        maxSeriesCount: 2
    )

    let snapshot = await UsageAggregator().buildSnapshot(
        from: [UsageLoadResult(events: events)],
        configuration: configuration,
        now: date("2026-03-12T00:00:00Z")
    )

    #expect(snapshot.buckets.count == 10)
    let nonEmptyBuckets = snapshot.buckets.filter { $0.tokens > 0 }
    #expect(nonEmptyBuckets.count == 2)
    #expect(snapshot.series.count == 2)
    #expect(snapshot.series.map(\.label).contains("Others"))
    #expect(snapshot.totalTokens == 5_200)
    #expect(snapshot.totalCostUSD > 0.012)
    #expect(snapshot.estimatedCostEventCount == 1)
    #expect(snapshot.unresolvedCostEventCount == 1)
    #expect(snapshot.heatmapCells.count == 273)
    #expect(snapshot.warnings.contains(where: { $0.contains("custom-model") }))
}

@Test func usageAggregatorBuildSnapshotFromResolvedHonorsSourcesAndAgentGrouping() async {
    let loadResults = [UsageLoadResult(events: [
        UsageEvent(
            id: "claude-1",
            source: .claudeCode,
            sessionID: "claude-session",
            timestamp: date("2026-03-10T12:00:00Z"),
            modelName: "claude-sonnet-4-5-20250929",
            inputTokens: 2_000,
            outputTokens: 500,
            cacheReadTokens: 200,
            cacheWriteTokens: 100,
            costUSD: 0.012
        ),
        UsageEvent(
            id: "codex-1",
            source: .codex,
            sessionID: "codex-session",
            timestamp: date("2026-03-11T01:00:00Z"),
            modelName: "gpt-5-codex",
            inputTokens: 1_000,
            outputTokens: 300,
            cacheReadTokens: 100,
            cacheWriteTokens: 0
        ),
        UsageEvent(
            id: "opencode-1",
            source: .opencode,
            sessionID: "opencode-session",
            timestamp: date("2026-03-11T02:00:00Z"),
            modelName: "custom-model",
            inputTokens: 800,
            outputTokens: 200,
            cacheReadTokens: 0,
            cacheWriteTokens: 0
        ),
    ])]

    let aggregator = UsageAggregator()
    let resolvedEvents = await aggregator.resolveEvents(
        from: loadResults,
        sources: UsageSource.allCases
    ).events
    let configuration = UsageDisplayConfiguration(
        sources: [.codex],
        refreshCadence: .fiveMinutes,
        visualizationStyle: .lineChart,
        metric: .tokens,
        granularity: .day,
        seriesGrouping: .agent
    )

    let snapshot = aggregator.buildSnapshotFromResolved(
        resolvedEvents: resolvedEvents,
        loadResults: loadResults,
        configuration: configuration,
        now: date("2026-03-12T00:00:00Z")
    )

    #expect(snapshot.totalTokens == 1_400)
    #expect(snapshot.series.map(\.label) == [UsageSource.codex.displayName])
    #expect(snapshot.buckets.count == 10)
    let nonEmptyBuckets = snapshot.buckets.filter { $0.tokens > 0 }
    #expect(nonEmptyBuckets.count == 1)
    #expect(nonEmptyBuckets.first?.breakdown.map(\.label) == [UsageSource.codex.displayName])
    #expect(snapshot.estimatedCostEventCount == 1)
    #expect(snapshot.unresolvedCostEventCount == 0)
    #expect(snapshot.warnings.contains(where: { $0.contains("custom-model") }) == false)
}

@Test func usageAggregatorGroupsByProject() async {
    let events = [
        UsageEvent(
            id: "claude-1",
            source: .claudeCode,
            sessionID: "session-1",
            timestamp: date("2026-03-10T12:00:00Z"),
            modelName: "claude-sonnet-4-5-20250929",
            inputTokens: 2_000,
            outputTokens: 500,
            cacheReadTokens: 0,
            cacheWriteTokens: 0,
            workingDirectory: "/Users/test/projects/VibeBar"
        ),
        UsageEvent(
            id: "codex-1",
            source: .codex,
            sessionID: "session-2",
            timestamp: date("2026-03-10T13:00:00Z"),
            modelName: "gpt-5-codex",
            inputTokens: 1_000,
            outputTokens: 300,
            cacheReadTokens: 0,
            cacheWriteTokens: 0,
            workingDirectory: "/Users/test/projects/moss-cloud"
        ),
        UsageEvent(
            id: "opencode-1",
            source: .opencode,
            sessionID: "session-3",
            timestamp: date("2026-03-11T01:00:00Z"),
            modelName: "custom-model",
            inputTokens: 800,
            outputTokens: 200,
            cacheReadTokens: 0,
            cacheWriteTokens: 0,
            workingDirectory: "/Users/test/projects/VibeBar"
        ),
        UsageEvent(
            id: "opencode-2",
            source: .opencode,
            sessionID: "session-4",
            timestamp: date("2026-03-11T02:00:00Z"),
            modelName: "custom-model",
            inputTokens: 500,
            outputTokens: 100,
            cacheReadTokens: 0,
            cacheWriteTokens: 0,
            workingDirectory: nil
        ),
    ]

    let configuration = UsageDisplayConfiguration(
        sources: [.claudeCode, .codex, .opencode],
        refreshCadence: .fiveMinutes,
        visualizationStyle: .barChart,
        metric: .tokens,
        granularity: .day,
        seriesGrouping: .project,
        maxSeriesCount: 10
    )

    let snapshot = await UsageAggregator().buildSnapshot(
        from: [UsageLoadResult(events: events)],
        configuration: configuration,
        now: date("2026-03-12T00:00:00Z")
    )

    #expect(snapshot.buckets.count == 10)
    let nonEmptyBuckets = snapshot.buckets.filter { $0.tokens > 0 }
    #expect(nonEmptyBuckets.count == 2)
    #expect(snapshot.series.count == 3)
    let labels = Set(snapshot.series.map(\.label))
    #expect(labels.contains("VibeBar"))
    #expect(labels.contains("moss-cloud"))
    #expect(labels.contains("unknown"))
    #expect(snapshot.totalTokens == 5_400)
}

private func makeTemporaryDirectory(prefix: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func date(_ value: String) -> Date {
    UsageLoaderSupport.parseDate(value) ?? Date(timeIntervalSince1970: 0)
}
