import Charts
import SwiftUI
import VibeBarCore

struct UsageLineChartView: View {
    let snapshot: UsageSnapshot
    let compact: Bool

    var body: some View {
        let points = chartPoints

        VStack(alignment: .leading, spacing: 10) {
            Chart(points) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(by: .value("Series", point.seriesLabel))
                .lineStyle(StrokeStyle(lineWidth: compact ? 2 : 2.5, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(by: .value("Series", point.seriesLabel))
                .symbolSize(compact ? 28 : 42)
            }
            .chartLegend(compact ? .hidden : .visible)
            .chartYAxis {
                if compact {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
                } else {
                    AxisMarks(position: .leading)
                }
            }
            .chartXAxis {
                AxisMarks(values: xAxisDates) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(xAxisLabel(for: date))
                                .font(.system(size: compact ? 9 : 10, weight: .medium))
                        }
                    }
                }
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

    private var chartPoints: [UsageLineChartPoint] {
        snapshot.series.flatMap { series in
            series.points.map { point in
                UsageLineChartPoint(
                    id: "\(series.id)-\(point.id)",
                    date: point.date,
                    seriesLabel: series.label,
                    value: snapshot.configuration.effectiveMetric == .tokens ? Double(point.tokens) : point.costUSD
                )
            }
        }
    }

    private var xAxisDates: [Date] {
        let dates = chartPoints.map(\.date).sorted()
        if compact, dates.count > 4 {
            let step = max(1, dates.count / 4)
            return stride(from: 0, to: dates.count, by: step).map { dates[$0] }
        }
        return dates
    }

    private var metricTitle: String {
        snapshot.configuration.effectiveMetric == .tokens ? "Token trend" : "Estimated value trend"
    }

    private var totalValue: String {
        snapshot.configuration.effectiveMetric == .tokens
            ? "\(snapshot.totalTokens.formatted()) tokens"
            : String(format: "$%.2f", snapshot.totalCostUSD)
    }

    private func xAxisLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        switch snapshot.configuration.effectiveGranularity {
        case .day:
            formatter.dateFormat = "MM/dd"
        case .week:
            formatter.dateFormat = "'W'ww"
        case .month:
            formatter.dateFormat = "yy/MM"
        }
        return formatter.string(from: date)
    }
}

private struct UsageLineChartPoint: Identifiable {
    let id: String
    let date: Date
    let seriesLabel: String
    let value: Double
}
