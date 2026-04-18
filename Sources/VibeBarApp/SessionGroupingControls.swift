import SwiftUI

struct SessionGroupingModeSwitcher: View {
    @Binding var selection: SessionGroupingMode
    var compact: Bool = true
    var appearance: PanelChromeAppearance = .standard

    var body: some View {
        HStack(spacing: appearance == .notch ? 2 : 3) {
            ForEach(SessionGroupingMode.allCases) { mode in
                Button {
                    selection = mode
                } label: {
                    Text(mode.displayName)
                        .font(.system(size: compact ? 10 : 11, weight: selection == mode ? .semibold : .medium))
                        .foregroundStyle(textColor(for: mode))
                        .padding(.horizontal, compact ? 8 : 10)
                        .padding(.vertical, compact ? 4 : 5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(selection == mode ? selectedFillColor : Color.clear)
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(
                                    selection == mode ? selectedBorderColor : Color.clear,
                                    lineWidth: 1
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(appearance == .notch ? 2.5 : 3)
        .background(
            Capsule(style: .continuous)
                .fill(trackFillColor)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(trackBorderColor, lineWidth: 1)
        )
    }

    private func textColor(for mode: SessionGroupingMode) -> Color {
        switch appearance {
        case .standard:
            return selection == mode ? Color.primary : Color.secondary
        case .notch:
            return selection == mode ? NotchPanelStyle.primaryTextColor : NotchPanelStyle.secondaryTextColor
        }
    }

    private var selectedFillColor: Color {
        switch appearance {
        case .standard:
            return Color.primary.opacity(0.12)
        case .notch:
            return NotchPanelStyle.surfaceCard
        }
    }

    private var selectedBorderColor: Color {
        switch appearance {
        case .standard:
            return Color.clear
        case .notch:
            return NotchPanelStyle.strokeColor
        }
    }

    private var trackFillColor: Color {
        switch appearance {
        case .standard:
            return Color.primary.opacity(0.06)
        case .notch:
            return NotchPanelStyle.surfaceElevated
        }
    }

    private var trackBorderColor: Color {
        switch appearance {
        case .standard:
            return Color.primary.opacity(0.08)
        case .notch:
            return NotchPanelStyle.strokeColor
        }
    }
}

struct SessionSectionHeaderView: View {
    let title: String
    @Binding var selection: SessionGroupingMode
    var compact: Bool = true
    var appearance: PanelChromeAppearance = .standard

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: compact ? 13 : 14, weight: .semibold))
                .foregroundStyle(headerTextColor)

            Spacer(minLength: 8)

            SessionGroupingModeSwitcher(selection: $selection, compact: compact, appearance: appearance)
        }
    }

    private var headerTextColor: Color {
        switch appearance {
        case .standard:
            return .primary
        case .notch:
            return NotchPanelStyle.primaryTextColor
        }
    }
}
