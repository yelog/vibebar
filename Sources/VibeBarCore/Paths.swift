import Foundation

public enum VibeBarPaths {
    public static let appFolderName = "VibeBar"
    public static let sessionsFolderName = "sessions"
    public static let runtimeFolderName = "runtime"
    public static let agentSocketFileName = "agent.sock"

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

    public static let repoRoot: URL = {
        let sourceFile = URL(fileURLWithPath: #filePath)
        return sourceFile
            .deletingLastPathComponent()   // VibeBarCore/
            .deletingLastPathComponent()   // Sources/
            .deletingLastPathComponent()   // repo root
    }()

    public static var pluginsDirectory: URL {
        repoRoot.appendingPathComponent("plugins", isDirectory: true)
    }

    public static func ensureDirectories() throws {
        try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: runtimeDirectory, withIntermediateDirectories: true)
    }
}
