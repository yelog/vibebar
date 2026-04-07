import SwiftUI

struct SessionGroupingModeSwitcher: View {
    @Binding var selection: SessionGroupingMode
    var compact: Bool = true

    var body: some View {
        HStack(spacing: 3) {
            ForEach(SessionGroupingMode.allCases) { mode in
                Button {
                    selection = mode
                } label: {
                    Text(mode.displayName)
                        .font(.system(size: compact ? 10 : 11, weight: selection == mode ? .semibold : .medium))
                        .foregroundStyle(selection == mode ? Color.primary : Color.secondary)
                        .padding(.horizontal, compact ? 8 : 10)
                        .padding(.vertical, compact ? 4 : 5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(selection == mode ? Color.primary.opacity(0.12) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

struct SessionSectionHeaderView: View {
    let title: String
    @Binding var selection: SessionGroupingMode
    var compact: Bool = true

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: compact ? 13 : 14, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            SessionGroupingModeSwitcher(selection: $selection, compact: compact)
        }
    }
}
