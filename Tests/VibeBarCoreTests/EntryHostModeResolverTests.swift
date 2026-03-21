import Testing
@testable import VibeBarCore

@Test func entryHostModeResolvesToNotchWhenEnabledAndPrimaryDisplaySupportsNotch() {
    let mode = EntryHostModeResolver.resolve(
        preferenceEnabled: true,
        primaryDisplaySupportsNotch: true,
        temporarilyBlocked: false
    )

    #expect(mode == .notch)
}

@Test func entryHostModeFallsBackToMenuBarWhenPreferenceDisabled() {
    let mode = EntryHostModeResolver.resolve(
        preferenceEnabled: false,
        primaryDisplaySupportsNotch: true,
        temporarilyBlocked: false
    )

    #expect(mode == .menuBar)
}

@Test func entryHostModeFallsBackToMenuBarWhenPrimaryDisplayHasNoNotch() {
    let mode = EntryHostModeResolver.resolve(
        preferenceEnabled: true,
        primaryDisplaySupportsNotch: false,
        temporarilyBlocked: false
    )

    #expect(mode == .menuBar)
}

@Test func entryHostModeFallsBackToMenuBarWhenTemporarilyBlocked() {
    let mode = EntryHostModeResolver.resolve(
        preferenceEnabled: true,
        primaryDisplaySupportsNotch: true,
        temporarilyBlocked: true
    )

    #expect(mode == .menuBar)
}
