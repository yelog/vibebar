import AppKit
import Testing
@testable import VibeBarApp

@Test func collapsingKeepsTopShellVisibleAndDisablesBodyHitTesting() {
    let model = NotchPanelLayoutModel(phase: .collapsing)

    #expect(model.showsTopShell)
    #expect(model.allowsBodyHitTesting == false)
}

@Test func collapsedTargetFrameUsesCollapsedWindowFrame() {
    let collapsedFrame = NSRect(x: 100, y: 10, width: 268, height: 42)
    let expandedFrame = NSRect(x: 40, y: -180, width: 440, height: 240)
    let model = NotchPanelLayoutModel(
        phase: .collapsed,
        collapsedFrame: collapsedFrame,
        expandedFrame: expandedFrame
    )

    #expect(model.targetFrame == collapsedFrame)
    #expect(model.hostingSize == collapsedFrame.size)
}

@Test func collapsingTargetFrameReturnsToCollapsedWindowFrame() {
    let collapsedFrame = NSRect(x: 100, y: 10, width: 268, height: 42)
    let expandedFrame = NSRect(x: 40, y: -180, width: 440, height: 240)
    let model = NotchPanelLayoutModel(
        phase: .collapsing,
        collapsedFrame: collapsedFrame,
        expandedFrame: expandedFrame
    )

    #expect(model.targetFrame == collapsedFrame)
    #expect(model.hostingSize == expandedFrame.size)
}

@Test func collapsedPhaseHidesExpandedBody() {
    let model = NotchPanelLayoutModel(phase: .collapsed)

    #expect(model.showsExpandedBody == false)
    #expect(model.showsPanelBackground == false)
}

@Test func collapsingPhaseKeepsExpandedBodyVisible() {
    let model = NotchPanelLayoutModel(phase: .collapsing)

    #expect(model.showsExpandedBody)
    #expect(model.bodyOpacity == 0.92)
}

@Test func expandingPhaseKeepsBodyNonInteractiveUntilSettled() {
    let model = NotchPanelLayoutModel(phase: .expanding)

    #expect(model.showsExpandedBody)
    #expect(model.allowsBodyHitTesting == false)
    #expect(model.usesExpandedHitFrame)
}
