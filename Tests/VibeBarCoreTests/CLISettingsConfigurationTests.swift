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

@Test func piDefaultDetectionMethodsUsePluginThenProcessScan() {
    #expect(
        CLIToolConfiguration.defaultMethods(for: .pi) == [.plugin, .processScan]
    )
    #expect(
        CLIToolConfiguration.availableMethods(for: .pi) == [.plugin, .processScan]
    )
    #expect(CLIToolConfiguration.hasPluginSupport(for: .pi))
}

@Test func ohMyPiDefaultDetectionMethodsUsePluginThenProcessScan() {
    #expect(
        CLIToolConfiguration.defaultMethods(for: .ohMyPi) == [.plugin, .processScan]
    )
    #expect(
        CLIToolConfiguration.availableMethods(for: .ohMyPi) == [.plugin, .processScan]
    )
    #expect(CLIToolConfiguration.hasPluginSupport(for: .ohMyPi))
}

@Test func migrationInsertsPiFamilyDefaultsWithoutOverwritingExistingTools() {
    var configs: [ToolKind: CLIToolConfiguration] = [
        .claudeCode: CLIToolConfiguration(
            tool: .claudeCode,
            isEnabled: false,
            enabledDetectionMethods: [.transcriptFile],
            pluginEnabled: true
        ),
        .opencode: CLIToolConfiguration(
            tool: .opencode,
            isEnabled: true,
            enabledDetectionMethods: [.httpAPI],
            pluginEnabled: false
        ),
    ]

    CLIToolConfiguration.migratePiFamilyDefaults(&configs)

    #expect(configs[.claudeCode]?.isEnabled == false)
    #expect(configs[.claudeCode]?.enabledDetectionMethods == [.transcriptFile])
    #expect(configs[.opencode]?.enabledDetectionMethods == [.httpAPI])

    #expect(configs[.pi]?.isEnabled == true)
    #expect(configs[.pi]?.enabledDetectionMethods == [.plugin, .processScan])
    #expect(configs[.ohMyPi]?.isEnabled == true)
    #expect(configs[.ohMyPi]?.enabledDetectionMethods == [.plugin, .processScan])
}

@Test func migrationDoesNotOverwriteExistingPiFamilyConfigs() {
    var configs: [ToolKind: CLIToolConfiguration] = [
        .pi: CLIToolConfiguration(
            tool: .pi,
            isEnabled: false,
            enabledDetectionMethods: [.processScan],
            pluginEnabled: false
        ),
    ]

    CLIToolConfiguration.migratePiFamilyDefaults(&configs)

    #expect(configs[.pi]?.isEnabled == false)
    #expect(configs[.pi]?.enabledDetectionMethods == [.processScan])
    #expect(configs[.ohMyPi]?.enabledDetectionMethods == [.plugin, .processScan])
}
