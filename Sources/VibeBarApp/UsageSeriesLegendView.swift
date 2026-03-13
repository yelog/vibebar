import SwiftUI
import VibeBarCore

enum UsageChartColorPalette {
    private static let colors: [Color] = [
        Color(red: 0.12, green: 0.52, blue: 0.95),
        Color(red: 0.18, green: 0.72, blue: 0.43),
        Color(red: 0.96, green: 0.58, blue: 0.13),
        Color(red: 0.84, green: 0.29, blue: 0.44),
        Color(red: 0.47, green: 0.35, blue: 0.95),
        Color(red: 0.11, green: 0.72, blue: 0.76),
    ]

    static func color(at index: Int) -> Color {
        colors[index % colors.count]
    }

    static func entries(for series: [UsageSeries]) -> [UsageSeriesLegendEntry] {
        series.enumerated().map { index, item in
            UsageSeriesLegendEntry(
                id: item.id,
                label: item.label,
                color: color(at: index)
            )
        }
    }
}

struct UsageSeriesLegendEntry: Identifiable {
    let id: String
    let label: String
    let color: Color
}

struct UsageSeriesLegendView: View {
    let entries: [UsageSeriesLegendEntry]
    let compact: Bool

    private var gridColumns: [GridItem] {
        [
            GridItem(
                .adaptive(minimum: compact ? 88 : 108, maximum: compact ? 160 : 220),
                spacing: compact ? 8 : 10,
                alignment: .leading
            ),
        ]
    }

    var body: some View {
        if !entries.isEmpty {
            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: compact ? 6 : 8) {
                ForEach(entries) { entry in
                    HStack(spacing: compact ? 5 : 6) {
                        RoundedRectangle(cornerRadius: compact ? 2 : 3, style: .continuous)
                            .fill(entry.color)
                            .frame(width: compact ? 10 : 12, height: compact ? 10 : 12)

                        Text(entry.label)
                            .font(.system(size: compact ? 9 : 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .accessibilityElement(children: .contain)
        }
    }
}
