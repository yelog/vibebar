import AppKit
import SwiftUI
import VibeBarCore

struct SettingsShellView<Content: View>: View {
    @Binding var selectedPage: SettingsPage

    private let pages: [SettingsPage]
    private let content: (SettingsPage) -> Content
    private let sidebarWidth: CGFloat = 184
    private let sidebarSpacing: CGFloat = 6
    private let sidebarPadding: CGFloat = 16
    private let sidebarItemHeight: CGFloat = 36

    @ObservedObject private var l10n = L10n.shared
    @State private var hoveredPage: SettingsPage?

    init(
        selectedPage: Binding<SettingsPage>,
        pages: [SettingsPage] = SettingsPage.allCases,
        @ViewBuilder content: @escaping (SettingsPage) -> Content
    ) {
        self._selectedPage = selectedPage
        self.pages = pages
        self.content = content
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Divider()

            contentArea
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sidebar: some View {
        ScrollView(showsIndicators: true) {
            VStack(alignment: .leading, spacing: sidebarSpacing) {
                Text(l10n.string(.settings))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)

                ForEach(pages, id: \.id) { page in
                    pageButton(for: page)
                }

                Spacer(minLength: 0)
            }
            .padding(sidebarPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: sidebarWidth)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    private var contentArea: some View {
        Group {
            if selectedPage.presentation == .fullBleed {
                content(selectedPage)
            } else {
                ScrollView(showsIndicators: true) {
                    content(selectedPage)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.vertical, 20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(NSColor.windowBackgroundColor))
    }

    @ViewBuilder
    private func pageButton(for page: SettingsPage) -> some View {
        let selected = selectedPage == page
        let hovered = hoveredPage == page

        Button {
            selectedPage = page
        } label: {
            HStack(spacing: 10) {
                Image(systemName: page.iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 18, height: 18)

                Text(l10n.string(page.titleKey))
                    .font(.system(size: 13, weight: selected ? .semibold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)

                Spacer(minLength: 0)
            }
            .foregroundStyle(
                selected
                    ? Color.accentColor
                    : Color.primary.opacity(hovered ? 0.88 : 0.7)
            )
            .frame(maxWidth: .infinity, minHeight: sidebarItemHeight, alignment: .leading)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(backgroundFill(selected: selected, hovered: hovered))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(borderColor(selected: selected, hovered: hovered), lineWidth: selected ? 1.2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(page.shortcutEquivalent, modifiers: .command)
        .onHover { isHovering in
            hoveredPage = isHovering ? page : (hoveredPage == page ? nil : hoveredPage)
        }
    }

    private func backgroundFill(selected: Bool, hovered: Bool) -> Color {
        if selected {
            return Color.accentColor.opacity(0.14)
        }
        if hovered {
            return Color.white.opacity(0.06)
        }
        return .clear
    }

    private func borderColor(selected: Bool, hovered: Bool) -> Color {
        if selected {
            return Color.accentColor.opacity(0.45)
        }
        if hovered {
            return Color.white.opacity(0.16)
        }
        return .clear
    }
}
