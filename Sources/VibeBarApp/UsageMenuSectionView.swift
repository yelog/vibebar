import SwiftUI
import VibeBarCore

struct UsageMenuSectionView: View {
    let snapshot: UsageSnapshot
    let isRefreshing: Bool
    let action: (() -> Void)?

    @ObservedObject private var l10n = L10n.shared

    private let accentColors: [Color] = [
        Color(red: 0.12, green: 0.52, blue: 0.95),
        Color(red: 0.18, green: 0.72, blue: 0.43),
        Color(red: 0.96, green: 0.58, blue: 0.13),
        Color(red: 0.84, green: 0.29, blue: 0.44),
        Color(red: 0.47, green: 0.35, blue: 0.95),
        Color(red: 0.11, green: 0.72, blue: 0.76),
    ]

    private var compactBuckets: [UsageBucket] {
        Array(snapshot.buckets.suffix(12))
    }

    private var compactHeatmapCells: [UsageHeatmapCell] {
        Array(snapshot.heatmapCells.suffix(7 * 12))
    }

    private var compactSeries: [UsageSeries] {
        Array(snapshot.series.prefix(6))
    }

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    cardContent
                }
                .buttonStyle(.plain)
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
        .padding(12)
        .frame(width: 360, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
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

            if isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
            } else {
                Text(updatedText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if snapshot.buckets.isEmpty {
            Text(l10n.string(.usageNoData))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 72, alignment: .center)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
        } else {
            switch snapshot.configuration.visualizationStyle {
            case .githubHeatmap:
                heatmapView
            case .barChart:
                barChartView
            case .lineChart:
                lineChartView
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(primaryValueText)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)

            if snapshot.configuration.effectiveMetric == .costUSD {
                Text(l10n.string(.usageEstimatedCostHint))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("\(snapshot.configuration.normalizedSources.count) source(s)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var heatmapView: some View {
        let columns = Array(repeating: GridItem(.fixed(7), spacing: 3), count: 12)
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 3) {
            ForEach(compactHeatmapCells) { cell in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(heatmapColor(for: cell))
                    .frame(width: 7, height: 7)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private var barChartView: some View {
        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(compactBuckets) { bucket in
                VStack(spacing: 4) {
                    ZStack(alignment: .bottom) {
                        Capsule()
                            .fill(Color.primary.opacity(0.08))
                            .frame(width: 18, height: 72)

                        VStack(spacing: 1) {
                            ForEach(seriesSegments(for: bucket)) { segment in
                                Capsule()
                                    .fill(segment.color)
                                    .frame(width: 18, height: max(2, 72 * segment.fraction))
                            }
                        }
                    }

                    Text(shortBucketLabel(bucket.label))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private var lineChartView: some View {
        let maxValue = max(
            compactSeries.flatMap(\.points).map {
                snapshot.configuration.effectiveMetric == .tokens ? Double($0.tokens) : $0.costUSD
            }.max() ?? 0,
            1
        )

        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.04))

                    ForEach(Array(compactSeries.enumerated()), id: \.offset) { index, series in
                        let points = Array(series.points.suffix(12))
                        Path { path in
                            for (pointIndex, point) in points.enumerated() {
                                let x = points.count <= 1
                                    ? proxy.size.width / 2
                                    : proxy.size.width * CGFloat(pointIndex) / CGFloat(max(points.count - 1, 1))
                                let rawValue = snapshot.configuration.effectiveMetric == .tokens
                                    ? Double(point.tokens)
                                    : point.costUSD
                                let y = proxy.size.height - (proxy.size.height * CGFloat(rawValue / maxValue))
                                if pointIndex == 0 {
                                    path.move(to: CGPoint(x: x, y: y))
                                } else {
                                    path.addLine(to: CGPoint(x: x, y: y))
                                }
                            }
                        }
                        .stroke(accentColors[index % accentColors.count], lineWidth: 2)
                    }
                }
            }
            .frame(height: 86)

            HStack {
                ForEach(Array(compactSeries.enumerated()), id: \.offset) { index, series in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(accentColors[index % accentColors.count])
                            .frame(width: 6, height: 6)
                        Text(series.label)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private func seriesSegments(for bucket: UsageBucket) -> [UsageMenuBarSegment] {
        let totalValue = max(
            snapshot.configuration.effectiveMetric == .tokens
                ? Double(bucket.tokens)
                : bucket.costUSD,
            1
        )

        let items = compactSeries.compactMap { series -> UsageMenuBarSegment? in
            guard let point = series.points.first(where: { $0.bucketID == bucket.id }) else { return nil }
            let value = snapshot.configuration.effectiveMetric == .tokens
                ? Double(point.tokens)
                : point.costUSD
            guard value > 0 else { return nil }
            let index = compactSeries.firstIndex(where: { $0.id == series.id }) ?? 0
            return UsageMenuBarSegment(
                id: "\(bucket.id):\(series.id)",
                fraction: value / totalValue,
                color: accentColors[index % accentColors.count]
            )
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

    private func shortBucketLabel(_ rawValue: String) -> String {
        if rawValue.count <= 5 {
            return rawValue
        }
        return String(rawValue.suffix(5))
    }

    private func heatmapColor(for cell: UsageHeatmapCell) -> Color {
        if cell.tokens == 0 {
            return Color.primary.opacity(0.08)
        }
        return Color.accentColor.opacity(0.18 + (cell.intensity * 0.72))
    }

    private var configurationSummary: String {
        [
            snapshot.configuration.visualizationStyle.displayName,
            snapshot.configuration.effectiveMetric.displayName,
            snapshot.configuration.effectiveGranularity.displayName,
        ].joined(separator: " · ")
    }

    private var updatedText: String {
        guard snapshot.updatedAt > .distantPast else { return "--" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: snapshot.updatedAt)
    }

    private var primaryValueText: String {
        switch snapshot.configuration.effectiveMetric {
        case .tokens:
            return "\(snapshot.totalTokens) tokens"
        case .costUSD:
            return String(format: "$%.4f", snapshot.totalCostUSD)
        }
    }
}

private struct UsageMenuBarSegment: Identifiable {
    var id: String
    var fraction: Double
    var color: Color
}
