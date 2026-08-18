import Foundation
import Testing
@testable import VibeBarCore

private final class PluginDetectorFixture {
    let tempRoot: URL
    let home: URL
    let plugins: URL
    let installer: PiFamilyExtensionInstaller

    init() {
        let temp = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        tempRoot = temp.appendingPathComponent("PluginDetectorTests-\(UUID().uuidString)")
        home = tempRoot.appendingPathComponent("home")
        plugins = tempRoot.appendingPathComponent("plugins")
        installer = PiFamilyExtensionInstaller(
            homeDirectory: home,
            pluginsDirectory: plugins,
            bundledVersion: "0.1.0",
            cliExists: { _ in true }
        )
        writePluginSource()
    }

    func writePluginSource() {
        let root = plugins.appendingPathComponent("pi-vibebar-extension")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? "runtime".write(to: root.appendingPathComponent("runtime.js"), atomically: true, encoding: .utf8)
        for dir in ["pi", "omp"] {
            let adapter = root.appendingPathComponent(dir)
            try? FileManager.default.createDirectory(at: adapter, withIntermediateDirectories: true)
            try? "adapter".write(to: adapter.appendingPathComponent("index.ts"), atomically: true, encoding: .utf8)
        }
    }

    func makePiAgentDir() {
        try? FileManager.default.createDirectory(
            at: home.appendingPathComponent(".pi/agent"),
            withIntermediateDirectories: true
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: tempRoot)
    }
}

private final class TestScope {
    let fixture: PluginDetectorFixture
    init() { fixture = PluginDetectorFixture() }
    deinit { fixture.cleanup() }
}

@Test func visibleItemsIncludesPiFamilyWhenCLIsPresent() {
    let scope = TestScope()
    let report = PluginStatusReport(
        claudeCode: .cliNotFound,
        opencode: .installed,
        pi: .notInstalled,
        ohMyPi: .partialInstalled(installed: 1, total: 2)
    )
    let items = report.visibleItems
    #expect(items.count == 3)
    #expect(items.map(\.tool) == [.opencode, .pi, .ohMyPi])
}

@Test func visibleItemsExcludesPiFamilyWhenCLIsMissing() {
    let report = PluginStatusReport(
        claudeCode: .cliNotFound,
        opencode: .cliNotFound,
        pi: .cliNotFound,
        ohMyPi: .cliNotFound
    )
    #expect(report.visibleItems.isEmpty)
}

@Test func needsActionIncludesPartialInstallation() {
    #expect(PluginInstallStatus.partialInstalled(installed: 1, total: 2).needsAction)
    #expect(!PluginInstallStatus.installed.needsAction)
}

@Test func piFamilyInstallAndDetectRoundTrip() async {
    let scope = TestScope()
    let detector = PluginDetector(piFamilyInstaller: scope.fixture.installer)

    #expect(await detector.detectPiPlugin() == .notInstalled)
    #expect(await detector.detectOhMyPiPlugin() == .notInstalled)

    try? await detector.installPiPlugin()
    #expect(await detector.detectPiPlugin() == .installed)
    #expect(await detector.detectOhMyPiPlugin() == .notInstalled)

    try? await detector.installOhMyPiPlugin()
    #expect(await detector.detectOhMyPiPlugin() == .installed)

    try? await detector.uninstallPiPlugin()
    #expect(await detector.detectPiPlugin() == .notInstalled)
    #expect(await detector.detectOhMyPiPlugin() == .installed)
}

@Test func detectAllReportsAllFourTools() async {
    let scope = TestScope()
    let detector = PluginDetector(piFamilyInstaller: scope.fixture.installer)

    let report = await detector.detectAll()
    #expect(report.claudeCode != .checking)
    #expect(report.opencode != .checking)
    #expect(report.pi != .checking)
    #expect(report.ohMyPi != .checking)
}

@Test func ompPartialProfileInstallationMapsToPartialStatus() async throws {
    let scope = TestScope()
    scope.fixture.makePiAgentDir()
    let detector = PluginDetector(piFamilyInstaller: scope.fixture.installer)

    try await detector.installOhMyPiPlugin()
    let defaultAgent = scope.fixture.home.appendingPathComponent(".omp/agent")
    try? FileManager.default.createDirectory(at: defaultAgent, withIntermediateDirectories: true)
    let workAgent = scope.fixture.home.appendingPathComponent(".omp/profiles/work/agent")
    try? FileManager.default.createDirectory(at: workAgent, withIntermediateDirectories: true)

    #expect(await detector.detectOhMyPiPlugin() == .partialInstalled(installed: 1, total: 2))

    try await detector.updateOhMyPiPlugin()
    #expect(await detector.detectOhMyPiPlugin() == .installed)
}

@Test func bundledVersionComesFromInstallerInjection() {
    let scope = TestScope()
    #expect(scope.fixture.installer.bundledExtensionVersion() == "0.1.0")
}
