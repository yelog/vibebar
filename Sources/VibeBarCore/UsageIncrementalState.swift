import Foundation

public enum UsageFullRefreshInterval: Int, Codable, CaseIterable, Identifiable, Sendable {
    case sixHours = 6
    case twelveHours = 12
    case twentyFourHours = 24
    case fortyEightHours = 48

    public var id: Int { rawValue }

    public var displayName: String {
        switch self {
        case .sixHours:
            return "6 hours"
        case .twelveHours:
            return "12 hours"
        case .twentyFourHours:
            return "24 hours"
        case .fortyEightHours:
            return "48 hours"
        }
    }

    public var hours: Int { rawValue }
}

public struct UsageFileSignature: Codable, Sendable, Equatable {
    public var modificationTimeIntervalSince1970: TimeInterval
    public var fileSize: Int64

    public init(modificationTime: Date, fileSize: Int64) {
        self.modificationTimeIntervalSince1970 = modificationTime.timeIntervalSince1970
        self.fileSize = fileSize
    }

    public var modificationDate: Date {
        Date(timeIntervalSince1970: modificationTimeIntervalSince1970)
    }
}

public struct UsageSourceRefreshState: Codable, Sendable, Equatable {
    public var source: UsageSource
    public var lastFullRefreshAt: Date
    public var lastIncrementalRefreshAt: Date
    public var loadedFileCount: Int

    public init(
        source: UsageSource,
        lastFullRefreshAt: Date = .distantPast,
        lastIncrementalRefreshAt: Date = .distantPast,
        loadedFileCount: Int = 0
    ) {
        self.source = source
        self.lastFullRefreshAt = lastFullRefreshAt
        self.lastIncrementalRefreshAt = lastIncrementalRefreshAt
        self.loadedFileCount = loadedFileCount
    }
}

public struct UsageIncrementalState: Codable, Sendable {
    public static let currentVersion = 5

    public var version: Int
    public var resolvedEvents: [ResolvedUsageEvent]
    public var fileSignaturesBySource: [UsageSource: [String: UsageFileSignature]]
    public var sourceStates: [UsageSource: UsageSourceRefreshState]
    public var estimatedCostEventCount: Int
    public var unresolvedCostEventCount: Int
    public var warnings: [String]
    public var missingDirectories: [String]
    /// 日聚合缓存，用于快速生成热力图
    public var dailyAggregations: [UsageDailyAggregation]
    /// Buckets 缓存，用于快速切换图表样式（按 granularity + grouping + sources 索引）
    public var bucketsCache: [UsageBucketsCacheKey: UsageBucketsCacheEntry]

    public init(
        version: Int = Self.currentVersion,
        resolvedEvents: [ResolvedUsageEvent] = [],
        fileSignaturesBySource: [UsageSource: [String: UsageFileSignature]] = [:],
        sourceStates: [UsageSource: UsageSourceRefreshState] = [:],
        estimatedCostEventCount: Int = 0,
        unresolvedCostEventCount: Int = 0,
        warnings: [String] = [],
        missingDirectories: [String] = [],
        dailyAggregations: [UsageDailyAggregation] = [],
        bucketsCache: [UsageBucketsCacheKey: UsageBucketsCacheEntry] = [:]
    ) {
        self.version = version
        self.resolvedEvents = resolvedEvents
        self.fileSignaturesBySource = fileSignaturesBySource
        self.sourceStates = sourceStates
        self.estimatedCostEventCount = estimatedCostEventCount
        self.unresolvedCostEventCount = unresolvedCostEventCount
        self.warnings = warnings
        self.missingDirectories = missingDirectories
        self.dailyAggregations = dailyAggregations
        self.bucketsCache = bucketsCache
    }

    public static var empty: UsageIncrementalState {
        var sourceStates: [UsageSource: UsageSourceRefreshState] = [:]
        for source in UsageSource.allCases {
            sourceStates[source] = UsageSourceRefreshState(source: source)
        }
        return UsageIncrementalState(sourceStates: sourceStates)
    }

    /// 按日期查找日聚合数据
    public func dailyAggregation(for date: Date, calendar: Calendar = .autoupdatingCurrent) -> UsageDailyAggregation? {
        let dayStart = calendar.startOfDay(for: date)
        return dailyAggregations.first { calendar.startOfDay(for: $0.date) == dayStart }
    }

    public func needsFullRefresh(
        for source: UsageSource,
        interval: UsageFullRefreshInterval,
        now: Date = Date()
    ) -> Bool {
        guard let state = sourceStates[source] else { return true }
        let hoursSinceFullRefresh = Calendar.current.dateComponents(
            [.hour],
            from: state.lastFullRefreshAt,
            to: now
        ).hour ?? 0
        return hoursSinceFullRefresh >= interval.hours
    }

    public func hasData(for source: UsageSource) -> Bool {
        guard let state = sourceStates[source] else { return false }
        return state.loadedFileCount > 0
    }

    public func fileSignatures(for source: UsageSource) -> [String: UsageFileSignature] {
        fileSignaturesBySource[source] ?? [:]
    }

    public mutating func updateSourceState(
        _ source: UsageSource,
        isFullRefresh: Bool,
        now: Date = Date(),
        loadedFileCount: Int? = nil
    ) {
        var state = sourceStates[source] ?? UsageSourceRefreshState(source: source)
        if isFullRefresh {
            state.lastFullRefreshAt = now
        }
        state.lastIncrementalRefreshAt = now
        if let count = loadedFileCount {
            state.loadedFileCount = count
        }
        sourceStates[source] = state
    }

    public mutating func setFileSignatures(_ signatures: [String: UsageFileSignature], for source: UsageSource) {
        fileSignaturesBySource[source] = signatures
    }

    /// 更新日聚合缓存
    public mutating func rebuildDailyAggregations(calendar: Calendar = .autoupdatingCurrent) {
        var totals: [Date: (tokens: Int, costUSD: Double)] = [:]

        for resolved in resolvedEvents {
            let day = calendar.startOfDay(for: resolved.event.timestamp)
            let current = totals[day] ?? (0, 0)
            totals[day] = (
                tokens: current.tokens + resolved.event.totalTokens,
                costUSD: current.costUSD + resolved.costUSD
            )
        }

        dailyAggregations = totals.map { date, metrics in
            UsageDailyAggregation(date: date, tokens: metrics.tokens, costUSD: metrics.costUSD)
        }.sorted { $0.date < $1.date }
    }
}