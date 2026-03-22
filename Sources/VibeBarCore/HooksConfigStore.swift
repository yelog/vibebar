import Foundation

public final class HooksConfigStore: Sendable {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var hooksDirectory: URL {
        VibeBarPaths.appSupportDirectory.appendingPathComponent("hooks", isDirectory: true)
    }

    private var configFileURL: URL {
        hooksDirectory.appendingPathComponent("config.json", isDirectory: false)
    }

    public init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func load() -> HooksConfig {
        let url = configFileURL

        guard FileManager.default.fileExists(atPath: url.path) else {
            return .default
        }

        do {
            let data = try Data(contentsOf: url)
            var config = try decoder.decode(HooksConfig.self, from: data)
            migrateIfNeeded(&config)
            return config
        } catch {
            fputs("vibebar: Failed to load hooks config: \(error.localizedDescription)\n", stderr)
            return .default
        }
    }

    public func save(_ config: HooksConfig) throws {
        let dir = hooksDirectory
        let url = configFileURL

        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        let data = try encoder.encode(config)

        let tempURL = dir.appendingPathComponent("config.json.tmp")
        try data.write(to: tempURL, options: .atomic)

        _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
    }

    public func addHook(_ hook: HookConfig) throws -> HooksConfig {
        var config = load()
        config.hooks.append(hook)
        try save(config)
        return config
    }

    public func updateHook(_ hook: HookConfig) throws -> HooksConfig {
        var config = load()
        guard let index = config.hooks.firstIndex(where: { $0.id == hook.id }) else {
            throw HooksError.hookNotFound(id: hook.id)
        }
        var updated = hook
        updated.touch()
        config.hooks[index] = updated
        try save(config)
        return config
    }

    public func deleteHook(id: String) throws -> HooksConfig {
        var config = load()
        let countBefore = config.hooks.count
        config.hooks.removeAll { $0.id == id }
        guard config.hooks.count < countBefore else {
            throw HooksError.hookNotFound(id: id)
        }
        try save(config)
        return config
    }

    public func setHookEnabled(id: String, enabled: Bool) throws -> HooksConfig {
        var config = load()
        guard let index = config.hooks.firstIndex(where: { $0.id == id }) else {
            throw HooksError.hookNotFound(id: id)
        }
        config.hooks[index].isEnabled = enabled
        config.hooks[index].touch()
        try save(config)
        return config
    }

    private func migrateIfNeeded(_ config: inout HooksConfig) {
        // Future migration logic
    }
}

public enum HooksError: LocalizedError, Sendable {
    case hookNotFound(id: String)
    case invalidConfiguration(String)
    case executionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .hookNotFound(let id):
            return "Hook not found: \(id)"
        case .invalidConfiguration(let message):
            return "Invalid hook configuration: \(message)"
        case .executionFailed(let message):
            return "Hook execution failed: \(message)"
        }
    }
}