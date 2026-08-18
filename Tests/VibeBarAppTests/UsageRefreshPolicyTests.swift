import Foundation
import Testing
@testable import VibeBarApp

@Test func usageRefreshReasonInitialDoesNotForceFullRefresh() {
    #expect(UsageRefreshReason.initial.forcesFullRefresh == false)
}

@Test func usageRefreshReasonAutomaticDoesNotForceFullRefresh() {
    #expect(UsageRefreshReason.automatic.forcesFullRefresh == false)
}

@Test func usageRefreshReasonManualDoesNotForceFullRefresh() {
    #expect(UsageRefreshReason.manual.forcesFullRefresh == false)
}

@Test func usageRefreshReasonForceFullForcesFullRefresh() {
    #expect(UsageRefreshReason.forceFull.forcesFullRefresh == true)
}

@Test func usageRefreshReasonCacheResetForcesFullRefresh() {
    #expect(UsageRefreshReason.cacheReset.forcesFullRefresh == true)
}

@Test func usageRefreshReasonStrongestWins() {
    #expect(UsageRefreshReason.strongest(.automatic, .manual) == .manual)
    #expect(UsageRefreshReason.strongest(.initial, .automatic) == .automatic)
    #expect(UsageRefreshReason.strongest(.manual, .forceFull) == .forceFull)
    #expect(UsageRefreshReason.strongest(.forceFull, .cacheReset) == .cacheReset)
    #expect(UsageRefreshReason.strongest(.cacheReset, .automatic) == .cacheReset)
}