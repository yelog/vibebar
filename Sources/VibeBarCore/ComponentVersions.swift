import Foundation

public struct ComponentVersionsManifest: Codable, Sendable, Equatable {
    public var appVersion: String
    public var wrapperVersion: String
    public var claudePluginVersion: String
    public var opencodePluginVersion: String
    public var piFamilyExtensionVersion: String?

    public init(
        appVersion: String,
        wrapperVersion: String,
        claudePluginVersion: String,
        opencodePluginVersion: String,
        piFamilyExtensionVersion: String? = nil
    ) {
        self.appVersion = appVersion
        self.wrapperVersion = wrapperVersion
        self.claudePluginVersion = claudePluginVersion
        self.opencodePluginVersion = opencodePluginVersion
        self.piFamilyExtensionVersion = piFamilyExtensionVersion
    }
}

public enum ComponentVersions {
    public static func loadBundled() -> ComponentVersionsManifest? {
        guard let url = VibeBarPaths.componentVersionsURL else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let manifest = try? JSONDecoder().decode(ComponentVersionsManifest.self, from: data) else {
            return nil
        }
        return manifest
    }

    public static func wrapperVersion() -> String? {
        guard let version = loadBundled()?.wrapperVersion else { return nil }
        return normalize(version)
    }

    public static func pluginVersion(for tool: ToolKind) -> String? {
        guard let manifest = loadBundled() else { return nil }
        switch tool {
        case .claudeCode:
            return normalize(manifest.claudePluginVersion)
        case .opencode:
            return normalize(manifest.opencodePluginVersion)
        case .pi, .ohMyPi:
            return normalize(manifest.piFamilyExtensionVersion ?? "")
        default:
            return nil
        }
    }

    public static func piFamilyExtensionVersion() -> String? {
        normalize(loadBundled()?.piFamilyExtensionVersion ?? "")
    }

    private static func normalize(_ version: String) -> String? {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
