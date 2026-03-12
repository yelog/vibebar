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

    #expect(snapshot.buckets.count == 2)
    #expect(snapshot.series.count == 2)
    #expect(snapshot.series.map(\.label).contains("Others"))
    #expect(snapshot.totalTokens == 5_200)
    #expect(snapshot.totalCostUSD > 0.012)
    #expect(snapshot.estimatedCostEventCount == 1)
    #expect(snapshot.unresolvedCostEventCount == 1)
    #expect(snapshot.heatmapCells.count == 364)
    #expect(snapshot.warnings.contains(where: { $0.contains("custom-model") }))
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
