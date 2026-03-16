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
    public static let currentVersion = 1

    public var version: Int
    public var resolvedEvents: [ResolvedUsageEvent]
    public var fileSignatures: [String: UsageFileSignature]
    public var sourceStates: [UsageSource: UsageSourceRefreshState]
    public var estimatedCostEventCount: Int
    public var unresolvedCostEventCount: Int
    public var warnings: [String]
    public var missingDirectories: [String]

    public init(
        version: Int = Self.currentVersion,
        resolvedEvents: [ResolvedUsageEvent] = [],
        fileSignatures: [String: UsageFileSignature] = [:],
        sourceStates: [UsageSource: UsageSourceRefreshState] = [:],
        estimatedCostEventCount: Int = 0,
        unresolvedCostEventCount: Int = 0,
        warnings: [String] = [],
        missingDirectories: [String] = []
    ) {
        self.version = version
        self.resolvedEvents = resolvedEvents
        self.fileSignatures = fileSignatures
        self.sourceStates = sourceStates
        self.estimatedCostEventCount = estimatedCostEventCount
        self.unresolvedCostEventCount = unresolvedCostEventCount
        self.warnings = warnings
        self.missingDirectories = missingDirectories
    }

    public static var empty: UsageIncrementalState {
        var sourceStates: [UsageSource: UsageSourceRefreshState] = [:]
        for source in UsageSource.allCases {
            sourceStates[source] = UsageSourceRefreshState(source: source)
        }
        return UsageIncrementalState(sourceStates: sourceStates)
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
}