import SwiftUI
import VibeBarCore

struct UsageSettingsView: View {
    @Binding var configuration: UsageDisplayConfiguration
    @Binding var usageEnabled: Bool
    @Binding var fullRefreshInterval: UsageFullRefreshInterval
    let snapshot: UsageSnapshot
    let isRefreshing: Bool
    let isFullRefreshing: Bool
    var isRebuilding: Bool = false
    let lastErrorMessage: String?
    let incrementalRefreshTime: Date?
    let incrementalRefreshDuration: TimeInterval?
    let fullRefreshTime: Date?
    let fullRefreshDuration: TimeInterval?
    let onRefresh: () -> Void
    let onFullRefresh: () -> Void

    @ObservedObject private var l10n = L10n.shared
    @State private var previewChartHover: UsageMenuChartHoverState?
    @State private var previewCardFrame: CGRect = .zero
    @State private var previewTooltipSize: CGSize = .zero

    private static let previewCoordinateSpaceName = "UsageSettingsView.preview"

    var body: some View {
        ScrollView(showsIndicators: true) {
            VStack(alignment: .leading, spacing: SettingsPanelLayout.sectionSpacing) {
                header

                SettingsSection(title: l10n.string(.usageDataSourcesTitle)) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(l10n.string(.usageDataSourcesDesc))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        sourceGrid
                    }
                }

                SettingsSection(title: l10n.string(.usageRefreshSectionTitle)) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Picker(l10n.string(.usageRefreshCadenceTitle), selection: cadenceBinding) {
                                ForEach(UsageRefreshCadence.allCases) { cadence in
                                    Text(cadence.displayName).tag(cadence)
                                }
                            }
                            .pickerStyle(.segmented)

                            Spacer()

                            Button(action: onRefresh) {
                                if isRefreshing {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Label(l10n.string(.usageIncrementalRefresh), systemImage: "arrow.clockwise")
                                        .labelStyle(.iconOnly)
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(!usageEnabled || isFullRefreshing)
                        }

                        Text(l10n.string(.usageRefreshCadenceDesc))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        if let time = incrementalRefreshTime {
                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                    .font(.system(size: 10))
                                Text(l10n.string(.usageLastRefreshTime))
                                    .font(.system(size: 11))
                                Text(formatRelativeTime(Date().timeIntervalSince(time)))
                                    .font(.system(size: 11, weight: .medium))

                                if let duration = incrementalRefreshDuration {
                                    Text("·")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.tertiary)
                                    Image(systemName: "stopwatch")
                                        .font(.system(size: 10))
                                    Text(formatDuration(duration))
                                        .font(.system(size: 11, weight: .medium))
                                }
                            }
                            .foregroundStyle(.secondary)
                        }

                        Divider()

                        HStack {
                            Picker(l10n.string(.usageFullRefreshCadenceTitle), selection: $fullRefreshInterval) {
                                ForEach(UsageFullRefreshInterval.allCases) { interval in
                                    Text(interval.displayName).tag(interval)
                                }
                            }
                            .pickerStyle(.segmented)

                            Spacer()

                            Button(action: onFullRefresh) {
                                if isFullRefreshing {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Label(l10n.string(.usageFullRefresh), systemImage: "arrow.triangle.2.circlepath")
                                        .labelStyle(.iconOnly)
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(!usageEnabled || isRefreshing)
                        }

                        Text(l10n.string(.usageFullRefreshCadenceDesc))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        if let time = fullRefreshTime {
                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                    .font(.system(size: 10))
                                Text(l10n.string(.usageLastRefreshTime))
                                    .font(.system(size: 11))
                                Text(formatRelativeTime(Date().timeIntervalSince(time)))
                                    .font(.system(size: 11, weight: .medium))

                                if let duration = fullRefreshDuration {
                                    Text("·")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.tertiary)
                                    Image(systemName: "stopwatch")
                                        .font(.system(size: 10))
                                    Text(formatDuration(duration))
                                        .font(.system(size: 11, weight: .medium))
                                }
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                }

                SettingsSection(title: l10n.string(.usageVisualizationTitle)) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(l10n.string(.usageVisualizationDesc))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        stylePicker

                        if configuration.visualizationStyle == .githubHeatmap {
                            VStack(alignment: .leading, spacing: 12) {
                                LazyVGrid(columns: [GridItem(.flexible())], spacing: 12) {
                                    controlGroup(title: l10n.string(.usageMetricTitle)) {
                                        Picker(l10n.string(.usageMetricTitle), selection: metricBinding) {
                                            ForEach(UsageMetric.allCases) { metric in
                                                Text(metric.displayName).tag(metric)
                                            }
                                        }
                                        .pickerStyle(.menu)
                                    }
                                }

                                heatmapHint
                            }
                        } else {
                            controlsGrid
                        }
                    }
                }

                SettingsSection(title: l10n.string(.usagePreviewTitle)) {
                    VStack(alignment: .leading, spacing: 12) {
                        previewMeta

                        if let lastErrorMessage, !lastErrorMessage.isEmpty {
                            Text(lastErrorMessage)
                                .font(.system(size: 11))
                                .foregroundStyle(.red)
                        }

                        previewContent
                    }
                    .coordinateSpace(name: Self.previewCoordinateSpaceName)
                    .onPreferenceChange(UsageSettingsPreviewCardFramePreferenceKey.self) { frame in
                        previewCardFrame = frame
                    }
                    .onPreferenceChange(UsageSettingsPreviewTooltipSizePreferenceKey.self) { size in
                        previewTooltipSize = size
                    }
                    .overlay(alignment: .topLeading) {
                        previewTooltipOverlay
                    }
                    .zIndex(previewChartHover == nil ? 0 : 10)
                    .onChange(of: previewChartHover == nil) { isNil in
                        if isNil {
                            previewTooltipSize = .zero
                        }
                    }
                    .onDisappear {
                        previewChartHover = nil
                        previewTooltipSize = .zero
                    }
                }
            }
            .padding(.horizontal, SettingsPanelLayout.horizontalPadding)
            .padding(.bottom, 20)
        }
    }

    private var header: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))
                            .frame(width: 48, height: 48)

                        Image(systemName: "waveform.path.ecg.rectangle")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(l10n.string(.usageTitle))
                            .font(.system(size: 18, weight: .bold))

                        Text(l10n.string(.usageHeaderDescription))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: $usageEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                HStack(spacing: 8) {
                    statusPill(
                        title: usageEnabled ? l10n.string(.usageEnabled) : l10n.string(.usageDisabled),
                        tint: usageEnabled ? .green : .secondary
                    )
                    if usageEnabled {
                        statusPill(
                            title: "\(configuration.normalizedSources.count) \(l10n.string(.usageSourcesCount))",
                            tint: .blue
                        )
                        statusPill(
                            title: configuration.refreshCadence.displayName,
                            tint: .green
                        )
                        statusPill(
                            title: configuration.visualizationStyle.displayName,
                            tint: .orange
                        )
                        if isRefreshing {
                            statusPill(
                                title: l10n.string(.usageRefreshing),
                                tint: .teal
                            )
                        }
                    }
                }
            }
        }
    }

    private var sourceGrid: some View {
        LazyVGrid(columns: sourceGridColumns, alignment: .leading, spacing: 10) {
            ForEach(UsageSource.allCases) { source in
                UsageSourceCard(
                    source: source,
                    isSelected: configuration.normalizedSources.contains(source),
                    action: {
                        toggleSource(source)
                    }
                )
            }
        }
    }

    private var stylePicker: some View {
        LazyVGrid(columns: styleGridColumns, alignment: .leading, spacing: 10) {
            ForEach(UsageVisualizationStyle.allCases) { style in
                UsageStyleCard(
                    style: style,
                    isSelected: configuration.visualizationStyle == style
                ) {
                    configuration.visualizationStyle = style
                }
            }
        }
    }

    private var heatmapHint: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.green)
                Text(l10n.string(.usageHeatmapHint1))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Text(l10n.string(.usageHeatmapHint2))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.green.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.green.opacity(0.20), lineWidth: 1)
        )
    }

    private var controlsGrid: some View {
        LazyVGrid(columns: controlGridColumns, alignment: .leading, spacing: 12) {
            controlGroup(title: l10n.string(.usageMetricTitle)) {
                Picker(l10n.string(.usageMetricTitle), selection: metricBinding) {
                    ForEach(UsageMetric.allCases) { metric in
                        Text(metric.displayName).tag(metric)
                    }
                }
                .pickerStyle(.menu)
            }

            controlGroup(title: l10n.string(.usageGranularityTitle)) {
                Picker(l10n.string(.usageGranularityTitle), selection: granularityBinding) {
                    ForEach(UsageGranularity.allCases) { granularity in
                        Text(granularity.displayName).tag(granularity)
                    }
                }
                .pickerStyle(.menu)
            }

            controlGroup(title: l10n.string(.usageGroupingTitle)) {
                Picker(l10n.string(.usageGroupingTitle), selection: groupingBinding) {
                    ForEach(UsageSeriesGrouping.allCases) { grouping in
                        Text(grouping.displayName).tag(grouping)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    // 固定3列布局，适应480px宽度（480 - 24*2 padding = 432px 可用宽度）
    private var sourceGridColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]
    }

    private var styleGridColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]
    }

    private var controlGridColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]
    }

    private var previewMeta: some View {
        HStack(spacing: 8) {
            statusPill(
                title: configuration.effectiveMetric.displayName,
                tint: configuration.effectiveMetric == .tokens ? .purple : .pink
            )
            if configuration.visualizationStyle == .githubHeatmap {
                statusPill(
                    title: "52 weeks",
                    tint: .teal
                )
            } else {
                statusPill(
                    title: configuration.effectiveGranularity.displayName,
                    tint: .teal
                )
                statusPill(
                    title: configuration.seriesGrouping.displayName,
                    tint: .orange
                )
            }

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 9, weight: .medium))
                Text(updatedTimeText)
                    .font(.system(size: 11, weight: .medium))

                if snapshot.loadDuration != nil {
                    Text("·")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Image(systemName: "stopwatch")
                        .font(.system(size: 9, weight: .medium))
                    Text(loadDurationText)
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .foregroundStyle(.secondary)
        }
    }

    private var updatedTimeText: String {
        guard snapshot.updatedAt != .distantPast else {
            return isRefreshing ? l10n.string(.usageRefreshing) : l10n.string(.usageWaitingFirstRefresh)
        }
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

    @ViewBuilder
    private var previewContent: some View {
        UsageMenuSectionView(
            snapshot: snapshot,
            isRefreshing: isRefreshing,
            isRebuilding: isRebuilding,
            onChartHoverChange: { hover in
                previewChartHover = hover
            },
            action: nil
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: UsageSettingsPreviewCardFramePreferenceKey.self,
                    value: proxy.frame(in: .named(Self.previewCoordinateSpaceName))
                )
            }
        )
    }

    private var previewTooltipOverlay: some View {
        GeometryReader { proxy in
            if let hover = previewChartHover, !previewCardFrame.isEmpty {
                UsageChartTooltipView(content: hover.content)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: UsageSettingsPreviewTooltipSizePreferenceKey.self,
                                value: proxy.size
                            )
                        }
                    )
                    .offset(
                        x: previewTooltipOffsetX(containerWidth: proxy.size.width, hover: hover),
                        y: previewTooltipOffsetY(hover: hover)
                    )
                    .zIndex(1)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
    }

    private func previewTooltipOffsetX(containerWidth: CGFloat, hover: UsageMenuChartHoverState) -> CGFloat {
        let tooltipSize = resolvedPreviewTooltipSize(for: hover)
        let anchorX = previewCardFrame.minX + hover.bucketFrame.midX
        let proposedX = anchorX - tooltipSize.width / 2
        return min(
            max(0, proposedX),
            max(0, containerWidth - tooltipSize.width)
        )
    }

    private func previewTooltipOffsetY(hover: UsageMenuChartHoverState) -> CGFloat {
        let anchorY = previewCardFrame.minY + hover.chartFrame.minY
        return anchorY - resolvedPreviewTooltipSize(for: hover).height
    }

    private func resolvedPreviewTooltipSize(for hover: UsageMenuChartHoverState) -> CGSize {
        if previewTooltipSize != .zero {
            return previewTooltipSize
        }
        return CGSize(width: hover.content.estimatedWidth, height: hover.content.estimatedHeight)
    }

    private var cadenceBinding: Binding<UsageRefreshCadence> {
        Binding(
            get: { configuration.refreshCadence },
            set: { configuration.refreshCadence = $0 }
        )
    }

    private var metricBinding: Binding<UsageMetric> {
        Binding(
            get: { configuration.metric },
            set: { configuration.metric = $0 }
        )
    }

    private var granularityBinding: Binding<UsageGranularity> {
        Binding(
            get: { configuration.granularity },
            set: { configuration.granularity = $0 }
        )
    }

    private var groupingBinding: Binding<UsageSeriesGrouping> {
        Binding(
            get: { configuration.seriesGrouping },
            set: { configuration.seriesGrouping = $0 }
        )
    }

    @ViewBuilder
    private func controlGroup<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
                .labelsHidden()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func statusPill(title: String, tint: Color) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(tint.opacity(0.12))
            )
            .overlay(
                Capsule()
                    .strokeBorder(tint.opacity(0.25), lineWidth: 1)
            )
    }

    private func toggleSource(_ source: UsageSource) {
        var selected = configuration.normalizedSources
        if selected.contains(source) {
            guard selected.count > 1 else { return }
            selected.removeAll { $0 == source }
        } else {
            selected.append(source)
        }
        configuration.sources = UsageSource.allCases.filter { selected.contains($0) }
    }
}

private struct UsageSettingsPreviewCardFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect { .zero }

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if !next.isEmpty {
            value = next
        }
    }
}

private struct UsageSettingsPreviewTooltipSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize { .zero }

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

private struct UsageSourceCard: View {
    let source: UsageSource
    let isSelected: Bool
    let action: () -> Void

    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: iconName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)

                    Spacer()

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary.opacity(0.5))
                }

                Text(source.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.75) : Color.primary.opacity(0.08),
                        lineWidth: isSelected ? 1.4 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var iconName: String {
        switch source {
        case .claudeCode:
            return "sparkles"
        case .codex:
            return "chevron.left.forwardslash.chevron.right"
        case .opencode:
            return "network"
        }
    }

    private var description: String {
        switch source {
        case .claudeCode:
            return l10n.string(.usageSourceClaudeDesc)
        case .codex:
            return l10n.string(.usageSourceCodexDesc)
        case .opencode:
            return l10n.string(.usageSourceOpenCodeDesc)
        }
    }
}

private struct UsageStyleCard: View {
    let style: UsageVisualizationStyle
    let isSelected: Bool
    let action: () -> Void

    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: iconName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)

                Text(style.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.75) : Color.primary.opacity(0.08),
                        lineWidth: isSelected ? 1.4 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var iconName: String {
        switch style {
        case .githubHeatmap:
            return "square.grid.4x3.fill"
        case .barChart:
            return "chart.bar.xaxis"
        case .lineChart:
            return "chart.line.uptrend.xyaxis"
        }
    }

    private var description: String {
        switch style {
        case .githubHeatmap:
            return l10n.string(.usageStyleGithubDesc)
        case .barChart:
            return l10n.string(.usageStyleBarDesc)
        case .lineChart:
            return l10n.string(.usageStyleLineDesc)
        }
    }
}

enum UsagePreviewFactory {
    static func snapshot(configuration: UsageDisplayConfiguration) -> UsageSnapshot {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date())

        let buckets = sampleBuckets(configuration: configuration, today: today, calendar: calendar)
        let series = sampleSeries(configuration: configuration, buckets: buckets)
        let heatmapCells = sampleHeatmapCells(today: today, calendar: calendar)

        return UsageSnapshot(
            updatedAt: Date(),
            configuration: configuration,
            totalTokens: buckets.reduce(0) { $0 + $1.tokens },
            totalCostUSD: buckets.reduce(0) { $0 + $1.costUSD },
            buckets: buckets,
            series: series,
            heatmapCells: heatmapCells,
            warnings: [],
            missingDirectories: [],
            estimatedCostEventCount: 4,
            unresolvedCostEventCount: 0
        )
    }

    private static func sampleBuckets(
        configuration: UsageDisplayConfiguration,
        today: Date,
        calendar: Calendar
    ) -> [UsageBucket] {
        let count: Int
        let component: Calendar.Component
        switch configuration.effectiveGranularity {
        case .hour:
            count = 8
            component = .hour
        case .day:
            count = 8
            component = .day
        case .week:
            count = 8
            component = .weekOfYear
        case .month:
            count = 6
            component = .month
        }

        return (0..<count).compactMap { index in
            guard let start = calendar.date(byAdding: component, value: -(count - index - 1), to: today) else {
                return nil
            }

            let label: String
            switch configuration.effectiveGranularity {
            case .hour:
                label = shortTime(start)
            case .day:
                label = shortDate(start)
            case .week:
                let week = calendar.component(.weekOfYear, from: start)
                label = "W\(week)"
            case .month:
                label = monthDate(start)
            }

            let baseTokens = 12_000 + index * 3_800
            let totalTokens = index % 3 == 0 ? baseTokens + 6_000 : baseTokens
            let totalCost = Double(totalTokens) / 1_000_000.0 * 12

            let breakdown = breakdownItems(
                configuration: configuration,
                bucketID: label,
                totalTokens: totalTokens,
                totalCost: totalCost
            )

            return UsageBucket(
                id: label,
                label: label,
                startDate: start,
                endDate: start,
                tokens: totalTokens,
                costUSD: totalCost,
                breakdown: breakdown
            )
        }
    }

    private static func sampleSeries(
        configuration: UsageDisplayConfiguration,
        buckets: [UsageBucket]
    ) -> [UsageSeries] {
        switch configuration.seriesGrouping {
        case .total:
            return [
                UsageSeries(
                    id: "total",
                    label: "Total",
                    points: buckets.map { bucket in
                        UsageSeriesPoint(
                            id: "total-\(bucket.id)",
                            bucketID: bucket.id,
                            bucketLabel: bucket.label,
                            date: bucket.startDate,
                            tokens: bucket.tokens,
                            costUSD: bucket.costUSD
                        )
                    }
                )
            ]

        case .agent, .model, .project:
            let labels = buckets.first?.breakdown.map(\.label) ?? []
            return labels.map { label in
                UsageSeries(
                    id: label,
                    label: label,
                    points: buckets.map { bucket in
                        let item = bucket.breakdown.first { $0.label == label }
                        return UsageSeriesPoint(
                            id: "\(label)-\(bucket.id)",
                            bucketID: bucket.id,
                            bucketLabel: bucket.label,
                            date: bucket.startDate,
                            tokens: item?.tokens ?? 0,
                            costUSD: item?.costUSD ?? 0
                        )
                    }
                )
            }
        }
    }

    private static func breakdownItems(
        configuration: UsageDisplayConfiguration,
        bucketID: String,
        totalTokens: Int,
        totalCost: Double
    ) -> [UsageBreakdownItem] {
        switch configuration.seriesGrouping {
        case .total:
            return [
                UsageBreakdownItem(
                    id: "\(bucketID)-total",
                    label: "Total",
                    tokens: totalTokens,
                    costUSD: totalCost
                )
            ]
        case .agent:
            let parts: [(String, Double)] = [
                ("Claude Code", 0.48),
                ("Codex", 0.32),
                ("OpenCode", 0.20),
            ]
            return parts.map { label, ratio in
                UsageBreakdownItem(
                    id: "\(bucketID)-\(label)",
                    label: label,
                    tokens: Int(Double(totalTokens) * ratio),
                    costUSD: totalCost * ratio
                )
            }
        case .model:
            let parts: [(String, Double)] = [
                ("sonnet-4-5", 0.45),
                ("gpt-5", 0.30),
                ("Others", 0.25),
            ]
            return parts.map { label, ratio in
                UsageBreakdownItem(
                    id: "\(bucketID)-\(label)",
                    label: label,
                    tokens: Int(Double(totalTokens) * ratio),
                    costUSD: totalCost * ratio
                )
            }
        case .project:
            let parts: [(String, Double)] = [
                ("VibeBar", 0.40),
                ("moss-cloud", 0.35),
                ("Others", 0.25),
            ]
            return parts.map { label, ratio in
                UsageBreakdownItem(
                    id: "\(bucketID)-\(label)",
                    label: label,
                    tokens: Int(Double(totalTokens) * ratio),
                    costUSD: totalCost * ratio
                )
            }
        }
    }

    private static func sampleHeatmapCells(today: Date, calendar: Calendar) -> [UsageHeatmapCell] {
        let count = 52 * 7
        return (0..<count).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -(count - offset - 1), to: today) else {
                return nil
            }
            let weekday = calendar.component(.weekday, from: date)
            let wave = (offset % 11 == 0) ? 0.92 : Double((weekday * 13 + offset) % 100) / 100.0
            let intensity = max(0.04, wave)
            return UsageHeatmapCell(
                id: shortDate(date),
                date: date,
                tokens: Int(52_000 * intensity),
                costUSD: 0.52 * intensity,
                intensity: intensity
            )
        }
    }

    private static func shortTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"
        return formatter.string(from: date)
    }

    private static func monthDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }
}
