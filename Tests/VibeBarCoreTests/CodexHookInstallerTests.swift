import Foundation
import Testing
@testable import VibeBarCore

@Test func codexHookInstallerWritesManagedHooksAndEnablesConfigFlag() throws {
    let fixture = try makeCodexHookFixture()
    defer { try? FileManager.default.removeItem(at: fixture.homeURL) }

    let installer = CodexHookInstaller(
        homeDirectory: fixture.homeURL,
        commandProvider: { "/tmp/vibebar codex-hook" },
        cliExistsProvider: { _ in true }
    )

    try installer.install()

    let hooks = try #require(fixture.loadHooks())
    for event in ["SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop", "PermissionRequest"] {
        let entries = try #require(hooks[event] as? [[String: Any]])
        #expect(entries.count == 1)
        let hookList = try #require(entries.first?["hooks"] as? [[String: Any]])
        let command = try #require(hookList.first?["command"] as? String)
        let timeout = try #require(hookList.first?["timeout"] as? Int)
        #expect(command == "/tmp/vibebar codex-hook")
        if event == "PermissionRequest" {
            #expect(timeout == 3600)
        } else {
            #expect(timeout == 5)
        }
    }

    let config = try #require(fixture.loadConfigToml())
    #expect(config.contains("[features]"))
    #expect(config.contains("codex_hooks = true"))
    #expect(installer.detect() == .installed)
}

@Test func codexHookInstallerDoesNotDuplicateManagedEntriesOnReinstall() throws {
    let fixture = try makeCodexHookFixture()
    defer { try? FileManager.default.removeItem(at: fixture.homeURL) }

    let installer = CodexHookInstaller(
        homeDirectory: fixture.homeURL,
        commandProvider: { "/tmp/vibebar codex-hook" },
        cliExistsProvider: { _ in true }
    )

    try installer.install()
    try installer.install()

    let hooks = try #require(fixture.loadHooks())
    for event in ["SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop", "PermissionRequest"] {
        let entries = try #require(hooks[event] as? [[String: Any]])
        let managedCount = entries.filter { entry in
            guard let hookList = entry["hooks"] as? [[String: Any]],
                  let command = hookList.first?["command"] as? String else {
                return false
            }
            return command == "/tmp/vibebar codex-hook"
        }.count
        #expect(managedCount == 1)
    }
}

@Test func codexHookInstallerUninstallKeepsForeignHooks() throws {
    let fixture = try makeCodexHookFixture()
    defer { try? FileManager.default.removeItem(at: fixture.homeURL) }

    try fixture.writeHooks(
        [
            "hooks": [
                "SessionStart": [
                    [
                        "hooks": [[
                            "type": "command",
                            "command": "foreign-hook",
                            "timeout": 9,
                        ]],
                    ],
                ],
            ],
        ]
    )

    let installer = CodexHookInstaller(
        homeDirectory: fixture.homeURL,
        commandProvider: { "/tmp/vibebar codex-hook" },
        cliExistsProvider: { _ in true }
    )

    try installer.install()
    try installer.uninstall()

    let hooks = try #require(fixture.loadHooks())
    let sessionStartEntries = try #require(hooks["SessionStart"] as? [[String: Any]])
    #expect(sessionStartEntries.count == 1)
    let foreignHooks = try #require(sessionStartEntries.first?["hooks"] as? [[String: Any]])
    #expect(foreignHooks.first?["command"] as? String == "foreign-hook")
    #expect(hooks["Stop"] == nil)
}

@Test func codexHookInstallerReportsCliNotFoundWithoutCodexHomeOrBinary() throws {
    let fixture = try makeCodexHookFixture()
    defer { try? FileManager.default.removeItem(at: fixture.homeURL) }

    let installer = CodexHookInstaller(
        homeDirectory: fixture.homeURL,
        commandProvider: { "/tmp/vibebar codex-hook" },
        cliExistsProvider: { _ in false }
    )

    #expect(installer.detect() == .cliNotFound)
}

private struct CodexHookFixture {
    let homeURL: URL

    var codexURL: URL {
        homeURL.appendingPathComponent(".codex", isDirectory: true)
    }

    var hooksURL: URL {
        codexURL.appendingPathComponent("hooks.json", isDirectory: false)
    }

    var configURL: URL {
        codexURL.appendingPathComponent("config.toml", isDirectory: false)
    }

    func writeHooks(_ json: [String: Any]) throws {
        try FileManager.default.createDirectory(at: codexURL, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: hooksURL, options: .atomic)
    }

    func loadHooks() -> [String: Any]? {
        guard let data = try? Data(contentsOf: hooksURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            return nil
        }
        return hooks
    }

    func loadConfigToml() -> String? {
        try? String(contentsOf: configURL, encoding: .utf8)
    }
}

private func makeCodexHookFixture() throws -> CodexHookFixture {
    let homeURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)
    return CodexHookFixture(homeURL: homeURL)
}
