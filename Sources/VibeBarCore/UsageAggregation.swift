import Foundation

public struct ResolvedUsageEvent: Sendable, Codable {
    public var event: UsageEvent
    public var costUSD: Double
    public var costIsEstimated: Bool
    public var costIsIncomplete: Bool
}

private final class CachedDateFormatters: @unchecked Sendable {
    private let lock = NSLock()
    private var cache: [String: DateFormatter] = [:]

    func formatter(for format: String) -> DateFormatter {
        lock.lock()
        defer { lock.unlock() }
        if let existing = cache[format] {
            return existing
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = format
        cache[format] = formatter
        return formatter
    }
}

private let sharedDateFormatters = CachedDateFormatters()

public struct UsageAggregator: Sendable {
    private struct BucketAccumulator {
        var startDate: Date
        var endDate: Date
        var label: String
        var tokens: Int = 0
        var costUSD: Double = 0
        var groupingValues: [String: (label: String, tokens: Int, costUSD: Double)] = [:]
    }

    private let pricingResolver: UsagePricingResolver
    private let calendarProvider: @Sendable () -> Calendar

    public init(
        pricingResolver: UsagePricingResolver = UsagePricingResolver(),
        calendarProvider: @escaping @Sendable () -> Calendar = {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .autoupdatingCurrent
            return calendar
        }
    ) {
        self.pricingResolver = pricingResolver
        self.calendarProvider = calendarProvider
    }

    public func resolveEvents(
        from loadResults: [UsageLoadResult],
        sources: [UsageSource]
    ) async -> (events: [ResolvedUsageEvent], estimatedCount: Int, unresolvedCount: Int) {
        let enabledSources = Set(sources)
        let mergedEvents = loadResults.flatMap(\.events)
            .filter { enabledSources.contains($0.source) }

        var resolvedEvents: [ResolvedUsageEvent] = []
        resolvedEvents.reserveCapacity(mergedEvents.count)
        var estimatedCount = 0
        var unresolvedCount = 0
        var pricingCache: [String: UsageModelPricing?] = [:]

        for event in mergedEvents {
            let normalizedModelName = pricingResolver.normalizedModelName(for: event.modelName)
            let pricing: UsageModelPricing?
            if let cached = pricingCache[normalizedModelName] {
                pricing = cached
            } else {
                let resolvedPricing = await pricingResolver.pricing(forNormalizedModelName: normalizedModelName)
                pricingCache[normalizedModelName] = resolvedPricing
                pricing = resolvedPricing
            }

            let resolved = pricingResolver.resolveCost(
                for: event,
                normalizedModelName: normalizedModelName,
                pricing: pricing
            )
            if resolved.costIsEstimated {
                estimatedCount += 1
            }
            if resolved.costIsIncomplete {
                unresolvedCount += 1
            }
            resolvedEvents.append(
                ResolvedUsageEvent(
                    event: resolved,
                    costUSD: resolved.costUSD ?? 0,
                    costIsEstimated: resolved.costIsEstimated,
                    costIsIncomplete: resolved.costIsIncomplete
                )
            )
        }

        return (resolvedEvents, estimatedCount, unresolvedCount)
    }

    public func buildSnapshot(
        from loadResults: [UsageLoadResult],
        configuration: UsageDisplayConfiguration,
        now: Date = Date()
    ) async -> UsageSnapshot {
        let (resolvedEvents, _, _) = await resolveEvents(
            from: loadResults,
            sources: configuration.normalizedSources
        )
        return buildSnapshotFromResolved(
            resolvedEvents: resolvedEvents,
            loadResults: loadResults,
            configuration: configuration,
            now: now
        )
    }

    public func buildSnapshotFromResolved(
        resolvedEvents: [ResolvedUsageEvent],
        loadResults: [UsageLoadResult],
        configuration: UsageDisplayConfiguration,
        now: Date = Date()
    ) -> UsageSnapshot {
        let (_, snapshot) = buildSnapshotFromResolved(
            resolvedEvents: resolvedEvents,
            loadResults: loadResults,
            configuration: configuration,
            dailyAggregations: nil,
            dailyAggregationsSources: nil,
            bucketsCache: [:],
            now: now
        )
        return snapshot
    }

    /// 从日聚合缓存构建快照，避免重复遍历所有事件
    public func buildSnapshotFromResolved(
        resolvedEvents: [ResolvedUsageEvent],
        loadResults: [UsageLoadResult],
        configuration: UsageDisplayConfiguration,
        dailyAggregations: [UsageDailyAggregation]?,
        now: Date = Date()
    ) -> UsageSnapshot {
        let (_, snapshot) = buildSnapshotFromResolved(
            resolvedEvents: resolvedEvents,
            loadResults: loadResults,
            configuration: configuration,
            dailyAggregations: dailyAggregations,
            dailyAggregationsSources: nil,
            bucketsCache: [:],
            now: now
        )
        return snapshot
    }

    /// 从缓存构建快照，支持 buckets 缓存，返回更新后的缓存
    /// - Parameter previousSnapshot: 之前的快照，用于保持时间和耗时（如果是缓存重建）
    /// - Parameter dailyAggregationsSources: dailyAggregations 对应的 sources，用于判断缓存是否可用
    /// - Parameter eventsUpdatedAt: resolvedEvents 最后更新时间，用于判断 buckets 缓存是否有效
    public func buildSnapshotFromResolved(
        resolvedEvents: [ResolvedUsageEvent],
        loadResults: [UsageLoadResult],
        configuration: UsageDisplayConfiguration,
        dailyAggregations: [UsageDailyAggregation]?,
        dailyAggregationsSources: [UsageSource]?,
        bucketsCache: [UsageBucketsCacheKey: UsageBucketsCacheEntry],
        previousSnapshot: UsageSnapshot? = nil,
        eventsUpdatedAt: Date? = nil,
        now: Date = Date()
    ) -> (updatedBucketsCache: [UsageBucketsCacheKey: UsageBucketsCacheEntry], snapshot: UsageSnapshot) {
        let calendar = calendarProvider()
        let enabledSources = Set(configuration.normalizedSources)
        let sourceFilteredEvents = resolvedEvents.filter { enabledSources.contains($0.event.source) }
        let cutoffDate = configuration.chartCutoffDate(from: now, calendar: calendar)
        let filteredEvents: [ResolvedUsageEvent]
        if let cutoff = cutoffDate {
            filteredEvents = sourceFilteredEvents.filter { $0.event.timestamp >= cutoff }
        } else {
            filteredEvents = sourceFilteredEvents
        }

        // 优先使用缓存生成热力图（无论是否需要 buckets，热力图总是需要的）
        // 但必须确保缓存只包含当前选中的 sources 的数据
        let heatmapCells: [UsageHeatmapCell]
        let heatmapStart = Date()
        let cacheSourcesSet = Set(dailyAggregationsSources ?? [])
        let canUseDailyAggregationsCache = dailyAggregations != nil && !dailyAggregations!.isEmpty && cacheSourcesSet == enabledSources
        if canUseDailyAggregationsCache {
            print("[UsageAggregation] using cached dailyAggregations (\(dailyAggregations!.count) days)")
            heatmapCells = makeHeatmapCellsFromCache(
                dailyAggregations: dailyAggregations!,
                now: now,
                calendar: calendar
            )
        } else {
            print("[UsageAggregation] building heatmap from \(sourceFilteredEvents.count) events (no cache or sources mismatch)")
            heatmapCells = makeHeatmapCells(from: sourceFilteredEvents, now: now, calendar: calendar)
        }
        print("[UsageAggregation] heatmap generation took \(Date().timeIntervalSince(heatmapStart))s")

        // 如果只需要热力图（github 样式），跳过 buckets 和 series 的昂贵计算
        var buckets: [UsageBucket] = []
        var series: [UsageSeries] = []
        var updatedBucketsCache = bucketsCache

        if configuration.visualizationStyle == .githubHeatmap {
            // 对于 github heatmap，使用空数组避免计算开销
            print("[UsageAggregation] skipping buckets/series for github heatmap")
        } else {
            // 尝试从 buckets 缓存获取
            let cacheKey = UsageBucketsCacheKey(
                granularity: configuration.effectiveGranularity,
                grouping: configuration.seriesGrouping,
                sources: configuration.normalizedSources
            )

            let bucketsStart = Date()
            if let cachedEntry = bucketsCache[cacheKey],
               isBucketsCacheValid(cachedEntry, granularity: configuration.effectiveGranularity, now: now, calendar: calendar, eventsUpdatedAt: eventsUpdatedAt) {
                print("[UsageAggregation] buckets cache hit for \(cacheKey)")
                buckets = cachedEntry.buckets
            } else {
                // 从原始事件计算（不再使用 dailyAggregations 缓存，因为它不按 sources 过滤）
                if configuration.seriesGrouping != .total {
                    print("[UsageAggregation] using makeBuckets for \(configuration.seriesGrouping) grouping")
                }
                buckets = makeBuckets(from: filteredEvents, configuration: configuration, calendar: calendar, now: now)
                // 存入缓存
                if !buckets.isEmpty {
                    updatedBucketsCache[cacheKey] = UsageBucketsCacheEntry(
                        key: cacheKey,
                        buckets: buckets,
                        cachedAt: now
                    )
                }
            }
            print("[UsageAggregation] makeBuckets took \(Date().timeIntervalSince(bucketsStart))s, buckets=\(buckets.count)")

            let seriesStart = Date()
            series = makeSeries(from: buckets, configuration: configuration, calendar: calendar)
            print("[UsageAggregation] makeSeries took \(Date().timeIntervalSince(seriesStart))s, series=\(series.count)")
        }

        let warnings = Array(
            Set(loadResults.flatMap(\.warnings) + unresolvedWarnings(from: sourceFilteredEvents))
        ).sorted()
        let missingDirectories = Array(Set(loadResults.flatMap(\.missingDirectories))).sorted()

        // 判断是否使用了缓存（buckets 来自缓存）
        let cacheKey = UsageBucketsCacheKey(
            granularity: configuration.effectiveGranularity,
            grouping: configuration.seriesGrouping,
            sources: configuration.normalizedSources
        )
        let usedCache = bucketsCache[cacheKey] != nil

        // 如果使用缓存，保持原来的时间和耗时；否则更新为当前时间
        let updatedAt: Date
        let loadDuration: TimeInterval?
        if usedCache, let previous = previousSnapshot {
            updatedAt = previous.updatedAt
            loadDuration = previous.loadDuration
            print("[UsageAggregation] using cache, preserving updatedAt and loadDuration")
        } else {
            updatedAt = now
            loadDuration = nil
        }

        let snapshot = UsageSnapshot(
            updatedAt: updatedAt,
            loadDuration: loadDuration,
            configuration: configuration,
            totalTokens: filteredEvents.reduce(0) { $0 + $1.event.totalTokens },
            totalCostUSD: filteredEvents.reduce(0) { $0 + $1.costUSD },
            buckets: buckets,
            series: series,
            heatmapCells: heatmapCells,
            warnings: warnings,
            missingDirectories: missingDirectories,
            estimatedCostEventCount: sourceFilteredEvents.filter(\.costIsEstimated).count,
            unresolvedCostEventCount: sourceFilteredEvents.filter(\.costIsIncomplete).count
        )

        return (updatedBucketsCache, snapshot)
    }

    private func unresolvedWarnings(from events: [ResolvedUsageEvent]) -> [String] {
        let unresolvedModels = Set(
            events
                .filter { $0.costIsIncomplete }
                .map { $0.event.modelName }
        )
        return unresolvedModels.sorted().map { "未找到模型价格，金额按 0 处理: \($0)" }
    }

    private func makeBuckets(
        from events: [ResolvedUsageEvent],
        configuration: UsageDisplayConfiguration,
        calendar: Calendar,
        now: Date
    ) -> [UsageBucket] {
        let granularity = configuration.effectiveGranularity
        let currentBucketStart = bucketStart(for: now, granularity: granularity, calendar: calendar)
        var accumulators: [String: BucketAccumulator] = [:]
        
        for offset in 0..<10 {
            guard let bucketStartDate = calendar.date(byAdding: bucketComponent(for: granularity), value: -offset, to: currentBucketStart) else { continue }
            let bucketEndDate = bucketEnd(for: bucketStartDate, granularity: granularity, calendar: calendar)
            let id = bucketID(for: bucketStartDate, granularity: granularity, calendar: calendar)
            let label = bucketLabel(for: bucketStartDate, granularity: granularity, calendar: calendar)
            accumulators[id] = BucketAccumulator(
                startDate: bucketStartDate,
                endDate: bucketEndDate,
                label: label
            )
        }

        for resolved in events {
            let bucketStartForEvent = bucketStart(for: resolved.event.timestamp, granularity: granularity, calendar: calendar)
            let bucketIDForEvent = bucketID(for: bucketStartForEvent, granularity: granularity, calendar: calendar)
            
            guard var accumulator = accumulators[bucketIDForEvent] else { continue }
            accumulator.tokens += resolved.event.totalTokens
            accumulator.costUSD += resolved.costUSD

            let groupingKey: String
            let groupingLabel: String
            switch configuration.seriesGrouping {
            case .total:
                groupingKey = "total"
                groupingLabel = "Total"
            case .agent:
                groupingKey = resolved.event.source.rawValue
                groupingLabel = resolved.event.source.displayName
            case .model:
                groupingKey = formatModelLabel(resolved.event.modelName)
                groupingLabel = formatModelLabel(resolved.event.modelName)
            case .project:
                let dir = resolved.event.workingDirectory
                groupingKey = dir ?? "unknown"
                groupingLabel = formatProjectLabel(dir)
            }

            let current = accumulator.groupingValues[groupingKey] ?? (groupingLabel, 0, 0)
            accumulator.groupingValues[groupingKey] = (
                label: groupingLabel,
                tokens: current.tokens + resolved.event.totalTokens,
                costUSD: current.costUSD + resolved.costUSD
            )

            accumulators[bucketIDForEvent] = accumulator
        }

        return accumulators
            .map { key, value -> UsageBucket in
                let breakdown = value.groupingValues
                    .map { groupKey, groupValue in
                        UsageBreakdownItem(
                            id: "\(key):\(groupKey)",
                            label: groupValue.label,
                            tokens: groupValue.tokens,
                            costUSD: groupValue.costUSD
                        )
                    }
                    .sorted { lhs, rhs in
                        compareMetric(tokens: lhs.tokens, cost: lhs.costUSD, rhsTokens: rhs.tokens, rhsCost: rhs.costUSD, metric: configuration.effectiveMetric)
                    }
                return UsageBucket(
                    id: key,
                    label: value.label,
                    startDate: value.startDate,
                    endDate: value.endDate,
                    tokens: value.tokens,
                    costUSD: value.costUSD,
                    breakdown: breakdown
                )
            }
            .sorted { $0.startDate < $1.startDate }
    }
    
    private func bucketComponent(for granularity: UsageGranularity) -> Calendar.Component {
        switch granularity {
        case .hour:
            return .hour
        case .day:
            return .day
        case .week:
            return .weekOfYear
        case .month:
            return .month
        }
    }

    private func makeSeries(
        from buckets: [UsageBucket],
        configuration: UsageDisplayConfiguration,
        calendar: Calendar
    ) -> [UsageSeries] {
        guard !buckets.isEmpty else { return [] }

        let allowedLabels: Set<String>
        switch configuration.seriesGrouping {
        case .total:
            allowedLabels = ["Total"]
        case .agent:
            allowedLabels = Set(configuration.normalizedSources.map(\.displayName))
        case .model, .project:
            var totals: [String: Double] = [:]
            for bucket in buckets {
                for item in bucket.breakdown {
                    let contribution = configuration.effectiveMetric == .tokens
                        ? Double(item.tokens)
                        : item.costUSD
                    totals[item.label, default: 0] += contribution
                }
            }

            let sortedLabels = totals
                .sorted { lhs, rhs in
                    if lhs.value == rhs.value {
                        return lhs.key < rhs.key
                    }
                    return lhs.value > rhs.value
                }
                .map(\.key)
            if sortedLabels.count > configuration.maxSeriesCount {
                let kept = sortedLabels.prefix(max(1, configuration.maxSeriesCount - 1))
                allowedLabels = Set(kept).union(["Others"])
            } else {
                allowedLabels = Set(sortedLabels)
            }
        }

        var seriesMap: [String: [UsageSeriesPoint]] = [:]
        var seriesLabels: [String: String] = [:]

        for bucket in buckets {
            var valuesByLabel: [String: (tokens: Int, costUSD: Double)] = [:]
            for item in bucket.breakdown {
                let rawLabel = item.label
                let label: String
                if (configuration.seriesGrouping == .model || configuration.seriesGrouping == .project) && !allowedLabels.contains(rawLabel) {
                    label = "Others"
                } else {
                    label = rawLabel
                }
                let current = valuesByLabel[label] ?? (0, 0)
                valuesByLabel[label] = (
                    tokens: current.tokens + item.tokens,
                    costUSD: current.costUSD + item.costUSD
                )
            }

            if configuration.seriesGrouping == .total {
                valuesByLabel = ["Total": (bucket.tokens, bucket.costUSD)]
            }

            for label in allowedLabels {
                let value = valuesByLabel[label] ?? (0, 0)
                let point = UsageSeriesPoint(
                    id: "\(label):\(bucket.id)",
                    bucketID: bucket.id,
                    bucketLabel: bucket.label,
                    date: bucket.startDate,
                    tokens: value.tokens,
                    costUSD: value.costUSD
                )
                seriesMap[label, default: []].append(point)
                seriesLabels[label] = label
            }
        }

        return seriesMap
            .map { label, points in
                UsageSeries(
                    id: label,
                    label: seriesLabels[label] ?? label,
                    points: points.sorted { $0.date < $1.date }
                )
            }
            .sorted { lhs, rhs in
                let lhsTotal = lhs.points.reduce(0.0) { partial, point in
                    partial + (configuration.effectiveMetric == .tokens ? Double(point.tokens) : point.costUSD)
                }
                let rhsTotal = rhs.points.reduce(0.0) { partial, point in
                    partial + (configuration.effectiveMetric == .tokens ? Double(point.tokens) : point.costUSD)
                }
                if lhsTotal == rhsTotal {
                    return lhs.label < rhs.label
                }
                return lhsTotal > rhsTotal
            }
    }

    private func makeHeatmapCells(
        from events: [ResolvedUsageEvent],
        now: Date,
        calendar: Calendar
    ) -> [UsageHeatmapCell] {
        let today = calendar.startOfDay(for: now)
        let dayRange = 39 * 7
        let startDate = calendar.date(byAdding: .day, value: -(dayRange - 1), to: today) ?? today

        var totals: [Date: (tokens: Int, costUSD: Double)] = [:]
        for resolved in events {
            let day = calendar.startOfDay(for: resolved.event.timestamp)
            guard day >= startDate && day <= today else { continue }
            let current = totals[day] ?? (0, 0)
            totals[day] = (
                tokens: current.tokens + resolved.event.totalTokens,
                costUSD: current.costUSD + resolved.costUSD
            )
        }

        let maxTokens = max(totals.values.map(\.tokens).max() ?? 0, 1)
        var cells: [UsageHeatmapCell] = []
        for offset in 0..<dayRange {
            let date = calendar.date(byAdding: .day, value: offset, to: startDate) ?? startDate
            let values = totals[date] ?? (0, 0)
            cells.append(
                UsageHeatmapCell(
                    id: heatmapCellID(for: date, calendar: calendar),
                    date: date,
                    tokens: values.tokens,
                    costUSD: values.costUSD,
                    intensity: Double(values.tokens) / Double(maxTokens)
                )
            )
        }
        return cells
    }

    /// 从日聚合缓存快速生成热力图
    public func makeHeatmapCellsFromCache(
        dailyAggregations: [UsageDailyAggregation],
        now: Date,
        calendar: Calendar
    ) -> [UsageHeatmapCell] {
        let today = calendar.startOfDay(for: now)
        let dayRange = 39 * 7
        let startDate = calendar.date(byAdding: .day, value: -(dayRange - 1), to: today) ?? today

        // 将聚合数据转换为字典，O(N) 但 N 是总天数（可能几年），比遍历所有事件快得多
        var totals: [Date: (tokens: Int, costUSD: Double)] = [:]
        for aggregation in dailyAggregations {
            let day = calendar.startOfDay(for: aggregation.date)
            guard day >= startDate && day <= today else { continue }
            totals[day] = (aggregation.tokens, aggregation.costUSD)
        }

        let maxTokens = max(totals.values.map(\.tokens).max() ?? 0, 1)
        var cells: [UsageHeatmapCell] = []
        for offset in 0..<dayRange {
            let date = calendar.date(byAdding: .day, value: offset, to: startDate) ?? startDate
            let values = totals[date] ?? (0, 0)
            cells.append(
                UsageHeatmapCell(
                    id: heatmapCellID(for: date, calendar: calendar),
                    date: date,
                    tokens: values.tokens,
                    costUSD: values.costUSD,
                    intensity: Double(values.tokens) / Double(maxTokens)
                )
            )
        }
        return cells
    }

    /// 从日聚合缓存快速生成桶数据，避免遍历所有事件
    public func makeBucketsFromCache(
        dailyAggregations: [UsageDailyAggregation],
        configuration: UsageDisplayConfiguration,
        cutoffDate: Date?,
        calendar: Calendar
    ) -> [UsageBucket] {
        let granularity = configuration.effectiveGranularity
        
        switch granularity {
        case .hour:
            return []
        case .day, .week, .month:
            break
        }
        
        let now = Date()
        let currentBucketStart = bucketStart(for: now, granularity: granularity, calendar: calendar)
        var accumulators: [String: BucketAccumulator] = [:]
        
        for offset in 0..<10 {
            guard let bucketStartDate = calendar.date(byAdding: bucketComponent(for: granularity), value: -offset, to: currentBucketStart) else { continue }
            let bucketEndDate = bucketEnd(for: bucketStartDate, granularity: granularity, calendar: calendar)
            let id = bucketID(for: bucketStartDate, granularity: granularity, calendar: calendar)
            let label = bucketLabel(for: bucketStartDate, granularity: granularity, calendar: calendar)
            accumulators[id] = BucketAccumulator(
                startDate: bucketStartDate,
                endDate: bucketEndDate,
                label: label
            )
        }

        for aggregation in dailyAggregations {
            let aggregationDay = calendar.startOfDay(for: aggregation.date)
            
            let start: Date
            let id: String

            switch granularity {
            case .hour:
                continue
            case .day:
                start = aggregationDay
                id = self.bucketID(for: start, granularity: .day, calendar: calendar)
            case .week:
                start = UsageLoaderSupport.weekStart(for: aggregation.date, calendar: calendar)
                id = self.bucketID(for: start, granularity: .week, calendar: calendar)
            case .month:
                let components = calendar.dateComponents([.year, .month], from: aggregation.date)
                start = calendar.date(from: components) ?? aggregationDay
                id = self.bucketID(for: start, granularity: .month, calendar: calendar)
            }

            guard var accumulator = accumulators[id] else { continue }
            accumulator.tokens += aggregation.tokens
            accumulator.costUSD += aggregation.costUSD
            accumulators[id] = accumulator
        }

        return accumulators
            .map { key, value -> UsageBucket in
                let breakdown = [
                    UsageBreakdownItem(
                        id: "\(key):total",
                        label: "Total",
                        tokens: value.tokens,
                        costUSD: value.costUSD
                    )
                ]
                return UsageBucket(
                    id: key,
                    label: value.label,
                    startDate: value.startDate,
                    endDate: value.endDate,
                    tokens: value.tokens,
                    costUSD: value.costUSD,
                    breakdown: breakdown
                )
            }
            .sorted { $0.startDate < $1.startDate }
    }

    private func bucketStart(for date: Date, granularity: UsageGranularity, calendar: Calendar) -> Date {
        switch granularity {
        case .hour:
            let components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
            return calendar.date(from: components) ?? date
        case .day:
            return calendar.startOfDay(for: date)
        case .week:
            return UsageLoaderSupport.weekStart(for: date, calendar: calendar)
        case .month:
            let components = calendar.dateComponents([.year, .month], from: date)
            return calendar.date(from: components) ?? calendar.startOfDay(for: date)
        }
    }

    private func bucketEnd(for startDate: Date, granularity: UsageGranularity, calendar: Calendar) -> Date {
        let component: Calendar.Component
        switch granularity {
        case .hour:
            component = .hour
        case .day:
            component = .day
        case .week:
            component = .weekOfYear
        case .month:
            component = .month
        }
        return calendar.date(byAdding: component, value: 1, to: startDate) ?? startDate
    }

    private func bucketID(for date: Date, granularity: UsageGranularity, calendar: Calendar) -> String {
        switch granularity {
        case .hour:
            return makeDateFormatter("yyyy-MM-dd HH:00").string(from: date)
        case .day:
            return makeDateFormatter("yyyy-MM-dd").string(from: date)
        case .week:
            let week = calendar.component(.weekOfYear, from: date)
            let year = calendar.component(.yearForWeekOfYear, from: date)
            return String(format: "%04d-W%02d", year, week)
        case .month:
            return makeDateFormatter("yyyy-MM").string(from: date)
        }
    }

    private func bucketLabel(for date: Date, granularity: UsageGranularity, calendar: Calendar) -> String {
        bucketID(for: date, granularity: granularity, calendar: calendar)
    }

    private func heatmapCellID(for date: Date, calendar: Calendar) -> String {
        makeDateFormatter("yyyy-MM-dd").string(from: calendar.startOfDay(for: date))
    }

    private func formatModelLabel(_ rawValue: String) -> String {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "unknown" }

        if value.hasPrefix("[pi] ") {
            value.removeFirst(5)
        }
        if let slashIndex = value.lastIndex(of: "/") {
            value = String(value[value.index(after: slashIndex)...])
        }
        if value.hasPrefix("claude-") {
            value = value.replacingOccurrences(of: "claude-", with: "")
        }
        if value.hasSuffix("-latest") {
            value = value.replacingOccurrences(of: "-latest", with: "")
        }
        let parts = value.split(separator: "-")
        if let last = parts.last, last.count == 8, last.allSatisfy(\.isNumber) {
            value = parts.dropLast().joined(separator: "-")
        }
        return value
    }

    private func formatProjectLabel(_ path: String?) -> String {
        guard let path, !path.isEmpty else { return "unknown" }
        let url = URL(fileURLWithPath: path)
        return url.lastPathComponent
    }

    private func compareMetric(
        tokens: Int,
        cost: Double,
        rhsTokens: Int,
        rhsCost: Double,
        metric: UsageMetric
    ) -> Bool {
        let lhsValue = metric == .tokens ? Double(tokens) : cost
        let rhsValue = metric == .tokens ? Double(rhsTokens) : rhsCost
        if lhsValue == rhsValue {
            return tokens > rhsTokens
        }
        return lhsValue > rhsValue
    }

    private func isBucketsCacheValid(
        _ entry: UsageBucketsCacheEntry,
        granularity: UsageGranularity,
        now: Date,
        calendar: Calendar,
        eventsUpdatedAt: Date? = nil
    ) -> Bool {
        let currentBucketStart = bucketStart(for: now, granularity: granularity, calendar: calendar)
        let currentBucketID = bucketID(for: currentBucketStart, granularity: granularity, calendar: calendar)
        guard entry.buckets.contains(where: { $0.id == currentBucketID }) else {
            return false
        }
        
        if let eventsUpdatedAt = eventsUpdatedAt {
            guard entry.cachedAt >= eventsUpdatedAt else {
                return false
            }
        }
        
        return true
    }

    private func makeDateFormatter(_ format: String) -> DateFormatter {
        sharedDateFormatters.formatter(for: format)
    }
}
