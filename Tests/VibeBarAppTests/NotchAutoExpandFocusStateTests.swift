import Testing
@testable import VibeBarApp

@Test func notchAutoExpandFocusStateStoresFocusedSessionID() {
    var focusState = NotchAutoExpandFocusState()

    focusState.begin(sessionID: "session-123")

    #expect(focusState.focusedSessionID == "session-123")
}

@Test func notchAutoExpandFocusStateClearsFocusWhenRevealingFullPanel() {
    var focusState = NotchAutoExpandFocusState()
    focusState.begin(sessionID: "session-123")

    let changed = focusState.revealFullPanel()

    #expect(changed)
    #expect(focusState.focusedSessionID == nil)
}

@Test func notchAutoExpandFocusStateNoOpsWhenAlreadyFullPanel() {
    var focusState = NotchAutoExpandFocusState()

    let changed = focusState.revealFullPanel()

    #expect(changed == false)
    #expect(focusState.focusedSessionID == nil)
}
