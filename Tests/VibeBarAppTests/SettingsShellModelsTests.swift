import Testing
@testable import VibeBarApp

@Test func settingsPageOrderMatchesProductDecision() {
    #expect(SettingsPage.allCases == [.general, .cli, .appearance, .usage, .hooks, .about])
}

@Test func settingsPageMetadataMatchesNavigationShell() {
    #expect(SettingsPage.general.titleKey == .tabGeneral)
    #expect(SettingsPage.cli.titleKey == .tabCLI)
    #expect(SettingsPage.usage.titleKey == .tabUsage)
    #expect(SettingsPage.about.titleKey == .tabAbout)
    #expect(SettingsPage.cli.iconName == "terminal.fill")
    #expect(SettingsPage.hooks.shortcutKey == "5")
}

@Test func settingsPagePresentationDistinguishesCliFromStandardPages() {
    #expect(SettingsPage.cli.presentation == .fullBleed)
    #expect(SettingsPage.general.presentation == .standardScrollable)
    #expect(SettingsPage.appearance.presentation == .standardScrollable)
}

@Test func settingsWindowPolicyUsesSingleResizableLayout() {
    let policy = SettingsWindowPolicy.default

    #expect(policy.defaultContentSize.width == 780)
    #expect(policy.defaultContentSize.height == 700)
    #expect(policy.minContentSize.width == 720)
    #expect(policy.minContentSize.height == 620)
    #expect(policy.maxContentSize.width == 1100)
    #expect(policy.maxContentSize.height == 900)
    #expect(policy.resizesPerPage == false)
}
