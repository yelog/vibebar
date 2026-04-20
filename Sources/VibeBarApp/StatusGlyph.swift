import SwiftUI
import VibeBarCore

struct StatusGlyph: View {
    let summary: GlobalSummary

    private struct Slice: Identifiable {
        let id = UUID()
        let state: ToolActivityState
        let start: Double
        let end: Double
    }

    private let ringStates: [ToolActivityState] = [.running, .awaitingInput, .completed, .idle]

    private var slices: [Slice] {
        guard summary.total > 0 else { return [] }
        var current = 0.0
        var result: [Slice] = []

        for state in ringStates {
            let count = summary.counts[state, default: 0]
            guard count > 0 else { continue }
            let fraction = Double(count) / Double(summary.total)
            let next = current + fraction
            result.append(Slice(state: state, start: current, end: next))
            current = next
        }

        return result
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(baseRingColor, lineWidth: 2.5)

            ForEach(slices) { slice in
                ArcSegment(start: slice.start, end: slice.end)
                    .stroke(color(for: slice.state), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }

            Text(centerText)
                .font(.system(size: 7.5, weight: .bold, design: .rounded))
                .foregroundStyle(NotchPanelStyle.primaryTextColor.opacity(summary.total > 0 ? 0.96 : 0.8))
        }
        .frame(width: 16, height: 16)
        .accessibilityLabel(L10n.shared.string(.accessibilityFmt, summary.total))
    }

    private var centerText: String {
        summary.total > 0 ? "\(min(summary.total, 99))" : "0"
    }

    private var baseRingColor: Color {
        summary.total > 0 ? NotchPanelStyle.neutralAccentColor.opacity(0.24) : NotchPanelStyle.secondaryTextColor.opacity(0.4)
    }

    private func color(for state: ToolActivityState) -> Color {
        NotchPanelStyle.color(for: state)
    }
}

private struct ArcSegment: Shape {
    let start: Double
    let end: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * 0.5 - 1.5

        let startAngle = Angle.degrees(start * 360 - 90)
        let endAngle = Angle.degrees(end * 360 - 90)

        path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        return path
    }
}
