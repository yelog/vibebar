import Foundation

public enum PluginInstallStatus: Sendable, Equatable {
    case cliNotFound
    case installed
    case notInstalled
    case checking
    case installing
    case installFailed(String)
    case uninstalling
    case uninstallFailed(String)

    public var needsAction: Bool {
        switch self {
        case .notInstalled, .installFailed:
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
            if output.contains("vibebar-claude") {
                return .installed
            }
            return .notInstalled
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
            let pluginDir = VibeBarPaths.pluginsDirectory
                .appendingPathComponent("opencode-vibebar-plugin").path
            if plugins.contains(where: { $0 == pluginDir }) {
                return .installed
            }
            return .notInstalled
        } catch {
            return .notInstalled
        }
    }

    // MARK: - Installation

    public func installClaudePlugin() async throws {
        let marketplaceDir = VibeBarPaths.pluginsDirectory.path

        // Add local marketplace
        _ = try? await runShell(
            "/usr/bin/env",
            arguments: ["claude", "plugin", "marketplace", "add", marketplaceDir]
        )

        // Install
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
        let pluginDir = VibeBarPaths.pluginsDirectory
            .appendingPathComponent("opencode-vibebar-plugin").path
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
    }

    public func uninstallOpenCodePlugin() async throws {
        let pluginDir = VibeBarPaths.pluginsDirectory
            .appendingPathComponent("opencode-vibebar-plugin").path
        let configURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/opencode/opencode.json")

        guard FileManager.default.fileExists(atPath: configURL.path) else { return }

        let rawData = try Data(contentsOf: configURL)
        guard var json = try JSONSerialization.jsonObject(with: rawData) as? [String: Any],
              var plugins = json["plugin"] as? [String]
        else { return }

        plugins.removeAll { $0 == pluginDir }
        json["plugin"] = plugins

        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: configURL, options: .atomic)
    }

    // MARK: - Helpers

    private func cliExists(_ name: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
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
    ///
    /// Fixes for reliability:
    /// - `standardInput = .nullDevice` — prevents commands from blocking on stdin in non-TTY context.
    /// - Parent's pipe write end is closed after launch — `readDataToEndOfFile` EOF depends only on child.
    /// - Timeout terminates the process, which closes its pipe FDs and unblocks the read.
    /// - All blocking I/O happens on a GCD thread, not the Swift cooperative thread pool.
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
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                process.standardInput = FileHandle.nullDevice

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                // Close parent's write end so EOF depends only on the child process.
                pipe.fileHandleForWriting.closeFile()

                // Timeout: terminate the process after deadline.
                let timer = DispatchSource.makeTimerSource(queue: .global())
                timer.schedule(deadline: .now() + timeoutCopy)
                timer.setEventHandler { process.terminate() }
                timer.resume()

                // Block this GCD thread until pipe EOF + process exit.
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
