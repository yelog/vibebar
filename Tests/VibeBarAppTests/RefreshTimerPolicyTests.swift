import Foundation
import Testing
@testable import VibeBarApp

@Test func modelRefreshTimerToleranceIsAtLeast15SecondsForReconciliation() {
    let tolerance60s = RefreshTimerPolicy.modelRefreshTolerance(for: 60)
    #expect(tolerance60s >= 15)
    #expect(tolerance60s <= 60)

    let tolerance120s = RefreshTimerPolicy.modelRefreshTolerance(for: 120)
    #expect(tolerance120s >= 15)
    #expect(tolerance120s <= 120)
}

@Test func cleanupTimerToleranceIsAtLeast30Seconds() {
    #expect(RefreshTimerPolicy.cleanupTimerTolerance >= 30)
}

@Test func usageTimerToleranceIsAtLeast10PercentOfCadence() {
    let tolerance = RefreshTimerPolicy.usageTolerance(for: 300)
    #expect(tolerance >= 30)
    #expect(tolerance <= 300)
}

@Test func timerTolerancesNeverExceedTheirIntervals() {
    for interval in [60.0, 120.0, 300.0] {
        let model = RefreshTimerPolicy.modelRefreshTolerance(for: interval)
        #expect(model >= 0)
        #expect(model <= interval)

        let usage = RefreshTimerPolicy.usageTolerance(for: interval)
        #expect(usage >= 0)
        #expect(usage <= interval)
    }
    #expect(RefreshTimerPolicy.cleanupTimerTolerance >= 0)
}