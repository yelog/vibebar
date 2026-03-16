import Foundation

public struct ResolvedUsageEvent: Sendable, Codable {
    public var event: UsageEvent
    public var costUSD: Double
    public var costIsEstimated: Bool
    public var costIsIncomplete: Bool
}

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
            bucketsCache: [:],
            now: now
        )
        return snapshot
    }

    /// 从缓存构建快照，支持 buckets 缓存，返回更新后的缓存
    public func buildSnapshotFromResolved(
        resolvedEvents: [ResolvedUsageEvent],
        loadResults: [UsageLoadResult],
        configuration: UsageDisplayConfiguration,
        dailyAggregations: [UsageDailyAggregation]?,
        bucketsCache: [UsageBucketsCacheKey: UsageBucketsCacheEntry],
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
        let heatmapCells: [UsageHeatmapCell]
        let heatmapStart = Date()
        if let aggregations = dailyAggregations, !aggregations.isEmpty {
            print("[UsageAggregation] using cached dailyAggregations (\(aggregations.count) days)")
            heatmapCells = makeHeatmapCellsFromCache(
                dailyAggregations: aggregations,
                now: now,
                calendar: calendar
            )
        } else {
            print("[UsageAggregation] building heatmap from \(sourceFilteredEvents.count) events (no cache)")
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
            if let cachedEntry = bucketsCache[cacheKey] {
                // 缓存命中！
                print("[UsageAggregation] buckets cache hit for \(cacheKey)")
                buckets = cachedEntry.buckets
            } else if let aggregations = dailyAggregations, !aggregations.isEmpty,
                      configuration.effectiveGranularity != .hour,
                      configuration.seriesGrouping == .total {
                // 从日聚合缓存快速生成（仅支持 total 分组）
                print("[UsageAggregation] using makeBucketsFromCache for \(configuration.effectiveGranularity)")
                buckets = makeBucketsFromCache(
                    dailyAggregations: aggregations,
                    configuration: configuration,
                    cutoffDate: cutoffDate,
                    calendar: calendar
                )
                // 存入缓存
                if !buckets.isEmpty {
                    updatedBucketsCache[cacheKey] = UsageBucketsCacheEntry(
                        key: cacheKey,
                        buckets: buckets,
                        cachedAt: now
                    )
                }
            } else {
                // 从原始事件计算
                if configuration.seriesGrouping != .total {
                    print("[UsageAggregation] using makeBuckets for \(configuration.seriesGrouping) grouping")
                }
                buckets = makeBuckets(from: filteredEvents, configuration: configuration, calendar: calendar)
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

        let snapshot = UsageSnapshot(
            updatedAt: now,
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
        calendar: Calendar
    ) -> [UsageBucket] {
        var accumulators: [String: BucketAccumulator] = [:]

        for resolved in events {
            let bucketStart = bucketStart(for: resolved.event.timestamp, granularity: configuration.effectiveGranularity, calendar: calendar)
            let bucketEnd = bucketEnd(for: bucketStart, granularity: configuration.effectiveGranularity, calendar: calendar)
            let bucketID = bucketID(for: bucketStart, granularity: configuration.effectiveGranularity, calendar: calendar)
            let label = bucketLabel(for: bucketStart, granularity: configuration.effectiveGranularity, calendar: calendar)
            var accumulator = accumulators[bucketID] ?? BucketAccumulator(
                startDate: bucketStart,
                endDate: bucketEnd,
                label: label
            )
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
            }

            let current = accumulator.groupingValues[groupingKey] ?? (groupingLabel, 0, 0)
            accumulator.groupingValues[groupingKey] = (
                label: groupingLabel,
                tokens: current.tokens + resolved.event.totalTokens,
                costUSD: current.costUSD + resolved.costUSD
            )

            accumulators[bucketID] = accumulator
        }

        let ordered = accumulators
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

        return ordered
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
        case .model:
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
                if configuration.seriesGrouping == .model && !allowedLabels.contains(rawLabel) {
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

        // 将日聚合数据按目标粒度分组
        var accumulators: [String: BucketAccumulator] = [:]

        for aggregation in dailyAggregations {
            // 应用 cutoff 过滤，只保留最近 10 个时间粒度的数据
            if let cutoff = cutoffDate {
                let day = calendar.startOfDay(for: aggregation.date)
                guard day >= cutoff else { continue }
            }

            let start: Date
            let end: Date
            let id: String
            let lbl: String

            switch granularity {
            case .hour:
                // Hour 粒度需要从原始事件计算，缓存无法提供小时级数据
                // 返回空数组，让调用方回退到原始方法
                return []
            case .day:
                start = calendar.startOfDay(for: aggregation.date)
                end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
                id = self.bucketID(for: start, granularity: .day, calendar: calendar)
                lbl = bucketLabel(for: start, granularity: .day, calendar: calendar)
            case .week:
                start = UsageLoaderSupport.weekStart(for: aggregation.date, calendar: calendar)
                end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) ?? start
                id = self.bucketID(for: start, granularity: .week, calendar: calendar)
                lbl = bucketLabel(for: start, granularity: .week, calendar: calendar)
            case .month:
                let components = calendar.dateComponents([.year, .month], from: aggregation.date)
                start = calendar.date(from: components) ?? calendar.startOfDay(for: aggregation.date)
                end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
                id = self.bucketID(for: start, granularity: .month, calendar: calendar)
                lbl = bucketLabel(for: start, granularity: .month, calendar: calendar)
            }

            var accumulator = accumulators[id] ?? BucketAccumulator(
                startDate: start,
                endDate: end,
                label: lbl
            )
            accumulator.tokens += aggregation.tokens
            accumulator.costUSD += aggregation.costUSD
            accumulators[id] = accumulator
        }

        // 转换为 UsageBucket 数组，并限制为最近 10 个
        let ordered = accumulators
            .map { key, value -> UsageBucket in
                // 对于从缓存生成的桶，我们没有 breakdown 数据
                // 返回简化的 breakdown（只有总计）
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

        // 只保留最近 10 个桶
        if ordered.count > 10 {
            return Array(ordered.suffix(10))
        }
        return ordered
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

    private func makeDateFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = format
        return formatter
    }
}
