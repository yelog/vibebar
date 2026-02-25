import Foundation

public enum PluginInstallStatus: Sendable, Equatable {
    case cliNotFound
    case installed
    case updateAvailable(installed: String, bundled: String)
    case notInstalled
    case checking
    case installing
    case installFailed(String)
    case uninstalling
    case uninstallFailed(String)
    case updating
    case updateFailed(String)

    public var needsAction: Bool {
        switch self {
        case .notInstalled, .installFailed, .updateAvailable:
            return true
        default:
            return false
        }
    }
}

public struct PluginStatusReport: Sendable {
    public var claudeCode: PluginInstallStatus
    public var opencode: PluginInstallStatus

    public init(
        claudeCode: PluginInstallStatus = .checking,
        opencode: PluginInstallStatus = .checking
    ) {
        self.claudeCode = claudeCode
        self.opencode = opencode
    }

    /// True when at least one CLI is present (section should be visible).
    public var needsAttention: Bool {
        !visibleItems.isEmpty
    }

    /// Returns tool/status pairs that should be visible in the menu.
    public var visibleItems: [(tool: ToolKind, status: PluginInstallStatus)] {
        var result: [(ToolKind, PluginInstallStatus)] = []
        if claudeCode != .cliNotFound {
            result.append((.claudeCode, claudeCode))
        }
        if opencode != .cliNotFound {
            result.append((.opencode, opencode))
        }
        return result
    }
}

public final class PluginDetector: Sendable {
    public init() {}

    // MARK: - Detection

    public func detectAll() async -> PluginStatusReport {
        async let claude = detectClaudePlugin()
        async let oc = detectOpenCodePlugin()
        return PluginStatusReport(claudeCode: await claude, opencode: await oc)
    }

    public func detectClaudePlugin() async -> PluginInstallStatus {
        guard cliExists("claude") else { return .cliNotFound }
        do {
            let output = try await runShell("/usr/bin/env", arguments: ["claude", "plugin", "list"])
            guard output.contains("vibebar-claude") else {
                return .notInstalled
            }
            // Compare installed vs bundled version
            if let installedVersion = parseInstalledClaudeVersion(from: output),
               let bundledVersion = readBundledVersion(tool: .claudeCode),
               installedVersion != bundledVersion,
               isVersionNewer(bundledVersion, than: installedVersion) {
                return .updateAvailable(installed: installedVersion, bundled: bundledVersion)
            }
            return .installed
        } catch {
            return .notInstalled
        }
    }

    public func detectOpenCodePlugin() async -> PluginInstallStatus {
        guard cliExists("opencode") else { return .cliNotFound }
        let configURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/opencode/opencode.json")
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            return .notInstalled
        }
        do {
            let data = try Data(contentsOf: configURL)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let plugins = json["plugin"] as? [String]
            else {
                return .notInstalled
            }
            // Check if any registered plugin path contains our plugin directory name
            if plugins.contains(where: { $0.contains("opencode-vibebar-plugin") }) {
                return .installed
            }
            return .notInstalled
        } catch {
            return .notInstalled
        }
    }

    // MARK: - Installation

    public func installClaudePlugin() async throws {
        guard let marketplaceDir = VibeBarPaths.pluginsDirectory?.path else {
            throw NSError(
                domain: "PluginDetector", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Plugins directory not available"]
            )
        }
        // Add local marketplace
        _ = try? await runShell(
            "/usr/bin/env",
            arguments: ["claude", "plugin", "marketplace", "add", marketplaceDir]
        )
        // Install from local marketplace
        _ = try await runShell(
            "/usr/bin/env",
            arguments: ["claude", "plugin", "install", "vibebar-claude@vibebar-local"]
        )
        // Enable
        _ = try? await runShell(
            "/usr/bin/env",
            arguments: ["claude", "plugin", "enable", "vibebar-claude"]
        )
    }

    public func installOpenCodePlugin() async throws {
        guard let pluginDir = VibeBarPaths.pluginsDirectory?
            .appendingPathComponent("opencode-vibebar-plugin").path else {
            throw NSError(
                domain: "PluginDetector", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Plugins directory not available"]
            )
        }

        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/opencode")
        let configURL = configDir.appendingPathComponent("opencode.json")

        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

        var json: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: configURL.path),
           let data = try? Data(contentsOf: configURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            json = existing
        }

        var plugins = (json["plugin"] as? [String]) ?? []
        if !plugins.contains(pluginDir) {
            plugins.append(pluginDir)
        }
        json["plugin"] = plugins

        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: configURL, options: .atomic)
    }

    // MARK: - Uninstallation

    public func uninstallClaudePlugin() async throws {
        _ = try await runShell(
            "/usr/bin/env",
            arguments: ["claude", "plugin", "uninstall", "vibebar-claude"]
        )
        if let marketplaceDir = VibeBarPaths.pluginsDirectory?.path {
            _ = try? await runShell(
                "/usr/bin/env",
                arguments: ["claude", "plugin", "marketplace", "remove", marketplaceDir]
            )
        }
    }

    public func uninstallOpenCodePlugin() async throws {
        let configURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/opencode/opencode.json")

        guard FileManager.default.fileExists(atPath: configURL.path) else { return }

        let rawData = try Data(contentsOf: configURL)
        guard var json = try JSONSerialization.jsonObject(with: rawData) as? [String: Any],
              var plugins = json["plugin"] as? [String]
        else { return }

        plugins.removeAll { $0.contains("opencode-vibebar-plugin") }
        json["plugin"] = plugins

        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: configURL, options: .atomic)
    }

    // MARK: - Update

    public func updateClaudePlugin() async throws {
        // Re-running install overwrites the old version with the bundled one
        try await installClaudePlugin()
    }

    // MARK: - Helpers

    /// Read version from the bundled plugin directory.
    public func readBundledVersion(tool: ToolKind) -> String? {
        guard let pluginsDir = VibeBarPaths.pluginsDirectory else { return nil }
        let fileURL: URL
        switch tool {
        case .claudeCode:
            fileURL = pluginsDir
                .appendingPathComponent("claude-vibebar-plugin")
                .appendingPathComponent(".claude-plugin")
                .appendingPathComponent("plugin.json")
        case .opencode:
            fileURL = pluginsDir
                .appendingPathComponent("opencode-vibebar-plugin")
                .appendingPathComponent("package.json")
        default:
            return nil
        }
        guard let data = try? Data(contentsOf: fileURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = json["version"] as? String
        else { return nil }
        return version
    }

    /// Parse `claude plugin list` output for the installed version of vibebar-claude.
    private func parseInstalledClaudeVersion(from output: String) -> String? {
        for line in output.components(separatedBy: .newlines) {
            guard line.contains("vibebar-claude") else { continue }
            if let match = line.range(of: #"\d+\.\d+\.\d+"#, options: .regularExpression) {
                return String(line[match])
            }
        }
        return nil
    }

    /// Returns true if `lhs` is a newer semver than `rhs`.
    private func isVersionNewer(_ lhs: String, than rhs: String) -> Bool {
        let lParts = lhs.split(separator: ".").compactMap { Int($0) }
        let rParts = rhs.split(separator: ".").compactMap { Int($0) }
        guard lParts.count == 3, rParts.count == 3 else { return false }
        for i in 0..<3 {
            if lParts[i] > rParts[i] { return true }
            if lParts[i] < rParts[i] { return false }
        }
        return false
    }

    private func cliExists(_ name: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        process.environment = VibeBarPaths.childProcessEnvironment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Run a shell command on a GCD thread with timeout.
    @discardableResult
    private func runShell(
        _ executable: String,
        arguments: [String],
        timeout: TimeInterval = 15
    ) async throws -> String {
        let executableCopy = executable
        let argumentsCopy = arguments
        let timeoutCopy = timeout

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                let pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: executableCopy)
                process.arguments = argumentsCopy
                process.environment = VibeBarPaths.childProcessEnvironment
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                process.standardInput = FileHandle.nullDevice

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                pipe.fileHandleForWriting.closeFile()

                let timer = DispatchSource.makeTimerSource(queue: .global())
                timer.schedule(deadline: .now() + timeoutCopy)
                timer.setEventHandler { process.terminate() }
                timer.resume()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                timer.cancel()

                let output = String(data: data, encoding: .utf8) ?? ""
                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "PluginDetector",
                        code: Int(process.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: "Exit \(process.terminationStatus): \(output)"]
                    ))
                }
            }
        }
    }
}
