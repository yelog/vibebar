import Foundation

public enum UsageSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case claudeCode = "claude-code"
    case codex = "codex"
    case opencode = "opencode"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claudeCode:
            return "Claude Code"
        case .codex:
            return "Codex"
        case .opencode:
            return "OpenCode"
        }
    }
}

public enum UsageMetric: String, Codable, CaseIterable, Identifiable, Sendable {
    case tokens = "tokens"
    case costUSD = "cost_usd"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .tokens:
            return "Tokens"
        case .costUSD:
            return "Estimated USD"
        }
    }
}

public enum UsageVisualizationStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case githubHeatmap = "github_heatmap"
    case barChart = "bar_chart"
    case lineChart = "line_chart"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .githubHeatmap:
            return "Github"
        case .barChart:
            return "Bar"
        case .lineChart:
            return "Line"
        }
    }
}

public enum UsageGranularity: String, Codable, CaseIterable, Identifiable, Sendable {
    case day = "day"
    case week = "week"
    case month = "month"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .day:
            return "Day"
        case .week:
            return "Week"
        case .month:
            return "Month"
        }
    }
}

public enum UsageSeriesGrouping: String, Codable, CaseIterable, Identifiable, Sendable {
    case total = "total"
    case agent = "agent"
    case model = "model"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .total:
            return "Total"
        case .agent:
            return "Agent"
        case .model:
            return "Model"
        }
    }
}

public enum UsageRefreshCadence: Int, Codable, CaseIterable, Identifiable, Sendable {
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case thirtyMinutes = 1_800
    case oneHour = 3_600

    public var id: Int { rawValue }

    public var displayName: String {
        switch self {
        case .fiveMinutes:
            return "5 min"
        case .fifteenMinutes:
            return "15 min"
        case .thirtyMinutes:
            return "30 min"
        case .oneHour:
            return "1 hour"
        }
    }

    public var timeInterval: TimeInterval {
        TimeInterval(rawValue)
    }
}

public struct UsageDisplayConfiguration: Codable, Sendable, Equatable {
    public var sources: [UsageSource]
    public var refreshCadence: UsageRefreshCadence
    public var visualizationStyle: UsageVisualizationStyle
    public var metric: UsageMetric
    public var granularity: UsageGranularity
    public var seriesGrouping: UsageSeriesGrouping
    public var maxSeriesCount: Int

    public init(
        sources: [UsageSource] = UsageSource.allCases,
        refreshCadence: UsageRefreshCadence = .fiveMinutes,
        visualizationStyle: UsageVisualizationStyle = .githubHeatmap,
        metric: UsageMetric = .tokens,
        granularity: UsageGranularity = .day,
        seriesGrouping: UsageSeriesGrouping = .total,
        maxSeriesCount: Int = 6
    ) {
        self.sources = sources
        self.refreshCadence = refreshCadence
        self.visualizationStyle = visualizationStyle
        self.metric = metric
        self.granularity = granularity
        self.seriesGrouping = seriesGrouping
        self.maxSeriesCount = max(2, maxSeriesCount)
    }

    public static let `default` = UsageDisplayConfiguration()

    public var normalizedSources: [UsageSource] {
        let unique = Array(Set(sources))
        let resolved = unique.isEmpty ? UsageSource.allCases : unique
        return UsageSource.allCases.filter { resolved.contains($0) }
    }

    public var effectiveMetric: UsageMetric {
        metric
    }

    public var effectiveGranularity: UsageGranularity {
        switch visualizationStyle {
        case .githubHeatmap:
            return .day
        case .barChart, .lineChart:
            return granularity
        }
    }

    public func chartCutoffDate(from now: Date, calendar: Calendar) -> Date? {
        switch visualizationStyle {
        case .githubHeatmap:
            return nil
        case .barChart, .lineChart:
            switch granularity {
            case .day:
                return calendar.date(byAdding: .day, value: -10, to: now)
            case .week:
                return calendar.date(byAdding: .weekOfYear, value: -10, to: now)
            case .month:
                return calendar.date(byAdding: .month, value: -10, to: now)
            }
        }
    }
}

public struct UsageEvent: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var source: UsageSource
    public var sessionID: String
    public var timestamp: Date
    public var modelName: String
    public var inputTokens: Int
    public var outputTokens: Int
    public var cacheReadTokens: Int
    public var cacheWriteTokens: Int
    public var totalTokens: Int
    public var costUSD: Double?
    public var costIsEstimated: Bool
    public var costIsIncomplete: Bool

    public init(
        id: String,
        source: UsageSource,
        sessionID: String,
        timestamp: Date,
        modelName: String,
        inputTokens: Int,
        outputTokens: Int,
        cacheReadTokens: Int,
        cacheWriteTokens: Int,
        totalTokens: Int? = nil,
        costUSD: Double? = nil,
        costIsEstimated: Bool = false,
        costIsIncomplete: Bool = false
    ) {
        self.id = id
        self.source = source
        self.sessionID = sessionID
        self.timestamp = timestamp
        self.modelName = modelName
        self.inputTokens = max(0, inputTokens)
        self.outputTokens = max(0, outputTokens)
        self.cacheReadTokens = max(0, cacheReadTokens)
        self.cacheWriteTokens = max(0, cacheWriteTokens)
        self.totalTokens = max(
            0,
            totalTokens ?? inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens
        )
        self.costUSD = costUSD
        self.costIsEstimated = costIsEstimated
        self.costIsIncomplete = costIsIncomplete
    }
}

public struct UsageLoadResult: Sendable, Equatable {
    public var events: [UsageEvent]
    public var warnings: [String]
    public var missingDirectories: [String]

    public init(
        events: [UsageEvent] = [],
        warnings: [String] = [],
        missingDirectories: [String] = []
    ) {
        self.events = events
        self.warnings = warnings
        self.missingDirectories = missingDirectories
    }
}

public struct UsageModelPricing: Codable, Sendable, Equatable {
    public var inputCostPerMillion: Double
    public var cacheWriteCostPerMillion: Double
    public var cacheReadCostPerMillion: Double
    public var outputCostPerMillion: Double

    public init(
        inputCostPerMillion: Double,
        cacheWriteCostPerMillion: Double,
        cacheReadCostPerMillion: Double,
        outputCostPerMillion: Double
    ) {
        self.inputCostPerMillion = inputCostPerMillion
        self.cacheWriteCostPerMillion = cacheWriteCostPerMillion
        self.cacheReadCostPerMillion = cacheReadCostPerMillion
        self.outputCostPerMillion = outputCostPerMillion
    }
}

public struct UsageBreakdownItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var label: String
    public var tokens: Int
    public var costUSD: Double

    public init(id: String, label: String, tokens: Int, costUSD: Double) {
        self.id = id
        self.label = label
        self.tokens = max(0, tokens)
        self.costUSD = max(0, costUSD)
    }
}

public struct UsageBucket: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var label: String
    public var startDate: Date
    public var endDate: Date
    public var tokens: Int
    public var costUSD: Double
    public var breakdown: [UsageBreakdownItem]

    public init(
        id: String,
        label: String,
        startDate: Date,
        endDate: Date,
        tokens: Int,
        costUSD: Double,
        breakdown: [UsageBreakdownItem] = []
    ) {
        self.id = id
        self.label = label
        self.startDate = startDate
        self.endDate = endDate
        self.tokens = max(0, tokens)
        self.costUSD = max(0, costUSD)
        self.breakdown = breakdown
    }
}

public struct UsageSeriesPoint: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var bucketID: String
    public var bucketLabel: String
    public var date: Date
    public var tokens: Int
    public var costUSD: Double

    public init(
        id: String,
        bucketID: String,
        bucketLabel: String,
        date: Date,
        tokens: Int,
        costUSD: Double
    ) {
        self.id = id
        self.bucketID = bucketID
        self.bucketLabel = bucketLabel
        self.date = date
        self.tokens = max(0, tokens)
        self.costUSD = max(0, costUSD)
    }
}

public struct UsageSeries: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var label: String
    public var points: [UsageSeriesPoint]

    public init(id: String, label: String, points: [UsageSeriesPoint]) {
        self.id = id
        self.label = label
        self.points = points
    }
}

public struct UsageHeatmapCell: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var date: Date
    public var tokens: Int
    public var costUSD: Double
    public var intensity: Double

    public init(id: String, date: Date, tokens: Int, costUSD: Double, intensity: Double) {
        self.id = id
        self.date = date
        self.tokens = max(0, tokens)
        self.costUSD = max(0, costUSD)
        self.intensity = min(max(0, intensity), 1)
    }
}

public struct UsageSnapshot: Codable, Sendable, Equatable {
    public var updatedAt: Date
    public var configuration: UsageDisplayConfiguration
    public var totalTokens: Int
    public var totalCostUSD: Double
    public var buckets: [UsageBucket]
    public var series: [UsageSeries]
    public var heatmapCells: [UsageHeatmapCell]
    public var warnings: [String]
    public var missingDirectories: [String]
    public var estimatedCostEventCount: Int
    public var unresolvedCostEventCount: Int

    public init(
        updatedAt: Date,
        configuration: UsageDisplayConfiguration,
        totalTokens: Int,
        totalCostUSD: Double,
        buckets: [UsageBucket],
        series: [UsageSeries],
        heatmapCells: [UsageHeatmapCell],
        warnings: [String],
        missingDirectories: [String],
        estimatedCostEventCount: Int,
        unresolvedCostEventCount: Int
    ) {
        self.updatedAt = updatedAt
        self.configuration = configuration
        self.totalTokens = max(0, totalTokens)
        self.totalCostUSD = max(0, totalCostUSD)
        self.buckets = buckets
        self.series = series
        self.heatmapCells = heatmapCells
        self.warnings = warnings
        self.missingDirectories = missingDirectories
        self.estimatedCostEventCount = max(0, estimatedCostEventCount)
        self.unresolvedCostEventCount = max(0, unresolvedCostEventCount)
    }

    public static var empty: UsageSnapshot {
        empty(configuration: .default)
    }

    public static func empty(configuration: UsageDisplayConfiguration) -> UsageSnapshot {
        UsageSnapshot(
            updatedAt: .distantPast,
            configuration: configuration,
            totalTokens: 0,
            totalCostUSD: 0,
            buckets: [],
            series: [],
            heatmapCells: [],
            warnings: [],
            missingDirectories: [],
            estimatedCostEventCount: 0,
            unresolvedCostEventCount: 0
        )
    }
}
