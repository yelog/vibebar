import Testing
@testable import VibeBarCore

@Test func opencodeDefaultDetectionMethodsIncludeProcessScanFallback() {
    #expect(
        CLIToolConfiguration.defaultMethods(for: .opencode) == [.plugin, .httpAPI, .processScan]
    )
}

@Test func codexDefaultDetectionMethodsPreferHookThenSessionFileThenProcessScan() {
    #expect(
        CLIToolConfiguration.defaultMethods(for: .codex) == [.hook, .sessionFile, .processScan]
    )
}

@Test func codexAvailableDetectionMethodsIncludeHook() {
    #expect(
        CLIToolConfiguration.availableMethods(for: .codex) == [.hook, .sessionFile, .processScan]
    )
}
