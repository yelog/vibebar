import Testing
@testable import VibeBarApp

@Test func responsiveColumnCountShrinksOnNarrowWidths() {
    #expect(
        SettingsResponsiveLayout.columnCount(
            availableWidth: 420,
            minimumItemWidth: 140,
            spacing: 10,
            maxColumns: 4
        ) == 2
    )
}

@Test func responsiveColumnCountExpandsWithinUpperBound() {
    #expect(
        SettingsResponsiveLayout.columnCount(
            availableWidth: 760,
            minimumItemWidth: 140,
            spacing: 10,
            maxColumns: 4
        ) == 4
    )
}

@Test func responsiveColumnCountClampsToAtLeastOne() {
    #expect(
        SettingsResponsiveLayout.columnCount(
            availableWidth: 0,
            minimumItemWidth: 140,
            spacing: 10,
            maxColumns: 4
        ) == 1
    )
}
