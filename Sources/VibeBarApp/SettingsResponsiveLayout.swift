import SwiftUI

enum SettingsResponsiveLayout {
    static func columnCount(
        availableWidth: CGFloat,
        minimumItemWidth: CGFloat,
        spacing: CGFloat,
        maxColumns: Int,
        minColumns: Int = 1
    ) -> Int {
        guard availableWidth > 0,
              minimumItemWidth > 0,
              spacing >= 0,
              maxColumns > 0,
              minColumns > 0 else {
            return max(1, minColumns)
        }

        let rawCount = Int((availableWidth + spacing) / (minimumItemWidth + spacing))
        let lowerBound = max(1, minColumns)
        return max(lowerBound, min(maxColumns, rawCount))
    }

    static func gridItems(columnCount: Int, spacing: CGFloat) -> [GridItem] {
        let resolvedCount = max(1, columnCount)
        return Array(
            repeating: GridItem(.flexible(), spacing: spacing, alignment: .leading),
            count: resolvedCount
        )
    }
}

struct ResponsiveGrid<Content: View>: View {
    let minimumItemWidth: CGFloat
    let spacing: CGFloat
    let maxColumns: Int
    let minColumns: Int
    let alignment: HorizontalAlignment
    private let content: (Int) -> Content

    @State private var availableWidth: CGFloat = 0

    init(
        minimumItemWidth: CGFloat,
        spacing: CGFloat,
        maxColumns: Int,
        minColumns: Int = 1,
        alignment: HorizontalAlignment = .leading,
        @ViewBuilder content: @escaping (Int) -> Content
    ) {
        self.minimumItemWidth = minimumItemWidth
        self.spacing = spacing
        self.maxColumns = maxColumns
        self.minColumns = minColumns
        self.alignment = alignment
        self.content = content
    }

    var body: some View {
        let columns = SettingsResponsiveLayout.columnCount(
            availableWidth: availableWidth,
            minimumItemWidth: minimumItemWidth,
            spacing: spacing,
            maxColumns: maxColumns,
            minColumns: minColumns
        )

        LazyVGrid(
            columns: SettingsResponsiveLayout.gridItems(columnCount: columns, spacing: spacing),
            alignment: alignment,
            spacing: spacing
        ) {
            content(columns)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: ResponsiveGridWidthPreferenceKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(ResponsiveGridWidthPreferenceKey.self) { width in
            if availableWidth != width {
                availableWidth = width
            }
        }
    }
}

private struct ResponsiveGridWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 {
            value = next
        }
    }
}
