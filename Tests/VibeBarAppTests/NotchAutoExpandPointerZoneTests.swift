import Testing
@testable import VibeBarApp

@Test func focusedAutoExpandBodyZoneDoesNotRevealFullPanel() {
    let decision = NotchAutoExpandPointerDecision.resolve(
        isFocusedAutoExpandActive: true,
        pointerInRevealZone: false,
        pointerInFocusedBodyZone: true,
        pointerInVisiblePanel: true
    )

    #expect(decision == .extendFocusedWindow)
}

@Test func focusedAutoExpandRevealZonePromotesToFullPanel() {
    let decision = NotchAutoExpandPointerDecision.resolve(
        isFocusedAutoExpandActive: true,
        pointerInRevealZone: true,
        pointerInFocusedBodyZone: false,
        pointerInVisiblePanel: true
    )

    #expect(decision == .revealFullPanel)
}

@Test func nonFocusedPointerInsideVisiblePanelKeepsRegularHoverBehavior() {
    let decision = NotchAutoExpandPointerDecision.resolve(
        isFocusedAutoExpandActive: false,
        pointerInRevealZone: false,
        pointerInFocusedBodyZone: false,
        pointerInVisiblePanel: true
    )

    #expect(decision == .pointerInsideVisiblePanel)
}

@Test func pointerOutsideAllZonesDoesNothingSpecial() {
    let decision = NotchAutoExpandPointerDecision.resolve(
        isFocusedAutoExpandActive: true,
        pointerInRevealZone: false,
        pointerInFocusedBodyZone: false,
        pointerInVisiblePanel: false
    )

    #expect(decision == .outside)
}
