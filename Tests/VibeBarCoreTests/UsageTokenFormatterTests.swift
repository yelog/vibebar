import Testing
@testable import VibeBarCore

@Test func tokenFormatterKeepsSmallValuesUnchanged() {
    #expect(UsageTokenFormatter.tooltipTokenText(0) == "0 tokens")
    #expect(UsageTokenFormatter.tooltipTokenText(1) == "1 token")
    #expect(UsageTokenFormatter.tooltipTokenText(999) == "999 tokens")
}

@Test func tokenFormatterUsesCompactUnits() {
    #expect(UsageTokenFormatter.tooltipTokenText(1_000) == "1K tokens")
    #expect(UsageTokenFormatter.tooltipTokenText(12_345) == "12K tokens")
    #expect(UsageTokenFormatter.tooltipTokenText(1_000_000) == "1M tokens")
    #expect(UsageTokenFormatter.tooltipTokenText(296_125_188) == "296M tokens")
    #expect(UsageTokenFormatter.tooltipTokenText(7_873_569_111) == "8B tokens")
}

@Test func tokenFormatterPromotesRoundedBoundaryValues() {
    #expect(UsageTokenFormatter.tooltipTokenText(999_950) == "1M tokens")
    #expect(UsageTokenFormatter.tooltipTokenText(999_950_000) == "1B tokens")
}
