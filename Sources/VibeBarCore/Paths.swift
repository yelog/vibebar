import Foundation

public enum VibeBarPaths {
    public static let appFolderName = "VibeBar"
    public static let sessionsFolderName = "sessions"

    public static var appSupportDirectory: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return root.appendingPathComponent(appFolderName, isDirectory: true)
    }

    public static var sessionsDirectory: URL {
        appSupportDirectory.appendingPathComponent(sessionsFolderName, isDirectory: true)
    }

    public static func ensureDirectories() throws {
        try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
    }
}
