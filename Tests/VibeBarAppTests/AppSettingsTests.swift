import Foundation
import Testing
@testable import VibeBarApp

@MainActor
@Test func sessionGroupingModeDefaultsToProjectForFreshPreferences() throws {
    let defaults = try #require(makeDefaultsSuite())

    let mode = AppSettings.loadSessionGroupingModeWithMigration(userDefaults: defaults)

    #expect(mode == .project)
    #expect(defaults.string(forKey: "sessionGroupingMode") == SessionGroupingMode.project.rawValue)
    #expect(defaults.object(forKey: "groupSessionsByTool") == nil)
}

@MainActor
@Test func sessionGroupingModeMigratesLegacyTrueToTool() throws {
    let defaults = try #require(makeDefaultsSuite())
    defaults.set(true, forKey: "groupSessionsByTool")

    let mode = AppSettings.loadSessionGroupingModeWithMigration(userDefaults: defaults)

    #expect(mode == .tool)
    #expect(defaults.string(forKey: "sessionGroupingMode") == SessionGroupingMode.tool.rawValue)
    #expect(defaults.object(forKey: "groupSessionsByTool") == nil)
}

@MainActor
@Test func sessionGroupingModeMigratesLegacyFalseToNone() throws {
    let defaults = try #require(makeDefaultsSuite())
    defaults.set(false, forKey: "groupSessionsByTool")

    let mode = AppSettings.loadSessionGroupingModeWithMigration(userDefaults: defaults)

    #expect(mode == .none)
    #expect(defaults.string(forKey: "sessionGroupingMode") == SessionGroupingMode.none.rawValue)
    #expect(defaults.object(forKey: "groupSessionsByTool") == nil)
}

@MainActor
@Test func sessionGroupingModePrefersPersistedModeOverLegacySetting() throws {
    let defaults = try #require(makeDefaultsSuite())
    defaults.set(SessionGroupingMode.project.rawValue, forKey: "sessionGroupingMode")
    defaults.set(true, forKey: "groupSessionsByTool")

    let mode = AppSettings.loadSessionGroupingModeWithMigration(userDefaults: defaults)

    #expect(mode == .project)
    #expect(defaults.string(forKey: "sessionGroupingMode") == SessionGroupingMode.project.rawValue)
}

private func makeDefaultsSuite() -> UserDefaults? {
    let suiteName = "AppSettingsTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        return nil
    }
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
