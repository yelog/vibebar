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
    #expect(model.hostingReferenceFrame == collapsedFrame)
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
    #expect(model.hostingReferenceFrame == expandedFrame)
}

@Test func collapsedPhaseHidesExpandedBody() {
    let model = NotchPanelLayoutModel(phase: .collapsed)

    #expect(model.showsExpandedBody == false)
    #expect(model.showsPanelBackground == false)
}

@Test func collapsingPhaseKeepsExpandedBodyVisible() {
    let model = NotchPanelLayoutModel(phase: .collapsing)

    #expect(model.showsExpandedBody)
    #expect(model.bodyOpacity > 0)
    #expect(model.bodyOpacity < 1)
    #expect(model.bodyBlurRadius > 0)
    #expect(model.bodyOffsetY < 0)
}

@Test func expandingPhaseKeepsBodyNonInteractiveUntilSettled() {
    let model = NotchPanelLayoutModel(phase: .expanding)

    #expect(model.showsExpandedBody)
    #expect(model.allowsBodyHitTesting == false)
    #expect(model.usesExpandedHitFrame)
    #expect(model.usesBridgeTopShellPresentation)
    #expect(model.bodyOpacity > 0)
    #expect(model.bodyOpacity < 1)
    #expect(model.bodyScale < 1)
    #expect(model.surfaceOpacity < 1)
}

@Test func expandedPhaseUsesFullySettledRevealValues() {
    let model = NotchPanelLayoutModel(phase: .expanded)

    #expect(model.bodyOpacity == 1)
    #expect(model.bodyOffsetY == 0)
    #expect(model.bodyBlurRadius == 0)
    #expect(model.bodyScale == 1)
    #expect(model.surfaceOpacity == 1)
}

@Test func collapsingPhaseKeepsBridgeTopShellPresentationForWidthContinuity() {
    let model = NotchPanelLayoutModel(phase: .collapsing)

    #expect(model.usesBridgeTopShellPresentation)
}

@Test func collapsedPhaseUsesCollapsedTopShellPresentation() {
    let model = NotchPanelLayoutModel(phase: .collapsed)

    #expect(model.usesBridgeTopShellPresentation == false)
}
