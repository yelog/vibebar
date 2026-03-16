import SwiftUI
import VibeBarCore

struct UsageSeriesVisualStyle {
    let color: Color
    let dashPattern: [CGFloat]

    func strokeStyle(lineWidth: CGFloat) -> StrokeStyle {
        StrokeStyle(
            lineWidth: lineWidth,
            lineCap: .round,
            lineJoin: .round,
            dash: dashPattern
        )
    }
}

enum UsageSeriesLegendVariant {
    case swatch
    case line
}

enum UsageChartColorPalette {
    private static let vividColors: [Color] = [
        Color(red: 0.12, green: 0.52, blue: 0.95),
        Color(red: 0.94, green: 0.56, blue: 0.12),
        Color(red: 0.17, green: 0.68, blue: 0.36),
        Color(red: 0.84, green: 0.29, blue: 0.44),
        Color(red: 0.47, green: 0.35, blue: 0.95),
        Color(red: 0.00, green: 0.64, blue: 0.73),
        Color(red: 0.84, green: 0.25, blue: 0.23),
        Color(red: 0.64, green: 0.42, blue: 0.08),
    ]

    private static let dashPatterns: [[CGFloat]] = [
        [],
        [7, 4],
        [2, 3],
        [10, 4, 2, 4],
    ]

    private static let othersStyle = UsageSeriesVisualStyle(
        color: Color(red: 0.55, green: 0.58, blue: 0.64),
        dashPattern: []
    )

    static func entries(for series: [UsageSeries]) -> [UsageSeriesLegendEntry] {
        let styles = styleMap(for: series)
        return series.map { item in
            let style = styles[item.id] ?? fallbackStyle(for: item)
            return UsageSeriesLegendEntry(
                id: item.id,
                label: item.label,
                color: style.color,
                dashPattern: style.dashPattern
            )
        }
    }

    static func styleMap(for series: [UsageSeries]) -> [String: UsageSeriesVisualStyle] {
        var styles: [String: UsageSeriesVisualStyle] = [:]
        var usedSlots = Set<Int>()

        let orderedSeries = series.sorted { sortKey(for: $0) < sortKey(for: $1) }
        for item in orderedSeries {
            if isOthers(item) {
                styles[item.id] = othersStyle
                continue
            }

            let preferredColorIndex = Int(stableHash(sortKey(for: item)) % UInt64(vividColors.count))
            let slot = nextAvailableSlot(preferredColorIndex: preferredColorIndex, usedSlots: usedSlots)
            usedSlots.insert(slot)
            styles[item.id] = style(forSlot: slot)
        }

        return styles
    }

    private static func fallbackStyle(for series: UsageSeries) -> UsageSeriesVisualStyle {
        isOthers(series)
            ? othersStyle
            : UsageSeriesVisualStyle(color: vividColors[0], dashPattern: [])
    }

    private static func style(forSlot slot: Int) -> UsageSeriesVisualStyle {
        let colorIndex = slot % vividColors.count
        let dashIndex = min(slot / vividColors.count, dashPatterns.count - 1)
        return UsageSeriesVisualStyle(
            color: vividColors[colorIndex],
            dashPattern: dashPatterns[dashIndex]
        )
    }

    private static func nextAvailableSlot(preferredColorIndex: Int, usedSlots: Set<Int>) -> Int {
        let totalSlots = vividColors.count * dashPatterns.count

        for dashIndex in 0..<dashPatterns.count {
            for offset in 0..<vividColors.count {
                let colorIndex = (preferredColorIndex + offset) % vividColors.count
                let slot = dashIndex * vividColors.count + colorIndex
                if !usedSlots.contains(slot) {
                    return slot
                }
            }
        }

        return preferredColorIndex % totalSlots
    }

    private static func sortKey(for series: UsageSeries) -> String {
        let key = series.id.isEmpty ? series.label : series.id
        return key.lowercased()
    }

    private static func isOthers(_ series: UsageSeries) -> Bool {
        let key = sortKey(for: series)
        return key == "others" || key == "other"
    }

    private static func stableHash(_ string: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        let prime: UInt64 = 1_099_511_628_211

        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }

        return hash
    }
}

struct UsageSeriesLegendEntry: Identifiable {
    let id: String
    let label: String
    let color: Color
    let dashPattern: [CGFloat]

    var visualStyle: UsageSeriesVisualStyle {
        UsageSeriesVisualStyle(color: color, dashPattern: dashPattern)
    }
}

struct UsageSeriesLegendView: View {
    let entries: [UsageSeriesLegendEntry]
    let compact: Bool
    var variant: UsageSeriesLegendVariant = .swatch

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
                        sampleView(for: entry)

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

    @ViewBuilder
    private func sampleView(for entry: UsageSeriesLegendEntry) -> some View {
        switch variant {
        case .swatch:
            RoundedRectangle(cornerRadius: compact ? 2 : 3, style: .continuous)
                .fill(entry.color)
                .frame(width: compact ? 10 : 12, height: compact ? 10 : 12)

        case .line:
            UsageSeriesLegendLineSample(entry: entry, compact: compact)
        }
    }
}

private struct UsageSeriesLegendLineSample: View {
    let entry: UsageSeriesLegendEntry
    let compact: Bool

    var body: some View {
        GeometryReader { proxy in
            let midY = proxy.size.height / 2
            let pointSize: CGFloat = compact ? 5 : 6

            Path { path in
                path.move(to: CGPoint(x: 1, y: midY))
                path.addLine(to: CGPoint(x: proxy.size.width - 1, y: midY))
            }
            .stroke(entry.color, style: entry.visualStyle.strokeStyle(lineWidth: compact ? 1.8 : 2.2))

            Circle()
                .fill(entry.color)
                .frame(width: pointSize, height: pointSize)
                .position(x: proxy.size.width * 0.62, y: midY)
        }
        .frame(width: compact ? 18 : 24, height: compact ? 10 : 12)
    }
}
