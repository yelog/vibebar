import SwiftUI
import VibeBarCore

struct UsageMenuSectionView: View {
    let snapshot: UsageSnapshot
    let isRefreshing: Bool
    var isRebuilding: Bool = false
    var onChartHoverChange: ((UsageMenuChartHoverState?) -> Void)? = nil
    var action: (() -> Void)?
    var enableFooterTooltip: Bool = true
    var cardWidth: CGFloat = 420

    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var settings = AppSettings.shared
    @State private var hoveredBucketIndex: Int?
    @State private var isHoveringFooter = false
    @State private var chartPlotFrame: CGRect = .zero
    @State private var bucketFrames: [Int: CGRect] = [:]

    private let menuCardPadding: CGFloat = 12
    private let chartContainerPadding: CGFloat = 8
    private let heatmapContainerPadding: CGFloat = 8
    private let barPlotHeight: CGFloat = 72
    private let linePlotHeight: CGFloat = 84
    private let compactChartAxisHeight: CGFloat = 8
    private static let cardCoordinateSpaceName = "UsageMenuSectionView.card"

    private var compactBuckets: [UsageBucket] {
        snapshot.buckets
    }

    private var compactBucketIDs: Set<String> {
        Set(compactBuckets.map(\.id))
    }

    private var menuHeatmapCells: [UsageHeatmapCell] {
        snapshot.heatmapCells
    }

    private var compactSeries: [UsageSeries] {
        snapshot.series.map { series in
            UsageSeries(
                id: series.id,
                label: series.label,
                points: series.points.filter { compactBucketIDs.contains($0.bucketID) }
            )
        }
    }

    private var compactLegendEntries: [UsageSeriesLegendEntry] {
        UsageChartColorPalette.entries(for: compactSeries)
    }

    private var compactSeriesStyles: [String: UsageSeriesVisualStyle] {
        UsageChartColorPalette.styleMap(for: compactSeries)
    }

    private var hoveredBucket: UsageBucket? {
        guard let hoveredBucketIndex, compactBuckets.indices.contains(hoveredBucketIndex) else { return nil }
        return compactBuckets[hoveredBucketIndex]
    }

    private var hoveredTooltipContent: UsageChartTooltipContent? {
        guard let hoveredBucket else { return nil }
        return chartTooltipContent(for: hoveredBucket)
    }

    private var displayConfiguration: UsageDisplayConfiguration {
        settings.usageConfiguration
    }

    private var displayVisualizationStyle: UsageVisualizationStyle {
        displayConfiguration.visualizationStyle
    }

    private var displayMetric: UsageMetric {
        displayConfiguration.effectiveMetric
    }

    private var shouldShowSeriesLegend: Bool {
        snapshot.configuration.seriesGrouping != .total && !compactLegendEntries.isEmpty
    }

    private var compactDateRange: (start: Date, end: Date)? {
        guard let firstBucket = compactBuckets.first,
              let lastBucket = compactBuckets.last else { return nil }
        return (firstBucket.startDate, lastBucket.endDate)
    }

    private var displayedDateRange: (start: Date, end: Date)? {
        if displayVisualizationStyle == .githubHeatmap {
            guard let firstCell = menuHeatmapCells.first,
                  let lastCell = menuHeatmapCells.last else { return nil }
            let calendar = Calendar.autoupdatingCurrent
            let endDate = calendar.date(byAdding: .day, value: 1, to: lastCell.date) ?? lastCell.date
            return (firstCell.date, endDate)
        }
        return compactDateRange
    }

    private var heatmapGridAvailableWidth: CGFloat {
        cardWidth - (menuCardPadding * 2) - (heatmapContainerPadding * 2)
    }

    private var chartPlotWidth: CGFloat {
        cardWidth - (menuCardPadding * 2) - (chartContainerPadding * 2)
    }

    private var heatmapLayout: UsageHeatmapGridLayout {
        UsageHeatmapGridLayout.make(
            compact: true,
            columnCount: UsageHeatmapGridLayout.columnCount(for: menuHeatmapCells.count),
            availableWidth: heatmapGridAvailableWidth
        )
    }

    private var compactSeriesTotals: [(id: String, label: String, tokens: Int, costUSD: Double)] {
        compactSeries.map { series in
            let tokens = series.points.reduce(0) { $0 + $1.tokens }
            let costUSD = series.points.reduce(0.0) { $0 + $1.costUSD }
            return (series.id, series.label, tokens, costUSD)
        }
    }

    private var heatmapTheme: UsageHeatmapTheme {
        UsageHeatmapTheme.make(for: colorScheme)
    }

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    cardContent
                }
                .buttonStyle(.plain)
                .focusable(false)
            } else {
                cardContent
            }
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            content
            footer
        }
        .padding(menuCardPadding)
        .frame(width: cardWidth, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .coordinateSpace(name: Self.cardCoordinateSpaceName)
        .onPreferenceChange(UsageMenuChartPlotFramePreferenceKey.self) { frame in
            chartPlotFrame = frame
            notifyChartHoverChangeIfNeeded()
        }
        .onPreferenceChange(UsageMenuBucketFramePreferenceKey.self) { frames in
            bucketFrames = frames
            notifyChartHoverChangeIfNeeded()
        }
        .onChange(of: hoveredBucketIndex) { _ in
            notifyChartHoverChangeIfNeeded()
        }
        .onChange(of: displayVisualizationStyle) { _ in
            notifyChartHoverChangeIfNeeded()
        }
        .onDisappear {
            onChartHoverChange?(nil)
        }
    }

    private var isPreviewMode: Bool {
        action == nil
    }

    private var usesDetachedChartTooltip: Bool {
        onChartHoverChange != nil
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(l10n.string(.usageTitle))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(configurationSummary)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Only show time indicators when NOT in preview mode
            if !isPreviewMode {
                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 9, weight: .medium))
                        Text(updatedTimeText)
                            .font(.system(size: 10))

                        if snapshot.loadDuration != nil {
                            Text("·")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                            Image(systemName: "stopwatch")
                                .font(.system(size: 9, weight: .medium))
                            Text(loadDurationText)
                                .font(.system(size: 10))
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isRebuilding {
            chartLoadingView
        } else if hasNoData {
            Text(l10n.string(.usageNoData))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 72, alignment: .center)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
        } else {
            switch displayVisualizationStyle {
            case .githubHeatmap:
                heatmapView
            case .barChart:
                barChartView
            case .lineChart:
                lineChartView
            }
        }
    }

    private var hasNoData: Bool {
        switch displayVisualizationStyle {
        case .githubHeatmap:
            return snapshot.heatmapCells.isEmpty
        case .barChart, .lineChart:
            return snapshot.buckets.isEmpty
        }
    }

    private var chartLoadingView: some View {
        VStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(l10n.string(.usageUpdating))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(primaryValueText)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)

            if let dateRange = displayedDateRange {
                Text(dateRangeText(dateRange))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            if displayMetric == .costUSD {
                Text(l10n.string(.usageEstimatedCostHint))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { isHovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHoveringFooter = isHovering
            }
        }
        .overlay(alignment: .topLeading) {
            if enableFooterTooltip && isHoveringFooter {
                if snapshot.configuration.seriesGrouping == .total {
                    totalTokenTooltip
                        .offset(y: -totalTooltipHeight - 4)
                        .transition(.opacity)
                } else if !compactSeriesTotals.isEmpty {
                    footerBreakdownTooltip
                        .offset(y: -footerBreakdownHeight - 4)
                        .transition(.opacity)
                }
            }
        }
    }

    private var totalTooltipHeight: CGFloat {
        25
    }

    private var totalTokenTooltip: some View {
        UsageTooltipBubbleView(compact: true) {
            Text(totalTooltipText)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
    }

    private var totalTooltipText: String {
        switch displayMetric {
        case .tokens:
            return "\(snapshot.totalTokens.formatted()) tokens"
        case .costUSD:
            return String(format: "$%.4f", snapshot.totalCostUSD)
        }
    }

    private var footerBreakdownHeight: CGFloat {
        CGFloat(compactSeriesTotals.count) * 17 + 8
    }

    private var footerBreakdownTooltip: some View {
        UsageTooltipBubbleView(compact: true) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(compactSeriesTotals.enumerated()), id: \.offset) { index, item in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(visualStyle(forSeriesID: item.id).color)
                            .frame(width: 5, height: 5)

                        Text(item.label)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.92))
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        Text(footerBreakdownValue(tokens: item.tokens, costUSD: item.costUSD))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private func footerBreakdownValue(tokens: Int, costUSD: Double) -> String {
        switch displayMetric {
        case .tokens:
            return UsageTokenFormatter.tooltipTokenText(tokens)
        case .costUSD:
            return String(format: "$%.4f", costUSD)
        }
    }

    private func dateRangeText(_ range: (start: Date, end: Date)) -> String {
        let calendar = Calendar.autoupdatingCurrent
        let inclusiveEnd = calendar.date(byAdding: .day, value: -1, to: range.end) ?? range.end

        let startText = formattedDate(range.start, format: "MMM d")
        let endText = formattedDate(inclusiveEnd, format: "MMM d")

        return "\(startText) - \(endText)"
    }

    private var heatmapView: some View {
        UsageHeatmapGridView(
            cells: menuHeatmapCells,
            compact: true,
            metric: displayMetric,
            availableWidth: heatmapGridAvailableWidth
        )
            .id(displayMetric)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: heatmapLayout.gridHeight(rowCount: 7))
            .padding(heatmapContainerPadding)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(heatmapTheme.surfaceFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(heatmapTheme.surfaceStroke, lineWidth: 1)
            )
    }

    private var barChartView: some View {
        // 计算所有 bucket 的最大值，用于动态调整柱子高度
        let maxBucketValue = max(
            compactBuckets.map { metricValue(for: $0) }.max() ?? 0,
            1
        )
        
        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                let barWidth = bucketBarWidth(containerWidth: proxy.size.width)

                ZStack(alignment: .topLeading) {
                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(Array(compactBuckets.enumerated()), id: \.element.id) { index, bucket in
                            let bucketValue = metricValue(for: bucket)
                            // 根据最大值动态调整柱子高度
                            let bucketHeight = max(4, barPlotHeight * (bucketValue / maxBucketValue))
                            
                            VStack {
                                Spacer(minLength: 0)

                                ZStack(alignment: .bottom) {
                                    Capsule()
                                        .fill(Color.primary.opacity(0.08))
                                        .frame(width: barWidth, height: bucketHeight)

                                    VStack(spacing: 0) {
                                        ForEach(seriesSegments(for: bucket, totalHeight: bucketHeight)) { segment in
                                            Rectangle()
                                                .fill(segment.color)
                                                .frame(width: barWidth, height: max(2, bucketHeight * segment.fraction))
                                        }
                                    }
                                    .frame(width: barWidth, height: bucketHeight, alignment: .bottom)
                                    .clipShape(
                                        RoundedRectangle(
                                            cornerRadius: barWidth / 2,
                                            style: .continuous
                                        )
                                    )
                                }
                                .frame(width: barWidth, height: bucketHeight)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        }
                    }

                    bucketHoverOverlay
                }
                .onHover { isHovering in
                    if !isHovering {
                        hoveredBucketIndex = nil
                    }
                }
            }
            .frame(height: barPlotHeight)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: UsageMenuChartPlotFramePreferenceKey.self,
                        value: proxy.frame(in: .named(Self.cardCoordinateSpaceName))
                    )
                }
            )

            UsageCompactChartAxisView(
                bucketCount: compactBuckets.count,
                activeIndex: hoveredBucketIndex
            )
            .frame(height: compactChartAxisHeight)

            if shouldShowSeriesLegend {
                UsageSeriesLegendView(entries: compactLegendEntries, compact: true)
            }
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .topLeading) {
            if !usesDetachedChartTooltip {
                chartTooltipOverlay(
                    containerWidth: chartPlotWidth,
                    containerHeight: barPlotHeight
                )
            }
        }
        .padding(chartContainerPadding)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private var lineChartView: some View {
        let maxValue = max(
            compactSeries.flatMap(\.points).map(metricValue(for:)).max() ?? 0,
            1
        )

        return VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    ForEach(Array(compactSeries.enumerated()), id: \.offset) { index, series in
                        let points = compactPoints(for: series)
                        let style = visualStyle(for: series)
                        Path { path in
                            for (pointIndex, point) in points.enumerated() {
                                let x = bucketCenterX(
                                    for: pointIndex,
                                    containerWidth: proxy.size.width,
                                    bucketCount: compactBuckets.count
                                )
                                let y = lineY(
                                    for: metricValue(for: point),
                                    maxValue: maxValue
                                )
                                if pointIndex == 0 {
                                    path.move(to: CGPoint(x: x, y: y))
                                } else {
                                    path.addLine(to: CGPoint(x: x, y: y))
                                }
                            }
                        }
                        .stroke(style.color, style: style.strokeStyle(lineWidth: 2))

                        ForEach(Array(points.enumerated()), id: \.element.id) { pointIndex, point in
                            Circle()
                                .fill(style.color)
                                .frame(width: 5, height: 5)
                                .position(
                                    x: bucketCenterX(
                                        for: pointIndex,
                                        containerWidth: proxy.size.width,
                                        bucketCount: compactBuckets.count
                                    ),
                                    y: lineY(
                                        for: metricValue(for: point),
                                        maxValue: maxValue
                                    )
                                )
                        }
                    }

                    bucketHoverOverlay
                }
                .onHover { isHovering in
                    if !isHovering {
                        hoveredBucketIndex = nil
                    }
                }
            }
            .frame(height: linePlotHeight)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: UsageMenuChartPlotFramePreferenceKey.self,
                        value: proxy.frame(in: .named(Self.cardCoordinateSpaceName))
                    )
                }
            )

            UsageCompactChartAxisView(
                bucketCount: compactBuckets.count,
                activeIndex: hoveredBucketIndex
            )
            .frame(height: 12)

            if shouldShowSeriesLegend {
                UsageSeriesLegendView(entries: compactLegendEntries, compact: true, variant: .line)
            }
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .topLeading) {
            if !usesDetachedChartTooltip {
                chartTooltipOverlay(
                    containerWidth: chartPlotWidth,
                    containerHeight: linePlotHeight
                )
            }
        }
        .padding(chartContainerPadding)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private var bucketHoverOverlay: some View {
        HStack(spacing: 0) {
            ForEach(compactBuckets.indices, id: \.self) { index in
                Rectangle()
                    .fill(Color.clear)
                    .overlay {
                        if index == hoveredBucketIndex {
                            GeometryReader { proxy in
                                Path { path in
                                    let centerX = proxy.size.width / 2
                                    path.move(to: CGPoint(x: centerX, y: 0))
                                    path.addLine(to: CGPoint(x: centerX, y: proxy.size.height))
                                }
                                .stroke(
                                    Color.accentColor.opacity(0.55),
                                    style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                                )
                            }
                        }
                    }
                    .contentShape(Rectangle())
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: UsageMenuBucketFramePreferenceKey.self,
                                value: [index: proxy.frame(in: .named(Self.cardCoordinateSpaceName))]
                            )
                        }
                    )
                    .onHover { isHovering in
                        updateHoveredBucket(index: index, isHovering: isHovering)
                    }
            }
        }
    }

    private func compactPoints(for series: UsageSeries) -> [UsageSeriesPoint] {
        compactBuckets.compactMap { bucket in
            series.points.first(where: { $0.bucketID == bucket.id })
        }
    }

    private func seriesSegments(for bucket: UsageBucket, totalHeight: CGFloat? = nil) -> [UsageMenuBarSegment] {
        let totalValue = max(metricValue(for: bucket), 1)

        var items: [UsageMenuBarSegment] = []
        for series in compactSeries {
            guard let point = series.points.first(where: { $0.bucketID == bucket.id }) else { continue }
            let value = metricValue(for: point)
            guard value > 0 else { continue }
            items.append(UsageMenuBarSegment(
                id: "\(bucket.id):\(series.id)",
                fraction: value / totalValue,
                color: visualStyle(for: series).color
            ))
        }

        if items.isEmpty {
            return [
                UsageMenuBarSegment(
                    id: "\(bucket.id):empty",
                    fraction: 0.02,
                    color: Color.primary.opacity(0.08)
                ),
            ]
        }
        return items
    }

    private func metricValue(for bucket: UsageBucket) -> Double {
        displayMetric == .tokens ? Double(bucket.tokens) : bucket.costUSD
    }

    private func metricValue(for point: UsageSeriesPoint) -> Double {
        displayMetric == .tokens ? Double(point.tokens) : point.costUSD
    }

    private func formattedMetricValue(tokens: Int, costUSD: Double) -> String {
        switch displayMetric {
        case .tokens:
            return UsageTokenFormatter.tooltipTokenText(tokens)
        case .costUSD:
            return String(format: "$%.4f", costUSD)
        }
    }

    private func bucketPeriodText(_ bucket: UsageBucket) -> String {
        let calendar = Calendar.autoupdatingCurrent
        switch snapshot.configuration.effectiveGranularity {
        case .hour:
            return formattedDate(bucket.startDate, format: "HH:mm")
        case .day:
            return formattedDate(bucket.startDate, format: "MMMM d")
        case .week:
            let inclusiveEnd = calendar.date(byAdding: .day, value: -1, to: bucket.endDate) ?? bucket.endDate
            let startText = formattedDate(bucket.startDate, format: "MMM d")
            let endText = formattedDate(inclusiveEnd, format: "MMM d")
            return "\(startText) - \(endText)"
        case .month:
            return formattedDate(bucket.startDate, format: "MMMM yyyy")
        }
    }

    private func chartTooltipContent(for bucket: UsageBucket) -> UsageChartTooltipContent {
        let title = "\(formattedMetricValue(tokens: bucket.tokens, costUSD: bucket.costUSD)) on \(bucketPeriodText(bucket))"

        guard snapshot.configuration.seriesGrouping != .total else {
            return UsageChartTooltipContent(title: title, lines: [])
        }

        let lines = compactSeries.map { series in
            let point = series.points.first(where: { $0.bucketID == bucket.id })
            return UsageChartTooltipLine(
                id: "\(bucket.id):\(series.id)",
                label: series.label,
                value: formattedMetricValue(tokens: point?.tokens ?? 0, costUSD: point?.costUSD ?? 0),
                color: visualStyle(for: series).color,
                sortValue: point.map { metricValue(for: $0) } ?? 0
            )
        }.sorted { $0.sortValue > $1.sortValue }

        return UsageChartTooltipContent(title: title, lines: lines)
    }

    private func formattedDate(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    private func visualStyle(for series: UsageSeries) -> UsageSeriesVisualStyle {
        compactSeriesStyles[series.id] ?? UsageSeriesVisualStyle(color: .accentColor, dashPattern: [])
    }

    private func visualStyle(forSeriesID seriesID: String) -> UsageSeriesVisualStyle {
        compactSeriesStyles[seriesID] ?? UsageSeriesVisualStyle(color: .accentColor, dashPattern: [])
    }

    private func bucketBarWidth(containerWidth: CGFloat) -> CGFloat {
        let bucketCount = max(compactBuckets.count, 1)
        let stepWidth = containerWidth / CGFloat(bucketCount)
        return min(14, max(8, stepWidth * 0.52))
    }

    private func bucketCenterX(for bucketIndex: Int, containerWidth: CGFloat, bucketCount: Int) -> CGFloat {
        guard bucketCount > 0 else { return 0 }
        let stepWidth = containerWidth / CGFloat(bucketCount)
        return stepWidth * (CGFloat(bucketIndex) + 0.5)
    }

    private func tooltipOffsetX(containerWidth: CGFloat, bucketIndex: Int, estimatedWidth: CGFloat) -> CGFloat {
        let anchorX = bucketCenterX(
            for: bucketIndex,
            containerWidth: containerWidth,
            bucketCount: compactBuckets.count
        )
        let proposedX = anchorX - (estimatedWidth / 2)
        return min(
            max(0, proposedX),
            max(0, containerWidth - estimatedWidth)
        )
    }

    private func floatingTooltipOffsetY(containerHeight: CGFloat, estimatedHeight: CGFloat) -> CGFloat {
        -estimatedHeight - 8
    }

    @ViewBuilder
    private func chartTooltipOverlay(containerWidth: CGFloat, containerHeight: CGFloat) -> some View {
        if let hoveredBucketIndex, let hoveredTooltipContent {
            UsageChartTooltipView(content: hoveredTooltipContent)
                .offset(
                    x: tooltipOffsetX(
                        containerWidth: containerWidth,
                        bucketIndex: hoveredBucketIndex,
                        estimatedWidth: hoveredTooltipContent.estimatedWidth
                    ),
                    y: floatingTooltipOffsetY(
                        containerHeight: containerHeight,
                        estimatedHeight: hoveredTooltipContent.estimatedHeight
                    )
                )
                .zIndex(1)
                .allowsHitTesting(false)
        }
    }

    private func lineY(for value: Double, maxValue: Double) -> CGFloat {
        guard maxValue > 0 else { return linePlotHeight }
        let normalized = min(max(value / maxValue, 0), 1)
        return linePlotHeight - (linePlotHeight * normalized)
    }

    private func updateHoveredBucket(index: Int, isHovering: Bool) {
        if isHovering {
            hoveredBucketIndex = index
        } else if hoveredBucketIndex == index {
            hoveredBucketIndex = nil
        }
    }

    private func notifyChartHoverChangeIfNeeded() {
        guard let onChartHoverChange else { return }
        guard displayVisualizationStyle == .barChart || displayVisualizationStyle == .lineChart else {
            onChartHoverChange(nil)
            return
        }
        guard let hoveredBucketIndex,
              let hoveredTooltipContent,
              let bucketFrame = bucketFrames[hoveredBucketIndex],
              !chartPlotFrame.isEmpty else {
            onChartHoverChange(nil)
            return
        }

        onChartHoverChange(
            UsageMenuChartHoverState(
                bucketFrame: bucketFrame,
                chartFrame: chartPlotFrame,
                content: hoveredTooltipContent
            )
        )
    }

    private var configurationSummary: String {
        [
            displayVisualizationStyle.displayName,
            displayMetric.displayName,
            snapshot.configuration.effectiveGranularity.displayName,
        ].joined(separator: " · ")
    }

    private var updatedTimeText: String {
        guard snapshot.updatedAt > .distantPast else { return "--" }
        let interval = Date().timeIntervalSince(snapshot.updatedAt)
        return formatRelativeTime(interval)
    }

    private var loadDurationText: String {
        guard let duration = snapshot.loadDuration else { return "" }
        return formatDuration(duration)
    }

    private func formatRelativeTime(_ interval: TimeInterval) -> String {
        if interval < 60 {
            return String(format: "%.0fs ago", interval)
        } else if interval < 3600 {
            return String(format: "%.0fm ago", interval / 60)
        } else if interval < 86400 {
            return String(format: "%.1fh ago", interval / 3600)
        } else {
            return String(format: "%.1fd ago", interval / 86400)
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 1 {
            return String(format: "%.0fms", duration * 1000)
        } else if duration < 60 {
            return String(format: "%.1fs", duration)
        } else {
            return String(format: "%.1fm", duration / 60)
        }
    }

    private var primaryValueText: String {
        switch displayMetric {
        case .tokens:
            return UsageTokenFormatter.footerTokenText(snapshot.totalTokens)
        case .costUSD:
            return String(format: "$%.4f", snapshot.totalCostUSD)
        }
    }
}

private struct UsageCompactChartAxisView: View {
    let bucketCount: Int
    let activeIndex: Int?

    private let baselineY: CGFloat = 3

    var body: some View {
        GeometryReader { proxy in
            let startX = axisX(for: 0, width: proxy.size.width)
            let endX = axisX(for: max(bucketCount - 1, 0), width: proxy.size.width)

            ZStack(alignment: .topLeading) {
                Path { path in
                    path.move(to: CGPoint(x: startX, y: baselineY))
                    path.addLine(to: CGPoint(x: endX, y: baselineY))
                }
                .stroke(Color.primary.opacity(0.16), lineWidth: 1)

                ForEach(0..<bucketCount, id: \.self) { index in
                    Circle()
                        .fill(index == activeIndex ? Color.accentColor : Color.primary.opacity(0.18))
                        .frame(width: index == activeIndex ? 5 : 4, height: index == activeIndex ? 5 : 4)
                        .position(x: axisX(for: index, width: proxy.size.width), y: baselineY)
                }
            }
        }
    }

    private func axisX(for index: Int, width: CGFloat) -> CGFloat {
        guard bucketCount > 0 else { return width / 2 }
        let stepWidth = width / CGFloat(bucketCount)
        return stepWidth * (CGFloat(index) + 0.5)
    }
}

struct UsageMenuChartHoverState {
    var bucketFrame: CGRect
    var chartFrame: CGRect
    var content: UsageChartTooltipContent
}

private struct UsageMenuChartPlotFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect { .zero }

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if !next.isEmpty {
            value = next
        }
    }
}

private struct UsageMenuBucketFramePreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] { [:] }

    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct UsageChartTooltipContent {
    var title: String
    var lines: [UsageChartTooltipLine]

    private static let compactVerticalPadding: CGFloat = 12
    private static let titleLineHeight: CGFloat = 12
    private static let titleToLinesSpacing: CGFloat = 6
    private static let detailLineHeight: CGFloat = 12
    private static let detailLineSpacing: CGFloat = 4
    private static let tooltipBottomGap: CGFloat = 6

    var estimatedWidth: CGFloat {
        let detailWidth = lines.map { $0.label.count + $0.value.count + 6 }.max() ?? 0
        let characterCount = max(title.count, detailWidth)
        return min(max(CGFloat(characterCount) * 6 + 28, 140), 250)
    }

    var estimatedHeight: CGFloat {
        Self.reservedTopInset(forLineCount: lines.count) - Self.tooltipBottomGap
    }

    static func reservedTopInset(forLineCount lineCount: Int) -> CGFloat {
        let detailSectionHeight: CGFloat
        if lineCount > 0 {
            detailSectionHeight =
                titleToLinesSpacing +
                (detailLineHeight * CGFloat(lineCount)) +
                (detailLineSpacing * CGFloat(max(lineCount - 1, 0)))
        } else {
            detailSectionHeight = 0
        }

        return compactVerticalPadding + titleLineHeight + detailSectionHeight + tooltipBottomGap
    }
}

struct UsageChartTooltipLine: Identifiable {
    var id: String
    var label: String
    var value: String
    var color: Color
    var sortValue: Double = 0
}

struct UsageChartTooltipView: View {
    let content: UsageChartTooltipContent

    var body: some View {
        UsageTooltipBubbleView(compact: true) {
            VStack(alignment: .leading, spacing: content.lines.isEmpty ? 0 : 6) {
                Text(content.title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if !content.lines.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(content.lines) { line in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(line.color)
                                    .frame(width: 5, height: 5)

                                Text(line.label)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.92))
                                    .lineLimit(1)

                                Spacer(minLength: 8)

                                Text(line.value)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            .frame(width: content.estimatedWidth, alignment: .leading)
        }
    }
}

private struct UsageMenuBarSegment: Identifiable {
    var id: String
    var fraction: Double
    var color: Color
}
