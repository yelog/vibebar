import SwiftUI
import VibeBarCore

struct UsageHeatmapView: View {
    let cells: [UsageHeatmapCell]
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom) {
                Text("Recent 52 weeks")
                    .font(.system(size: compact ? 10 : 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                HStack(spacing: 6) {
                    Text("Low")
                    legendSwatch(0.18)
                    legendSwatch(0.45)
                    legendSwatch(0.72)
                    legendSwatch(1.0)
                    Text("High")
                }
                .font(.system(size: compact ? 9 : 10, weight: .medium))
                .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: compact ? 3 : 4) {
                    ForEach(weeklyChunks.indices, id: \.self) { index in
                        VStack(spacing: compact ? 3 : 4) {
                            ForEach(weeklyChunks[index]) { cell in
                                RoundedRectangle(cornerRadius: compact ? 2 : 3, style: .continuous)
                                    .fill(fillColor(for: cell.intensity))
                                    .frame(width: compact ? 8 : 10, height: compact ? 8 : 10)
                                    .help("\(formattedDate(cell.date))\nTokens: \(cell.tokens)")
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
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

    private var weeklyChunks: [[UsageHeatmapCell]] {
        stride(from: 0, to: cells.count, by: 7).map { start in
            Array(cells[start..<min(start + 7, cells.count)])
        }
    }

    private func legendSwatch(_ intensity: Double) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(fillColor(for: intensity))
            .frame(width: compact ? 8 : 10, height: compact ? 8 : 10)
    }

    private func fillColor(for intensity: Double) -> Color {
        let normalized = min(max(intensity, 0), 1)
        return Color(
            red: 0.17 + normalized * 0.10,
            green: 0.30 + normalized * 0.46,
            blue: 0.22 + normalized * 0.18
        )
        .opacity(0.18 + normalized * 0.82)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}
