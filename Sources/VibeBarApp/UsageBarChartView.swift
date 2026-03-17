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
        let bucketTotals = calculateBucketTotals(points)
        let maxY = max(bucketTotals.values.max() ?? 1, 1)

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
            .chartYScale(domain: 0...max(1, maxY * 1.1))
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
            
            // Debug: show bucket totals
            if !compact {
                let sortedTotals = bucketTotals.sorted { $0.key < $1.key }
                HStack(spacing: 8) {
                    ForEach(sortedTotals, id: \.key) { bucket, total in
                        VStack(spacing: 2) {
                            Text(bucket)
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                            Text(formatNumber(total))
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.primary)
                        }
                    }
                }
                .padding(.top, 4)
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

    private func calculateBucketTotals(_ points: [UsageChartPoint]) -> [String: Double] {
        Dictionary(grouping: points, by: \.bucketLabel)
            .mapValues { points in
                points.reduce(0.0) { $0 + $1.value }
            }
    }

    private var chartPoints: [UsageChartPoint] {
        let points = snapshot.series.flatMap { series in
            series.points.map { point in
                UsageChartPoint(
                    bucketLabel: point.bucketLabel,
                    seriesLabel: series.label,
                    value: snapshot.configuration.effectiveMetric == .tokens ? Double(point.tokens) : point.costUSD
                )
            }
        }
        // 按 bucketLabel 排序以确保一致的显示顺序
        return points.sorted { $0.bucketLabel < $1.bucketLabel }
    }

    private var metricTitle: String {
        snapshot.configuration.effectiveMetric == .tokens ? "Token volume" : "Estimated value"
    }

    private var totalValue: String {
        snapshot.configuration.effectiveMetric == .tokens
            ? "\(snapshot.totalTokens.formatted()) tokens"
            : String(format: "$.2f", snapshot.totalCostUSD)
    }
    
    private func formatNumber(_ value: Double) -> String {
        if value >= 1_000_000_000 {
            return String(format: "%.1fB", value / 1_000_000_000)
        } else if value >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.1fK", value / 1_000)
        } else {
            return String(format: "%.0f", value)
        }
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
