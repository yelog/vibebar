import SwiftUI
import VibeBarCore

struct StatusGlyph: View {
    let summary: GlobalSummary
    @Environment(\.colorScheme) private var colorScheme

    private struct Slice: Identifiable {
        let id = UUID()
        let state: ToolActivityState
        let start: Double
        let end: Double
    }

    private let ringStates: [ToolActivityState] = [.running, .awaitingInput, .idle]

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
                .stroke(baseRingColor, lineWidth: 3)

            ForEach(slices) { slice in
                ArcSegment(start: slice.start, end: slice.end)
                    .stroke(color(for: slice.state), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }

            Text(centerText)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(Color.primary.opacity(summary.total > 0 ? 1 : 0.9))
        }
        .frame(width: 18, height: 18)
        .accessibilityLabel("VibeBar 会话总数 \(summary.total)")
    }

    private var centerText: String {
        summary.total > 0 ? "\(min(summary.total, 99))" : "0"
    }

    private var baseRingColor: Color {
        summary.total > 0 ? Color.gray.opacity(0.25) : Color.primary.opacity(0.55)
    }

    private func color(for state: ToolActivityState) -> Color {
        AppSettings.shared.swiftUIColor(for: state, colorScheme: colorScheme)
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
