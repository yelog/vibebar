import SwiftUI
import VibeBarCore

struct UsageHeatmapGridLayout {
    let cellSize: CGFloat
    let cellSpacing: CGFloat

    static func columnCount(for cellCount: Int, rows: Int = 7) -> Int {
        guard cellCount > 0, rows > 0 else { return 0 }
        return Int(ceil(Double(cellCount) / Double(rows)))
    }

    static func make(compact: Bool, columnCount: Int, availableWidth: CGFloat? = nil) -> Self {
        let defaultCellSize: CGFloat = compact ? 8 : 10
        let defaultCellSpacing: CGFloat = compact ? 2 : 4

        guard compact,
              columnCount > 0,
              let availableWidth,
              availableWidth > 0 else {
            return Self(cellSize: defaultCellSize, cellSpacing: defaultCellSpacing)
        }

        let intrinsicWidth =
            CGFloat(columnCount) * defaultCellSize +
            CGFloat(max(columnCount - 1, 0)) * defaultCellSpacing
        guard intrinsicWidth > availableWidth else {
            return Self(cellSize: defaultCellSize, cellSpacing: defaultCellSpacing)
        }

        let scale = availableWidth / intrinsicWidth
        return Self(
            cellSize: defaultCellSize * scale,
            cellSpacing: defaultCellSpacing * scale
        )
    }

    func gridWidth(columnCount: Int) -> CGFloat {
        guard columnCount > 0 else { return 0 }
        return CGFloat(columnCount) * cellSize + CGFloat(max(columnCount - 1, 0)) * cellSpacing
    }

    func gridHeight(rowCount: Int) -> CGFloat {
        guard rowCount > 0 else { return 0 }
        return CGFloat(rowCount) * cellSize + CGFloat(max(rowCount - 1, 0)) * cellSpacing
    }
}

struct UsageHeatmapTheme {
    let surfaceFill: Color
    let surfaceStroke: Color
    let cellColors: [Color]
    let emptyStroke: Color
    let activeStroke: Color
    let hoverStroke: Color
    let hoverGlow: Color

    static func make(for colorScheme: ColorScheme) -> Self {
        switch colorScheme {
        case .dark:
            return Self(
                surfaceFill: Color(red: 0.15, green: 0.17, blue: 0.20).opacity(0.94),
                surfaceStroke: Color.white.opacity(0.10),
                cellColors: [
                    Color(red: 0.20, green: 0.23, blue: 0.27),
                    Color(red: 0.09, green: 0.23, blue: 0.17),
                    Color(red: 0.12, green: 0.42, blue: 0.24),
                    Color(red: 0.20, green: 0.67, blue: 0.38),
                    Color(red: 0.40, green: 0.88, blue: 0.54),
                ],
                emptyStroke: Color.white.opacity(0.11),
                activeStroke: Color.white.opacity(0.06),
                hoverStroke: Color.white.opacity(0.50),
                hoverGlow: Color(red: 0.40, green: 0.88, blue: 0.54)
            )
        default:
            return Self(
                surfaceFill: Color(red: 0.96, green: 0.97, blue: 0.98),
                surfaceStroke: Color.black.opacity(0.08),
                cellColors: [
                    Color(red: 0.91, green: 0.93, blue: 0.95),
                    Color(red: 0.83, green: 0.92, blue: 0.84),
                    Color(red: 0.58, green: 0.83, blue: 0.61),
                    Color(red: 0.23, green: 0.67, blue: 0.39),
                    Color(red: 0.09, green: 0.46, blue: 0.24),
                ],
                emptyStroke: Color.black.opacity(0.05),
                activeStroke: Color.black.opacity(0.06),
                hoverStroke: Color.black.opacity(0.22),
                hoverGlow: Color(red: 0.23, green: 0.67, blue: 0.39)
            )
        }
    }

    func fillColor(for intensity: Double) -> Color {
        cellColors[bucketIndex(for: intensity)]
    }

    func strokeColor(for intensity: Double, isHovered: Bool) -> Color {
        if isHovered {
            return hoverStroke
        }
        return bucketIndex(for: intensity) == 0 ? emptyStroke : activeStroke
    }

    private func bucketIndex(for intensity: Double) -> Int {
        let normalized = min(max(intensity, 0), 1)
        guard normalized > 0 else { return 0 }

        let adjusted = pow(normalized, 0.58)
        return min(cellColors.count - 1, max(1, Int(ceil(adjusted * Double(cellColors.count - 1)))))
    }
}

struct UsageHeatmapView: View {
    let cells: [UsageHeatmapCell]
    let compact: Bool
    let metric: UsageMetric

    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var l10n = L10n.shared

    private var theme: UsageHeatmapTheme {
        UsageHeatmapTheme.make(for: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom) {
                Text(l10n.string(.usageRecent39Weeks))
                    .font(.system(size: compact ? 10 : 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                HStack(spacing: 6) {
                    Text(l10n.string(.usageLow))
                    legendSwatch(0.0)
                    legendSwatch(0.08)
                    legendSwatch(0.24)
                    legendSwatch(0.52)
                    legendSwatch(1.0)
                    Text(l10n.string(.usageHigh))
                }
                .font(.system(size: compact ? 9 : 10, weight: .medium))
                .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                UsageHeatmapGridView(cells: cells, compact: compact, metric: metric)
                .padding(.vertical, 2)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.surfaceFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(theme.surfaceStroke, lineWidth: 1)
        )
    }

    private func legendSwatch(_ intensity: Double) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(theme.fillColor(for: intensity))
            .frame(width: compact ? 8 : 10, height: compact ? 8 : 10)
            .overlay(
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(
                        theme.strokeColor(for: intensity, isHovered: false),
                        lineWidth: intensity <= 0 ? 0.8 : 0.6
                    )
            )
    }
}

struct UsageHeatmapGridView: View {
    private struct HoveredCell: Equatable {
        var cell: UsageHeatmapCell
        var column: Int
        var row: Int
    }

    let cells: [UsageHeatmapCell]
    let compact: Bool
    let metric: UsageMetric
    var availableWidth: CGFloat? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var hoveredCell: HoveredCell?

    private var theme: UsageHeatmapTheme {
        UsageHeatmapTheme.make(for: colorScheme)
    }

    private var weeklyChunks: [[UsageHeatmapCell]] {
        stride(from: 0, to: cells.count, by: 7).map { start in
            Array(cells[start..<min(start + 7, cells.count)])
        }
    }

    private var maxMetricValue: Double {
        let values = cells.map { metricValue(for: $0) }
        return max(values.max() ?? 0, 1)
    }

    private var gridLayout: UsageHeatmapGridLayout {
        UsageHeatmapGridLayout.make(
            compact: compact,
            columnCount: weeklyChunks.count,
            availableWidth: availableWidth
        )
    }

    private var cellSize: CGFloat {
        gridLayout.cellSize
    }

    private var cellSpacing: CGFloat {
        gridLayout.cellSpacing
    }

    private var tooltipText: String? {
        guard let hoveredCell else { return nil }
        let valueText: String
        switch metric {
        case .tokens:
            valueText = UsageTokenFormatter.tooltipTokenText(hoveredCell.cell.tokens)
        case .costUSD:
            valueText = String(format: "$%.4f", hoveredCell.cell.costUSD)
        }
        return "\(valueText) on \(formattedTooltipDate(hoveredCell.cell.date))"
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(alignment: .top, spacing: cellSpacing) {
                ForEach(Array(weeklyChunks.enumerated()), id: \.offset) { columnIndex, week in
                    VStack(spacing: cellSpacing) {
                        ForEach(Array(week.enumerated()), id: \.element.id) { rowIndex, cell in
                            let cellIntensity = intensity(for: cell)
                            let isEmptyCell = cellIntensity <= 0
                            let isHovered = hoveredCell?.cell.id == cell.id
                            RoundedRectangle(cornerRadius: compact ? 2 : 3, style: .continuous)
                                .fill(theme.fillColor(for: cellIntensity))
                                .frame(width: cellSize, height: cellSize)
                                .overlay(
                                    RoundedRectangle(cornerRadius: compact ? 2 : 3, style: .continuous)
                                        .strokeBorder(
                                            theme.strokeColor(for: cellIntensity, isHovered: isHovered),
                                            lineWidth: isHovered ? 1 : (isEmptyCell ? 0.8 : 0.6)
                                        )
                                )
                                .shadow(
                                    color: isHovered ? theme.hoverGlow.opacity(colorScheme == .dark ? 0.22 : 0.12) : .clear,
                                    radius: isHovered ? 3 : 0,
                                    y: 0
                                )
                                .onHover { isHovering in
                                    if isHovering {
                                        hoveredCell = HoveredCell(
                                            cell: cell,
                                            column: columnIndex,
                                            row: rowIndex
                                        )
                                    } else if hoveredCell?.cell.id == cell.id {
                                        hoveredCell = nil
                                    }
                                }
                        }
                    }
                }
            }

            if let hoveredCell, let tooltipText {
                UsageTooltipBubbleView(compact: compact) {
                    Text(tooltipText)
                        .font(.system(size: compact ? 10 : 11, weight: .semibold))
                        .foregroundStyle(.white)
                }
                    .offset(
                        x: tooltipOffsetX(for: hoveredCell, text: tooltipText),
                        y: tooltipOffsetY(for: hoveredCell)
                    )
                    .zIndex(1)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: hoveredCell)
    }

    private func metricValue(for cell: UsageHeatmapCell) -> Double {
        metric == .tokens ? Double(cell.tokens) : cell.costUSD
    }

    private func intensity(for cell: UsageHeatmapCell) -> Double {
        metricValue(for: cell) / maxMetricValue
    }

    private func tooltipOffsetX(for hoveredCell: HoveredCell, text: String) -> CGFloat {
        let gridWidth = gridLayout.gridWidth(columnCount: weeklyChunks.count)
        let estimatedWidth = min(
            max(CGFloat(text.count) * (compact ? 5.6 : 6.4) + 24, compact ? 96 : 120),
            compact ? 190 : 240
        )
        let anchorX = CGFloat(hoveredCell.column) * (cellSize + cellSpacing) + cellSize / 2
        let proposedX = anchorX - estimatedWidth / 2
        return min(max(0, proposedX), max(0, gridWidth - estimatedWidth))
    }

    private func tooltipOffsetY(for hoveredCell: HoveredCell) -> CGFloat {
        let anchorY = CGFloat(hoveredCell.row) * (cellSize + cellSpacing)
        return anchorY - (compact ? 34 : 38)
    }

    private func formattedTooltipDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = "MMMM d"
        return formatter.string(from: date)
    }
}

struct UsageTooltipBubbleView<Content: View>: View {
    let compact: Bool
    let content: () -> Content

    @Environment(\.colorScheme) private var colorScheme

    init(compact: Bool, @ViewBuilder content: @escaping () -> Content) {
        self.compact = compact
        self.content = content
    }

    var body: some View {
        content()
            .padding(.horizontal, 10)
            .padding(.vertical, compact ? 6 : 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(colorScheme == .dark ? Color.black.opacity(0.94) : Color.black.opacity(0.84))
            )
    }
}
