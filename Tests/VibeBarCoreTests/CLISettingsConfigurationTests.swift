import Testing
@testable import VibeBarCore

@Test func opencodeDefaultDetectionMethodsIncludeProcessScanFallback() {
    #expect(
        CLIToolConfiguration.defaultMethods(for: .opencode) == [.plugin, .httpAPI, .processScan]
    )
}
