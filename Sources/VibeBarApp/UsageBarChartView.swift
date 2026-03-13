import Charts
import SwiftUI
import VibeBarCore

struct UsageBarChartView: View {
    let snapshot: UsageSnapshot
    let compact: Bool

    private var legendEntries: [UsageSeriesLegendEntry] {
        UsageChartColorPalette.entries(for: snapshot.series)
    }

    private var shouldShowLegend: Bool {
        snapshot.configuration.seriesGrouping != .total && !legendEntries.isEmpty
    }

    var body: some View {
        let points = chartPoints

        VStack(alignment: .leading, spacing: 10) {
            Chart(points) { point in
                BarMark(
                    x: .value("Bucket", point.bucketLabel),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(by: .value("Series", point.seriesLabel))
                .cornerRadius(5)
            }
            .chartForegroundStyleScale(
                domain: legendEntries.map(\.label),
                range: legendEntries.map(\.color)
            )
            .chartLegend(.hidden)
            .chartYAxis {
                if compact {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
                } else {
                    AxisMarks(position: .leading)
                }
            }
            .chartXAxis {
                AxisMarks(values: points.map(\.bucketLabel)) { value in
                    AxisValueLabel {
                        if let label = value.as(String.self) {
                            Text(label)
                                .font(.system(size: compact ? 9 : 10, weight: .medium))
                        }
                    }
                }
            }

            if shouldShowLegend {
                UsageSeriesLegendView(entries: legendEntries, compact: compact)
            }

            HStack {
                Text(metricTitle)
                    .font(.system(size: compact ? 10 : 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(totalValue)
                    .font(.system(size: compact ? 11 : 12, weight: .semibold))
                    .foregroundStyle(.primary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var chartPoints: [UsageChartPoint] {
        snapshot.series.flatMap { series in
            series.points.map { point in
                UsageChartPoint(
                    bucketLabel: point.bucketLabel,
                    seriesLabel: series.label,
                    value: snapshot.configuration.effectiveMetric == .tokens ? Double(point.tokens) : point.costUSD
                )
            }
        }
    }

    private var metricTitle: String {
        snapshot.configuration.effectiveMetric == .tokens ? "Token volume" : "Estimated value"
    }

    private var totalValue: String {
        snapshot.configuration.effectiveMetric == .tokens
            ? "\(snapshot.totalTokens.formatted()) tokens"
            : String(format: "$%.2f", snapshot.totalCostUSD)
    }
}

private struct UsageChartPoint: Identifiable {
    let bucketLabel: String
    let seriesLabel: String
    let value: Double

    var id: String {
        "\(seriesLabel)-\(bucketLabel)"
    }
}
