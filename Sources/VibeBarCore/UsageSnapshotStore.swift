import Foundation

public struct UsageSnapshotStore {
    private let baseDirectory: URL?
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(baseURL: URL? = nil) {
        self.baseDirectory = baseURL

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601

        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
    }

    public func write(_ snapshot: UsageSnapshot) throws {
        try ensureDirectoryExists()
        let data = try encoder.encode(snapshot)
        let destination = fileURL()
        let temp = destination.appendingPathExtension("tmp")
        try data.write(to: temp, options: .atomic)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temp, to: destination)
    }

    public func load() throws -> UsageSnapshot? {
        let url = fileURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try decoder.decode(UsageSnapshot.self, from: data)
    }

    public func delete() {
        try? FileManager.default.removeItem(at: fileURL())
    }

    private func ensureDirectoryExists() throws {
        if let baseDirectory {
            try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        } else {
            try VibeBarPaths.ensureDirectories()
        }
    }

    private func fileURL() -> URL {
        let directory = baseDirectory ?? VibeBarPaths.usageDirectory
        return directory.appendingPathComponent("summary.json", isDirectory: false)
    }
}
