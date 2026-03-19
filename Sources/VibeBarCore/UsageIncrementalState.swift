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
    public var lastFullRefreshDuration: TimeInterval?
    public var lastIncrementalRefreshDuration: TimeInterval?

    public init(
        source: UsageSource,
        lastFullRefreshAt: Date = .distantPast,
        lastIncrementalRefreshAt: Date = .distantPast,
        loadedFileCount: Int = 0,
        lastFullRefreshDuration: TimeInterval? = nil,
        lastIncrementalRefreshDuration: TimeInterval? = nil
    ) {
        self.source = source
        self.lastFullRefreshAt = lastFullRefreshAt
        self.lastIncrementalRefreshAt = lastIncrementalRefreshAt
        self.loadedFileCount = loadedFileCount
        self.lastFullRefreshDuration = lastFullRefreshDuration
        self.lastIncrementalRefreshDuration = lastIncrementalRefreshDuration
    }
}

public struct UsageIncrementalState: Codable, Sendable {
    public static let currentVersion = 8

    public var version: Int
    public var resolvedEvents: [ResolvedUsageEvent]
    public var fileSignaturesBySource: [UsageSource: [String: UsageFileSignature]]
    public var parserVersionBySource: [UsageSource: Int]
    public var sourceStates: [UsageSource: UsageSourceRefreshState]
    public var estimatedCostEventCount: Int
    public var unresolvedCostEventCount: Int
    public var warnings: [String]
    public var missingDirectories: [String]
    public var dailyAggregations: [UsageDailyAggregation]
    public var dailyAggregationsSources: [UsageSource]
    public var bucketsCache: [UsageBucketsCacheKey: UsageBucketsCacheEntry]
    public var globalLastFullRefreshAt: Date?
    public var globalLastFullRefreshDuration: TimeInterval?
    public var globalLastIncrementalRefreshAt: Date?
    public var globalLastIncrementalRefreshDuration: TimeInterval?
    public var resolvedEventsUpdatedAt: Date?

    public init(
        version: Int = Self.currentVersion,
        resolvedEvents: [ResolvedUsageEvent] = [],
        fileSignaturesBySource: [UsageSource: [String: UsageFileSignature]] = [:],
        parserVersionBySource: [UsageSource: Int] = [:],
        sourceStates: [UsageSource: UsageSourceRefreshState] = [:],
        estimatedCostEventCount: Int = 0,
        unresolvedCostEventCount: Int = 0,
        warnings: [String] = [],
        missingDirectories: [String] = [],
        dailyAggregations: [UsageDailyAggregation] = [],
        dailyAggregationsSources: [UsageSource] = [],
        bucketsCache: [UsageBucketsCacheKey: UsageBucketsCacheEntry] = [:],
        globalLastFullRefreshAt: Date? = nil,
        globalLastFullRefreshDuration: TimeInterval? = nil,
        globalLastIncrementalRefreshAt: Date? = nil,
        globalLastIncrementalRefreshDuration: TimeInterval? = nil,
        resolvedEventsUpdatedAt: Date? = nil
    ) {
        self.version = version
        self.resolvedEvents = resolvedEvents
        self.fileSignaturesBySource = fileSignaturesBySource
        self.parserVersionBySource = parserVersionBySource
        self.sourceStates = sourceStates
        self.estimatedCostEventCount = estimatedCostEventCount
        self.unresolvedCostEventCount = unresolvedCostEventCount
        self.warnings = warnings
        self.missingDirectories = missingDirectories
        self.dailyAggregations = dailyAggregations
        self.dailyAggregationsSources = dailyAggregationsSources
        self.bucketsCache = bucketsCache
        self.globalLastFullRefreshAt = globalLastFullRefreshAt
        self.globalLastFullRefreshDuration = globalLastFullRefreshDuration
        self.globalLastIncrementalRefreshAt = globalLastIncrementalRefreshAt
        self.globalLastIncrementalRefreshDuration = globalLastIncrementalRefreshDuration
        self.resolvedEventsUpdatedAt = resolvedEventsUpdatedAt
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

    public func parserVersion(for source: UsageSource) -> Int? {
        parserVersionBySource[source]
    }

    public func hasMatchingParserVersion(for source: UsageSource, version: Int) -> Bool {
        parserVersionBySource[source] == version
    }

    public mutating func updateSourceState(
        _ source: UsageSource,
        isFullRefresh: Bool,
        now: Date = Date(),
        loadedFileCount: Int? = nil,
        duration: TimeInterval? = nil
    ) {
        var state = sourceStates[source] ?? UsageSourceRefreshState(source: source)
        if isFullRefresh {
            state.lastFullRefreshAt = now
            if let duration = duration {
                state.lastFullRefreshDuration = duration
            }
        }
        state.lastIncrementalRefreshAt = now
        if let duration = duration {
            state.lastIncrementalRefreshDuration = duration
        }
        if let count = loadedFileCount {
            state.loadedFileCount = count
        }
        sourceStates[source] = state
    }

    public mutating func setFileSignatures(_ signatures: [String: UsageFileSignature], for source: UsageSource) {
        fileSignaturesBySource[source] = signatures
    }

    public mutating func setParserVersion(_ version: Int, for source: UsageSource) {
        parserVersionBySource[source] = version
    }

    /// 更新日聚合缓存
    public mutating func rebuildDailyAggregations(calendar: Calendar = .autoupdatingCurrent) {
        var totals: [Date: (tokens: Int, costUSD: Double)] = [:]
        var sourcesSet = Set<UsageSource>()

        for resolved in resolvedEvents {
            let day = calendar.startOfDay(for: resolved.event.timestamp)
            let current = totals[day] ?? (0, 0)
            totals[day] = (
                tokens: current.tokens + resolved.event.totalTokens,
                costUSD: current.costUSD + resolved.costUSD
            )
            sourcesSet.insert(resolved.event.source)
        }

        dailyAggregations = totals.map { date, metrics in
            UsageDailyAggregation(date: date, tokens: metrics.tokens, costUSD: metrics.costUSD)
        }.sorted { $0.date < $1.date }
        dailyAggregationsSources = Array(sourcesSet).sorted { $0.rawValue < $1.rawValue }
    }

    public mutating func invalidateBucketsCacheForCurrentBucket(now: Date, calendar: Calendar) {
        let today = calendar.startOfDay(for: now)
        var keysToRemove: [UsageBucketsCacheKey] = []
        
        for (key, entry) in bucketsCache {
            let hasCurrentBucket = entry.buckets.contains { bucket in
                let bucketDay = calendar.startOfDay(for: bucket.startDate)
                return bucketDay == today
            }
            if hasCurrentBucket {
                keysToRemove.append(key)
            }
        }
        
        for key in keysToRemove {
            bucketsCache.removeValue(forKey: key)
        }
    }
}
