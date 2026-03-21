import SwiftUI
import VibeBarCore

struct NotchCollapsedView: View {
    let summary: GlobalSummary

    @Environment(\.colorScheme) private var colorScheme

    private struct StateBadge: Identifiable {
        let state: ToolActivityState
        let count: Int
        let id: String
    }

    private var orderedStates: [ToolActivityState] {
        [.running, .awaitingInput, .idle, .unknown]
    }

    private var primaryState: ToolActivityState {
        orderedStates.first { summary.counts[$0, default: 0] > 0 } ?? .unknown
    }

    private var secondaryBadges: [StateBadge] {
        orderedStates
            .filter { $0 != primaryState }
            .compactMap { state in
                let count = summary.counts[state, default: 0]
                guard count > 0 else { return nil }
                return StateBadge(state: state, count: count, id: state.rawValue)
            }
            .prefix(2)
            .map { $0 }
    }

    private var totalText: String {
        summary.total > 99 ? "99+" : "\(summary.total)"
    }

    var body: some View {
        HStack(spacing: 10) {
            stateMark(for: primaryState)

            Text(totalText)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.95))
                .frame(minWidth: 24)

            HStack(spacing: 4) {
                ForEach(secondaryBadges) { badge in
                    stateDot(for: badge.state)
                        .help("\(badge.state.displayName) \(badge.count)")
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 22)
        .background(
            Capsule(style: .continuous)
                .fill(backgroundFill)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(L10n.shared.string(.accessibilityFmt, summary.total)))
    }

    private var backgroundFill: some ShapeStyle {
        LinearGradient(
            colors: [
                Color(red: 0.10, green: 0.10, blue: 0.11),
                Color(red: 0.05, green: 0.05, blue: 0.06),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    @ViewBuilder
    private func stateMark(for state: ToolActivityState) -> some View {
        let color = AppSettings.shared.swiftUIColor(for: state, colorScheme: colorScheme)
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(color.opacity(0.95))
            .frame(width: 10, height: 10)
            .shadow(color: color.opacity(0.35), radius: 4, x: 0, y: 0)
    }

    @ViewBuilder
    private func stateDot(for state: ToolActivityState) -> some View {
        let color = AppSettings.shared.swiftUIColor(for: state, colorScheme: colorScheme)
        Circle()
            .fill(color.opacity(0.95))
            .frame(width: 6, height: 6)
            .shadow(color: color.opacity(0.25), radius: 3, x: 0, y: 0)
    }
}
