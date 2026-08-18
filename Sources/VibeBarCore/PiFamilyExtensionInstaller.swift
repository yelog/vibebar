import Foundation

public enum PiFamilyProduct: String, Sendable, CaseIterable {
    case pi
    case ohMyPi

    public var tool: ToolKind {
        switch self {
        case .pi:
            return .pi
        case .ohMyPi:
            return .ohMyPi
        }
    }

    public var executable: String {
        switch self {
        case .pi:
            return "pi"
        case .ohMyPi:
            return "omp"
        }
    }

    var adapterDirectoryName: String {
        switch self {
        case .pi:
            return "pi"
        case .ohMyPi:
            return "omp"
        }
    }
}

public enum PiFamilyExtensionInstallStatus: Sendable, Equatable {
    case cliNotFound
    case notInstalled
    case installed(version: String)
    case partialInstalled(installed: Int, total: Int)
    case updateAvailable(installed: String, bundled: String)
}

public struct PiFamilyExtensionInstaller: Sendable {
    public static let managedDirectoryName = "vibebar"
    public static let markerFileName = "vibebar.json"
    public static let extensionSourceDirectoryName = "pi-vibebar-extension"

    private let homeDirectory: URL
    private let pluginsDirectory: URL
    private let bundledVersion: String?
    private let cliExists: @Sendable (String) -> Bool

    public init(
        homeDirectory: URL? = nil,
        pluginsDirectory: URL? = nil,
        bundledVersion: String? = nil,
        cliExists: (@Sendable (String) -> Bool)? = nil
    ) {
        self.homeDirectory = homeDirectory ?? FileManager.default.homeDirectoryForCurrentUser
        self.pluginsDirectory = pluginsDirectory
            ?? VibeBarPaths.pluginsDirectory
            ?? FileManager.default.homeDirectoryForCurrentUser
        self.bundledVersion = bundledVersion ?? ComponentVersions.piFamilyExtensionVersion()
        self.cliExists = cliExists ?? { executable in
            Self.cliExists(executable)
        }
    }

    // MARK: - Paths

    public static func destinationRoots(
        for product: PiFamilyProduct,
        homeDirectory: URL
    ) -> [URL] {
        switch product {
        case .pi:
            return [
                homeDirectory
                    .appendingPathComponent(".pi/agent/extensions", isDirectory: true),
            ]
        case .ohMyPi:
            var roots = [
                homeDirectory
                    .appendingPathComponent(".omp/agent/extensions", isDirectory: true),
            ]
            let profiles = homeDirectory
                .appendingPathComponent(".omp/profiles", isDirectory: true)
            let fileManager = FileManager.default
            guard let entries = try? fileManager.contentsOfDirectory(
                at: profiles,
                includingPropertiesForKeys: nil
            ) else {
                return roots
            }
            for entry in entries {
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: entry.path, isDirectory: &isDirectory),
                      isDirectory.boolValue else {
                    continue
                }
                let agentDirectory = entry.appendingPathComponent("agent", isDirectory: true)
                guard fileManager.fileExists(atPath: agentDirectory.path, isDirectory: &isDirectory),
                      isDirectory.boolValue else {
                    continue
                }
                roots.append(
                    agentDirectory.appendingPathComponent("extensions", isDirectory: true)
                )
            }
            return roots
        }
    }

    private func managedDirectory(in root: URL) -> URL {
        root.appendingPathComponent(Self.managedDirectoryName, isDirectory: true)
    }

    private func markerURL(for managedDirectory: URL) -> URL {
        managedDirectory.appendingPathComponent(Self.markerFileName, isDirectory: false)
    }

    private func sourceDirectory() -> URL {
        pluginsDirectory.appendingPathComponent(Self.extensionSourceDirectoryName, isDirectory: true)
    }

    // MARK: - Detection

    public func detect(product: PiFamilyProduct) -> PiFamilyExtensionInstallStatus {
        guard cliExists(product.executable) else {
            return .cliNotFound
        }
        guard let bundled = bundledVersion else {
            return .notInstalled
        }

        let roots = Self.destinationRoots(for: product, homeDirectory: homeDirectory)
        var installedCount = 0
        var installedVersion: String?
        var oldestInstalledVersion: String?

        for root in roots {
            let managed = managedDirectory(in: root)
            guard let marker = readMarker(at: managed) else {
                continue
            }
            guard FileManager.default.fileExists(atPath: managed.appendingPathComponent("index.ts").path),
                  FileManager.default.fileExists(atPath: managed.appendingPathComponent("runtime.js").path) else {
                continue
            }
            installedCount += 1
            if let version = marker["version"], !version.isEmpty {
                installedVersion = version
                if oldestInstalledVersion == nil || version < oldestInstalledVersion! {
                    oldestInstalledVersion = version
                }
            }
        }

        if installedCount == roots.count {
            if let installedVersion, installedVersion != bundled {
                return .updateAvailable(installed: installedVersion, bundled: bundled)
            }
            return .installed(version: installedVersion ?? bundled)
        }
        if installedCount == 0 {
            return .notInstalled
        }
        return .partialInstalled(installed: installedCount, total: roots.count)
    }

    public func bundledExtensionVersion() -> String? {
        bundledVersion
    }

    // MARK: - Installation

    public func install(product: PiFamilyProduct) throws {
        guard let bundled = bundledVersion else {
            throw makeError("无法确定 VibeBar 扩展版本。")
        }

        let sourceRoot = sourceDirectory()
        let runtimeURL = sourceRoot.appendingPathComponent("runtime.js", isDirectory: false)
        let adapterURL = sourceRoot
            .appendingPathComponent(product.adapterDirectoryName, isDirectory: true)
            .appendingPathComponent("index.ts", isDirectory: false)
        guard FileManager.default.fileExists(atPath: runtimeURL.path),
              FileManager.default.fileExists(atPath: adapterURL.path) else {
            throw makeError("VibeBar 扩展源文件缺失。")
        }

        let roots = Self.destinationRoots(for: product, homeDirectory: homeDirectory)
        for root in roots {
            try installInto(
                root: root,
                runtimeURL: runtimeURL,
                adapterURL: adapterURL,
                version: bundled
            )
        }
    }

    private func installInto(
        root: URL,
        runtimeURL: URL,
        adapterURL: URL,
        version: String
    ) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let managed = managedDirectory(in: root)
        if fileManager.fileExists(atPath: managed.path) {
            if !isManaged(at: managed) {
                if !isEmptyDirectory(managed) {
                    throw makeError("\(managed.path) 已存在非 VibeBar 管理的目录。")
                }
                try fileManager.removeItem(at: managed)
            }
        }

        let staging = root.appendingPathComponent(
            ".vibebar-staging-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        try fileManager.copyItem(at: adapterURL, to: staging.appendingPathComponent("index.ts"))
        try fileManager.copyItem(at: runtimeURL, to: staging.appendingPathComponent("runtime.js"))
        try writeMarker(in: staging, version: version)

        if fileManager.fileExists(atPath: managed.path) {
            let backup = root.appendingPathComponent(
                ".vibebar-backup-\(UUID().uuidString)",
                isDirectory: true
            )
            try fileManager.moveItem(at: managed, to: backup)
            do {
                try fileManager.moveItem(at: staging, to: managed)
                try? fileManager.removeItem(at: backup)
            } catch {
                try? fileManager.moveItem(at: backup, to: managed)
                throw error
            }
        } else {
            try fileManager.moveItem(at: staging, to: managed)
        }
    }

    // MARK: - Uninstall

    public func uninstall(product: PiFamilyProduct) throws {
        let roots = Self.destinationRoots(for: product, homeDirectory: homeDirectory)
        for root in roots {
            let managed = managedDirectory(in: root)
            guard isManaged(at: managed) else { continue }
            try FileManager.default.removeItem(at: managed)
        }
    }

    // MARK: - Marker

    private func isManaged(at directory: URL) -> Bool {
        guard let marker = readMarker(at: directory) else {
            return false
        }
        return marker["managedBy"] == "vibebar"
    }

    private func readMarker(at directory: URL) -> [String: String]? {
        let url = markerURL(for: directory)
        guard let data = try? Data(contentsOf: url),
              let marker = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return nil
        }
        return marker
    }

    private func writeMarker(in directory: URL, version: String) throws {
        let marker: [String: String] = [
            "managedBy": "vibebar",
            "version": version,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: marker,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: markerURL(for: directory), options: .atomic)
    }

    private func isEmptyDirectory(_ url: URL) -> Bool {
        let contents = try? FileManager.default.contentsOfDirectory(atPath: url.path)
        return contents?.isEmpty ?? false
    }

    private func makeError(_ message: String) -> Error {
        NSError(
            domain: "PiFamilyExtensionInstaller",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    private static func cliExists(_ executable: String) -> Bool {
        let fileManager = FileManager.default
        for directory in VibeBarPaths.userPATH.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory), isDirectory: true)
                .appendingPathComponent(executable, isDirectory: false)
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return true
            }
        }
        return false
    }
}
