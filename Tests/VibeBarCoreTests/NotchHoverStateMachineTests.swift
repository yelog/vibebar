import Testing
@testable import VibeBarCore

@Test func notchHoverSchedulesExpandAfterEnteringHotZone() {
    var machine = NotchHoverStateMachine()

    let effect = machine.reduce(.pointerEnteredHotZone)

    #expect(effect == .scheduleExpand)
}

@Test func notchHoverSchedulesCollapseAfterLeavingExpandedZones() {
    var machine = NotchHoverStateMachine()
    _ = machine.reduce(.pointerEnteredHotZone)
    _ = machine.reduce(.expandTimerFired)

    let effect = machine.reduce(.pointerExitedAllZones)

    #expect(effect == .scheduleCollapse)
}

@Test func notchHoverCancelsPendingCollapseWhenPointerReenters() {
    var machine = NotchHoverStateMachine()
    _ = machine.reduce(.pointerEnteredHotZone)
    _ = machine.reduce(.expandTimerFired)
    _ = machine.reduce(.pointerExitedAllZones)

    let effect = machine.reduce(.pointerEnteredHotZone)

    #expect(effect == .cancelCollapse)
}

@Test func notchHoverExpandsWhenExpandTimerFiresFromPendingExpand() {
    var machine = NotchHoverStateMachine()
    _ = machine.reduce(.pointerEnteredHotZone)

    let effect = machine.reduce(.expandTimerFired)

    #expect(effect == .expandNow)
}

@Test func notchHoverIgnoresStrayTimersInCollapsedState() {
    var machine = NotchHoverStateMachine()

    #expect(machine.reduce(.expandTimerFired) == .none)
    #expect(machine.reduce(.collapseTimerFired) == .none)
}
