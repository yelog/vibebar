import Foundation

public enum CodexHookInstallStatus: Sendable, Equatable {
    case cliNotFound
    case installed
    case notInstalled
}

public struct CodexHookInstaller: Sendable {
    public typealias CommandProvider = @Sendable () throws -> String
    public typealias CLIExistsProvider = @Sendable (String) -> Bool

    private let homeDirectory: URL
    private let commandProvider: CommandProvider
    private let cliExistsProvider: CLIExistsProvider

    private static let managedEvents = [
        "SessionStart",
        "SessionEnd",
        "UserPromptSubmit",
        "PreToolUse",
        "PostToolUse",
        "Stop",
        "PermissionRequest",
    ]

    public init(
        homeDirectory: URL? = nil,
        commandProvider: CommandProvider? = nil,
        cliExistsProvider: CLIExistsProvider? = nil
    ) {
        self.homeDirectory = homeDirectory ?? FileManager.default.homeDirectoryForCurrentUser
        self.commandProvider = commandProvider ?? {
            let path = try WrapperCommandInstaller().prepareManagedBinaryForIntegrations()
            return Self.commandString(forBinaryPath: path)
        }
        self.cliExistsProvider = cliExistsProvider ?? { executable in
            Self.cliExists(executable)
        }
    }

    public func detect() -> CodexHookInstallStatus {
        guard FileManager.default.fileExists(atPath: codexRootURL.path) || cliExistsProvider("codex") else {
            return .cliNotFound
        }
        return isInstalled() ? .installed : .notInstalled
    }

    public func install() throws {
        let command = try commandProvider()
        try FileManager.default.createDirectory(at: codexRootURL, withIntermediateDirectories: true)

        var root = loadJSONDictionary(at: hooksURL)
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        hooks = removeManagedEntries(from: hooks)

        for event in Self.managedEvents {
            var entries = hooks[event] as? [[String: Any]] ?? []
            entries.append(Self.makeHookEntry(command: command, event: event))
            hooks[event] = entries
        }

        root["hooks"] = hooks
        try writeJSONDictionary(root, to: hooksURL)
        try ensureCodexHooksEnabled()
    }

    public func uninstall() throws {
        var root = loadJSONDictionary(at: hooksURL)
        guard var hooks = root["hooks"] as? [String: Any] else {
            return
        }

        hooks = removeManagedEntries(from: hooks)
        if hooks.isEmpty {
            root.removeValue(forKey: "hooks")
        } else {
            root["hooks"] = hooks
        }

        try writeJSONDictionary(root, to: hooksURL)
    }

    public func hookCommand() throws -> String {
        try commandProvider()
    }

    private var codexRootURL: URL {
        homeDirectory.appendingPathComponent(".codex", isDirectory: true)
    }

    private var hooksURL: URL {
        codexRootURL.appendingPathComponent("hooks.json", isDirectory: false)
    }

    private var configURL: URL {
        codexRootURL.appendingPathComponent("config.toml", isDirectory: false)
    }

    private func isInstalled() -> Bool {
        let root = loadJSONDictionary(at: hooksURL)
        guard let hooks = root["hooks"] as? [String: Any] else { return false }
        return Self.managedEvents.allSatisfy { event in
            guard let entries = hooks[event] as? [[String: Any]] else { return false }
            return entries.contains(where: Self.containsManagedHook)
        }
    }

    private func removeManagedEntries(from hooks: [String: Any]) -> [String: Any] {
        var cleaned = hooks
        for (event, value) in hooks {
            guard var entries = value as? [[String: Any]] else { continue }
            entries.removeAll(where: Self.containsManagedHook)
            if entries.isEmpty {
                cleaned.removeValue(forKey: event)
            } else {
                cleaned[event] = entries
            }
        }
        return cleaned
    }

    private func loadJSONDictionary(at url: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object
    }

    private func writeJSONDictionary(_ json: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    private func ensureCodexHooksEnabled() throws {
        var contents = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""

        if contents.range(of: #"(?m)^\s*codex_hooks\s*=\s*true"#, options: .regularExpression) != nil {
            return
        }

        if contents.range(of: #"(?m)^\s*codex_hooks\s*=\s*false"#, options: .regularExpression) != nil {
            contents = contents.replacingOccurrences(
                of: #"(?m)^\s*codex_hooks\s*=\s*false"#,
                with: "codex_hooks = true",
                options: .regularExpression
            )
            try contents.write(to: configURL, atomically: true, encoding: .utf8)
            return
        }

        var lines = contents.components(separatedBy: "\n")
        if let featuresIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "[features]" }) {
            lines.insert("codex_hooks = true", at: featuresIndex + 1)
        } else {
            if !(lines.last ?? "").isEmpty {
                lines.append("")
            }
            lines.append("[features]")
            lines.append("codex_hooks = true")
        }

        let result = lines.joined(separator: "\n")
        try result.write(to: configURL, atomically: true, encoding: .utf8)
    }

    private static func makeHookEntry(command: String, event: String) -> [String: Any] {
        [
            "hooks": [[
                "type": "command",
                "command": command,
                "timeout": timeout(for: event),
            ]],
        ]
    }

    private static func timeout(for event: String) -> Int {
        if event == "PermissionRequest" {
            return 3600
        }
        return 5
    }

    private static func containsManagedHook(_ entry: [String: Any]) -> Bool {
        guard let hooks = entry["hooks"] as? [[String: Any]] else { return false }
        return hooks.contains { hook in
            guard let command = hook["command"] as? String else { return false }
            let lowered = command.lowercased()
            return lowered.contains("vibebar") && lowered.contains("codex-hook")
        }
    }

    private static func commandString(forBinaryPath path: String) -> String {
        let quotedPath = path.contains(" ") ? "\"\(path)\"" : path
        return quotedPath + " codex-hook"
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
