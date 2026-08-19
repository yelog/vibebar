import Foundation
import Testing
@testable import VibeBarCore

private struct PiFamilyInstallerFixture {
    let tempRoot: URL
    let home: URL
    let plugins: URL
    let installer: PiFamilyExtensionInstaller

    init() {
        let temp = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        tempRoot = temp
            .appendingPathComponent("PiFamilyInstallerTests-\(UUID().uuidString)")
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
        let sourceRoot = Self.repositoryRoot()
            .appendingPathComponent("plugins")
            .appendingPathComponent("pi-vibebar-extension")
        let root = plugins.appendingPathComponent("pi-vibebar-extension")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for relative in ["runtime.js", "pi/index.ts", "omp/index.ts"] {
            let source = sourceRoot.appendingPathComponent(relative)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            let destination = root.appendingPathComponent(relative)
            try? FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? FileManager.default.copyItem(at: source, to: destination)
        }
    }

    private static func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func makeOMPProfile(_ name: String, withAgent: Bool) {
        let profile = home.appendingPathComponent(".omp/profiles/\(name)")
        try? FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        if withAgent {
            try? FileManager.default.createDirectory(
                at: profile.appendingPathComponent("agent"),
                withIntermediateDirectories: true
            )
        }
    }

    func makePiAgentDir() {
        try? FileManager.default.createDirectory(
            at: home.appendingPathComponent(".pi/agent"),
            withIntermediateDirectories: true
        )
    }

    func makeOMPDefaultAgentDir() {
        try? FileManager.default.createDirectory(
            at: home.appendingPathComponent(".omp/agent"),
            withIntermediateDirectories: true
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: tempRoot)
    }
}

private final class TestScopedFixture {
    let fixture: PiFamilyInstallerFixture
    init() { fixture = PiFamilyInstallerFixture() }
    deinit { fixture.cleanup() }
}

@Test func piDestinationRootIsPiAgentExtensions() {
    let scope = TestScopedFixture()
    let roots = PiFamilyExtensionInstaller.destinationRoots(for: .pi, homeDirectory: scope.fixture.home)
    #expect(roots == [scope.fixture.home.appendingPathComponent(".pi/agent/extensions", isDirectory: true)])
}

@Test func ohMyPiDestinationRootsIncludeDefaultAndExistingProfiles() {
    let scope = TestScopedFixture()
    scope.fixture.makeOMPDefaultAgentDir()
    scope.fixture.makeOMPProfile("work", withAgent: true)
    scope.fixture.makeOMPProfile("dev", withAgent: true)
    scope.fixture.makeOMPProfile("empty", withAgent: false)
    try? "note".write(
        to: scope.fixture.home.appendingPathComponent(".omp/profiles/note.txt"),
        atomically: true,
        encoding: .utf8
    )

    let roots = PiFamilyExtensionInstaller.destinationRoots(for: .ohMyPi, homeDirectory: scope.fixture.home)
    let expected = [
        scope.fixture.home.appendingPathComponent(".omp/agent/extensions", isDirectory: true),
        scope.fixture.home.appendingPathComponent(".omp/profiles/work/agent/extensions", isDirectory: true),
        scope.fixture.home.appendingPathComponent(".omp/profiles/dev/agent/extensions", isDirectory: true),
    ]
    #expect(roots.map(normalizedPath) == expected.map(normalizedPath))
}

private func normalizedPath(_ url: URL) -> String {
    var path = url.path
    if path.hasPrefix("/private/var") {
        path = String(path.dropFirst("/private".count))
    }
    return path
}

@Test func installCopiesAdapterRuntimeAndMarker() throws {
    let scope = TestScopedFixture()
    try scope.fixture.installer.install(product: .pi)

    let managed = scope.fixture.home
        .appendingPathComponent(".pi/agent/extensions/vibebar")
    #expect(FileManager.default.fileExists(atPath: managed.appendingPathComponent("index.ts").path))
    #expect(FileManager.default.fileExists(atPath: managed.appendingPathComponent("runtime.js").path))

    let markerURL = managed.appendingPathComponent("vibebar.json")
    #expect(FileManager.default.fileExists(atPath: markerURL.path))
    let data = try Data(contentsOf: markerURL)
    let marker = try JSONSerialization.jsonObject(with: data) as? [String: String]
    #expect(marker?["managedBy"] == "vibebar")
    #expect(marker?["version"] == "0.1.0")
}

@Test func installedAdaptersReferenceColocatedRuntime() throws {
    let scope = TestScopedFixture()
    try scope.fixture.installer.install(product: .pi)
    try scope.fixture.installer.install(product: .ohMyPi)

    let piManaged = scope.fixture.home.appendingPathComponent(".pi/agent/extensions/vibebar")
    let ompManaged = scope.fixture.home.appendingPathComponent(".omp/agent/extensions/vibebar")

    for managed in [piManaged, ompManaged] {
        #expect(FileManager.default.fileExists(atPath: managed.appendingPathComponent("index.ts").path))
        #expect(FileManager.default.fileExists(atPath: managed.appendingPathComponent("runtime.js").path))
        let contents = try String(contentsOf: managed.appendingPathComponent("index.ts"), encoding: .utf8)
        #expect(contents.contains("from \"./runtime.js\""))
        #expect(!contents.contains("from \"../runtime.js\""))
    }
}

@Test func detectDistinguishesCliMissingNotInstalledInstalledPartialAndUpdate() throws {
    let scope = TestScopedFixture()

    let noCLI = PiFamilyExtensionInstaller(
        homeDirectory: scope.fixture.home,
        pluginsDirectory: scope.fixture.plugins,
        bundledVersion: "0.1.0",
        cliExists: { _ in false }
    )
    #expect(noCLI.detect(product: .pi) == .cliNotFound)

    scope.fixture.makePiAgentDir()
    #expect(scope.fixture.installer.detect(product: .pi) == .notInstalled)

    try scope.fixture.installer.install(product: .pi)
    #expect(scope.fixture.installer.detect(product: .pi) == .installed(version: "0.1.0"))

    let managed = scope.fixture.home.appendingPathComponent(".pi/agent/extensions/vibebar")
    let markerURL = managed.appendingPathComponent("vibebar.json")
    let oldMarker = ["managedBy": "vibebar", "version": "0.0.9"]
    let oldData = try JSONSerialization.data(withJSONObject: oldMarker)
    try oldData.write(to: markerURL, options: .atomic)
    #expect(scope.fixture.installer.detect(product: .pi) == .updateAvailable(installed: "0.0.9", bundled: "0.1.0"))
}

@Test func ompPartialInstallationReportsPartialStatus() throws {
    let scope = TestScopedFixture()
    scope.fixture.makeOMPDefaultAgentDir()
    scope.fixture.makeOMPProfile("work", withAgent: true)

    try scope.fixture.installer.install(product: .ohMyPi)
    #expect(scope.fixture.installer.detect(product: .ohMyPi) == .installed(version: "0.1.0"))

    scope.fixture.makeOMPProfile("later", withAgent: true)
    #expect(
        scope.fixture.installer.detect(product: .ohMyPi) == .partialInstalled(installed: 2, total: 3)
    )

    try scope.fixture.installer.install(product: .ohMyPi)
    #expect(scope.fixture.installer.detect(product: .ohMyPi) == .installed(version: "0.1.0"))
}

@Test func installRepairsMissingManagedFiles() throws {
    let scope = TestScopedFixture()
    scope.fixture.makePiAgentDir()
    try scope.fixture.installer.install(product: .pi)

    let managed = scope.fixture.home.appendingPathComponent(".pi/agent/extensions/vibebar")
    try? FileManager.default.removeItem(at: managed.appendingPathComponent("runtime.js"))
    #expect(scope.fixture.installer.detect(product: .pi) == .notInstalled)

    try scope.fixture.installer.install(product: .pi)
    #expect(FileManager.default.fileExists(atPath: managed.appendingPathComponent("runtime.js").path))
    #expect(scope.fixture.installer.detect(product: .pi) == .installed(version: "0.1.0"))
}

@Test func installFailsWhenDestinationIsUnmarkedUserDirectory() throws {
    let scope = TestScopedFixture()
    let managed = scope.fixture.home.appendingPathComponent(".pi/agent/extensions/vibebar")
    try FileManager.default.createDirectory(at: managed, withIntermediateDirectories: true)
    try "user-file".write(to: managed.appendingPathComponent("custom.ts"), atomically: true, encoding: .utf8)

    #expect(throws: (any Error).self) {
        try scope.fixture.installer.install(product: .pi)
    }
    #expect(FileManager.default.fileExists(atPath: managed.appendingPathComponent("custom.ts").path))
    #expect(!FileManager.default.fileExists(atPath: managed.appendingPathComponent("index.ts").path))
}

@Test func uninstallRemovesOnlyManagedDirectories() throws {
    let scope = TestScopedFixture()
    scope.fixture.makePiAgentDir()
    try scope.fixture.installer.install(product: .pi)

    let managed = scope.fixture.home.appendingPathComponent(".pi/agent/extensions/vibebar")
    let unrelated = scope.fixture.home.appendingPathComponent(".pi/agent/extensions/my-extension")
    try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)
    try "mine".write(to: unrelated.appendingPathComponent("index.ts"), atomically: true, encoding: .utf8)

    let userVibebarDir = scope.fixture.home.appendingPathComponent(".pi/agent/extensions/vibebar-user")
    try FileManager.default.createDirectory(at: userVibebarDir, withIntermediateDirectories: true)
    try "keep".write(to: userVibebarDir.appendingPathComponent("data.txt"), atomically: true, encoding: .utf8)

    try scope.fixture.installer.uninstall(product: .pi)

    #expect(!FileManager.default.fileExists(atPath: managed.path))
    #expect(FileManager.default.fileExists(atPath: unrelated.appendingPathComponent("index.ts").path))
    #expect(FileManager.default.fileExists(atPath: userVibebarDir.appendingPathComponent("data.txt").path))
    #expect(scope.fixture.installer.detect(product: .pi) == .notInstalled)
}

@Test func uninstallDoesNotRemoveUnmarkedVibebarDirectory() throws {
    let scope = TestScopedFixture()
    let managed = scope.fixture.home.appendingPathComponent(".pi/agent/extensions/vibebar")
    try FileManager.default.createDirectory(at: managed, withIntermediateDirectories: true)
    try "user-content".write(to: managed.appendingPathComponent("own.ts"), atomically: true, encoding: .utf8)

    try scope.fixture.installer.uninstall(product: .pi)

    #expect(FileManager.default.fileExists(atPath: managed.appendingPathComponent("own.ts").path))
}

@Test func cliExistenceIsCheckedPerProductExecutable() {
    let scope = TestScopedFixture()
    let installer = PiFamilyExtensionInstaller(
        homeDirectory: scope.fixture.home,
        pluginsDirectory: scope.fixture.plugins,
        bundledVersion: "0.1.0",
        cliExists: { executable in executable == "pi" }
    )
    #expect(installer.detect(product: .pi) == .notInstalled)
    #expect(installer.detect(product: .ohMyPi) == .cliNotFound)
}
