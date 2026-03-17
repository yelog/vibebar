import Foundation

public enum UsageSource: String, Codable, CaseIterable, Identifiable, Sendable, Hashable {
    case claudeCode = "claude-code"
    case codex = "codex"
    case opencode = "opencode"
    case gemini = "gemini"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claudeCode:
            return "Claude Code"
        case .codex:
            return "Codex"
        case .opencode:
            return "OpenCode"
        case .gemini:
            return "Gemini CLI"
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
    case hour = "hour"
    case day = "day"
    case week = "week"
    case month = "month"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .hour:
            return "Hour"
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
    case project = "project"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .total:
            return "Total"
        case .agent:
            return "Agent"
        case .model:
            return "Model"
        case .project:
            return "Project"
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
        maxSeriesCount: Int = 8
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
            case .hour:
                return calendar.date(byAdding: .hour, value: -10, to: now)
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
    public var workingDirectory: String?

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
        costIsIncomplete: Bool = false,
        workingDirectory: String? = nil
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
        self.workingDirectory = workingDirectory
    }
}

public struct UsageLoadResult: Sendable, Equatable {
    public var events: [UsageEvent]
    public var warnings: [String]
    public var missingDirectories: [String]
    public var fileSignatures: [String: UsageFileSignature]

    public init(
        events: [UsageEvent] = [],
        warnings: [String] = [],
        missingDirectories: [String] = [],
        fileSignatures: [String: UsageFileSignature] = [:]
    ) {
        self.events = events
        self.warnings = warnings
        self.missingDirectories = missingDirectories
        self.fileSignatures = fileSignatures
    }
}

public enum PricingSource: String, Codable, Sendable {
    case bundled = "bundled"
    case cached = "cached"
    case remote = "remote"
}

public struct UsageModelPricing: Codable, Sendable, Equatable {
    public var inputCostPerMillion: Double
    public var cacheWriteCostPerMillion: Double
    public var cacheReadCostPerMillion: Double
    public var outputCostPerMillion: Double
    public var inputCostPerMillionAbove200k: Double?
    public var outputCostPerMillionAbove200k: Double?
    public var cacheWriteCostPerMillionAbove200k: Double?
    public var cacheReadCostPerMillionAbove200k: Double?
    public var maxInputTokens: Int?
    public var source: PricingSource?

    public init(
        inputCostPerMillion: Double,
        cacheWriteCostPerMillion: Double,
        cacheReadCostPerMillion: Double,
        outputCostPerMillion: Double,
        inputCostPerMillionAbove200k: Double? = nil,
        outputCostPerMillionAbove200k: Double? = nil,
        cacheWriteCostPerMillionAbove200k: Double? = nil,
        cacheReadCostPerMillionAbove200k: Double? = nil,
        maxInputTokens: Int? = nil,
        source: PricingSource? = nil
    ) {
        self.inputCostPerMillion = inputCostPerMillion
        self.cacheWriteCostPerMillion = cacheWriteCostPerMillion
        self.cacheReadCostPerMillion = cacheReadCostPerMillion
        self.outputCostPerMillion = outputCostPerMillion
        self.inputCostPerMillionAbove200k = inputCostPerMillionAbove200k
        self.outputCostPerMillionAbove200k = outputCostPerMillionAbove200k
        self.cacheWriteCostPerMillionAbove200k = cacheWriteCostPerMillionAbove200k
        self.cacheReadCostPerMillionAbove200k = cacheReadCostPerMillionAbove200k
        self.maxInputTokens = maxInputTokens
        self.source = source
    }
}

public struct LiteLLMModelPricing: Codable, Sendable {
    enum CodingKeys: String, CodingKey {
        case inputCostPerToken = "input_cost_per_token"
        case outputCostPerToken = "output_cost_per_token"
        case cacheCreationInputTokenCost = "cache_creation_input_token_cost"
        case cacheReadInputTokenCost = "cache_read_input_token_cost"
        case inputCostPerTokenAbove200k = "input_cost_per_token_above_200k_tokens"
        case outputCostPerTokenAbove200k = "output_cost_per_token_above_200k_tokens"
        case cacheCreationCostAbove200k = "cache_creation_input_token_cost_above_200k_tokens"
        case cacheReadCostAbove200k = "cache_read_input_token_cost_above_200k_tokens"
        case maxInputTokens = "max_input_tokens"
        case maxOutputTokens = "max_output_tokens"
        case litellmProvider = "litellm_provider"
    }

    public var inputCostPerToken: Double?
    public var outputCostPerToken: Double?
    public var cacheCreationInputTokenCost: Double?
    public var cacheReadInputTokenCost: Double?
    public var inputCostPerTokenAbove200k: Double?
    public var outputCostPerTokenAbove200k: Double?
    public var cacheCreationCostAbove200k: Double?
    public var cacheReadCostAbove200k: Double?
    public var maxInputTokens: Int?
    public var maxOutputTokens: Int?
    public var litellmProvider: String?

    public func toUsageModelPricing(source: PricingSource) -> UsageModelPricing {
        UsageModelPricing(
            inputCostPerMillion: (inputCostPerToken ?? 0) * 1_000_000,
            cacheWriteCostPerMillion: (cacheCreationInputTokenCost ?? inputCostPerToken ?? 0) * 1_000_000,
            cacheReadCostPerMillion: (cacheReadInputTokenCost ?? 0) * 1_000_000,
            outputCostPerMillion: (outputCostPerToken ?? 0) * 1_000_000,
            inputCostPerMillionAbove200k: inputCostPerTokenAbove200k.map { $0 * 1_000_000 },
            outputCostPerMillionAbove200k: outputCostPerTokenAbove200k.map { $0 * 1_000_000 },
            cacheWriteCostPerMillionAbove200k: cacheCreationCostAbove200k.map { $0 * 1_000_000 },
            cacheReadCostPerMillionAbove200k: cacheReadCostAbove200k.map { $0 * 1_000_000 },
            maxInputTokens: maxInputTokens,
            source: source
        )
    }
}

public struct PricingCacheMetadata: Codable, Sendable {
    public var version: Int
    public var lastUpdated: Date
    public var source: String
    public var modelCount: Int

    public static let currentVersion = 1

    public init(version: Int, lastUpdated: Date, source: String, modelCount: Int) {
        self.version = version
        self.lastUpdated = lastUpdated
        self.source = source
        self.modelCount = modelCount
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

/// 日聚合数据，用于快速生成热力图
public struct UsageDailyAggregation: Codable, Sendable, Equatable {
    public var date: Date
    public var tokens: Int
    public var costUSD: Double

    public init(date: Date, tokens: Int, costUSD: Double) {
        self.date = date
        self.tokens = max(0, tokens)
        self.costUSD = max(0, costUSD)
    }
}

/// Buckets 缓存的键，唯一标识一种配置组合
public struct UsageBucketsCacheKey: Codable, Sendable, Equatable, Hashable {
    public var granularity: UsageGranularity
    public var grouping: UsageSeriesGrouping
    public var sources: [UsageSource]

    public init(
        granularity: UsageGranularity,
        grouping: UsageSeriesGrouping,
        sources: [UsageSource]
    ) {
        self.granularity = granularity
        self.grouping = grouping
        self.sources = sources
    }

    public func matches(configuration: UsageDisplayConfiguration) -> Bool {
        configuration.effectiveGranularity == granularity &&
        configuration.seriesGrouping == grouping &&
        Set(configuration.normalizedSources) == Set(sources)
    }
}

/// Buckets 缓存条目
public struct UsageBucketsCacheEntry: Codable, Sendable, Equatable {
    public var key: UsageBucketsCacheKey
    public var buckets: [UsageBucket]
    public var cachedAt: Date

    public init(
        key: UsageBucketsCacheKey,
        buckets: [UsageBucket],
        cachedAt: Date = Date()
    ) {
        self.key = key
        self.buckets = buckets
        self.cachedAt = cachedAt
    }
}

public struct UsageSnapshot: Codable, Sendable, Equatable {
    public var updatedAt: Date
    public var loadDuration: TimeInterval?
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
        loadDuration: TimeInterval? = nil,
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
        self.loadDuration = loadDuration
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
            loadDuration: nil,
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

/// 加载请求参数，支持时间范围过滤
public struct UsageLoadRequest: Sendable {
    /// 起始日期（可选），只加载该日期之后的事件
    public let cutoffDate: Date?
    /// 缓冲天数，用于处理跨天会话文件
    public let bufferDays: Int

    public init(cutoffDate: Date?, bufferDays: Int = 1) {
        self.cutoffDate = cutoffDate
        self.bufferDays = bufferDays
    }

    /// 计算实际过滤日期（包含缓冲）
    public func effectiveCutoffDate(calendar: Calendar = .autoupdatingCurrent) -> Date? {
        guard let cutoffDate else { return nil }
        return calendar.date(byAdding: .day, value: -bufferDays, to: cutoffDate)
    }
}

/// Usage Loader 协议，统一各数据源的加载接口
public protocol UsageLoader: Sendable {
    /// 数据源类型
    var source: UsageSource { get }

    /// 加载使用数据，支持时间范围过滤
    /// - Parameter request: 加载请求参数，包含时间范围等
    /// - Returns: 加载结果
    func load(request: UsageLoadRequest) async throws -> UsageLoadResult
}
