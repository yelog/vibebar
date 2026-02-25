import Foundation

public enum RunMode: Sendable {
    case source    // swift run 开发模式，repo 中有 Package.swift
    case published // .app bundle 或独立二进制
}

public enum VibeBarPaths {
    public static let appFolderName = "VibeBar"
    public static let sessionsFolderName = "sessions"
    public static let runtimeFolderName = "runtime"
    public static let agentSocketFileName = "agent.sock"

    // MARK: - Run Mode Detection

    private static func isInsideAppBundle(executable: URL) -> Bool {
        let macOSDir = executable.deletingLastPathComponent()
        guard macOSDir.lastPathComponent == "MacOS" else { return false }

        let contentsDir = macOSDir.deletingLastPathComponent()
        guard contentsDir.lastPathComponent == "Contents" else { return false }

        let appDir = contentsDir.deletingLastPathComponent()
        return appDir.pathExtension == "app"
    }

    public static let runMode: RunMode = {
        let exe = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
            .resolvingSymlinksInPath()

        // .app bundle should always be treated as published mode,
        // even if the bundle happens to live under the source repo.
        if isInsideAppBundle(executable: exe) {
            return .published
        }

        var dir = exe.deletingLastPathComponent()
        for _ in 0..<10 {
            if FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("Package.swift").path
            ) {
                return .source
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }
        return .published
    }()

    // MARK: - Standard Directories

    public static var appSupportDirectory: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return root.appendingPathComponent(appFolderName, isDirectory: true)
    }

    public static var sessionsDirectory: URL {
        appSupportDirectory.appendingPathComponent(sessionsFolderName, isDirectory: true)
    }

    public static var runtimeDirectory: URL {
        appSupportDirectory.appendingPathComponent(runtimeFolderName, isDirectory: true)
    }

    public static var agentSocketURL: URL {
        runtimeDirectory.appendingPathComponent(agentSocketFileName, isDirectory: false)
    }

    // MARK: - Plugins

    public static let repoRoot: URL? = {
        guard runMode == .source else { return nil }
        let sourceFile = URL(fileURLWithPath: #filePath)
        return sourceFile
            .deletingLastPathComponent()   // VibeBarCore/
            .deletingLastPathComponent()   // Sources/
            .deletingLastPathComponent()   // repo root
    }()

    public static var pluginsDirectory: URL? {
        switch runMode {
        case .source:
            return repoRoot?.appendingPathComponent("plugins", isDirectory: true)
        case .published:
            // .app bundle: Contents/Resources/plugins/
            let exe = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
                .resolvingSymlinksInPath()
            let resourcesPlugins = exe
                .deletingLastPathComponent()          // MacOS/
                .deletingLastPathComponent()          // Contents/
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent("plugins", isDirectory: true)
            guard FileManager.default.fileExists(atPath: resourcesPlugins.path) else {
                return nil
            }
            return resourcesPlugins
        }
    }

    // MARK: - Shell Environment

    /// User's full PATH, resolved from their login shell in published mode.
    public static let userPATH: String = {
        if runMode == .source {
            return ProcessInfo.processInfo.environment["PATH"]
                ?? "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        }
        // .app bundles inherit a minimal PATH; resolve from user's interactive login shell
        // to pick up PATH additions in both .zprofile and .zshrc.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lic", "echo $PATH"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
            pipe.fileHandleForWriting.closeFile()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            // Interactive shell may print extra output; take the last non-empty line.
            let lines = String(data: data, encoding: .utf8)?
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if let path = lines?.last, path.contains("/") {
                return path
            }
        } catch {}
        return "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    }()

    /// Environment dictionary suitable for child processes.
    public static let childProcessEnvironment: [String: String] = {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = userPATH
        return env
    }()

    public static func ensureDirectories() throws {
        try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: runtimeDirectory, withIntermediateDirectories: true)
    }
}
