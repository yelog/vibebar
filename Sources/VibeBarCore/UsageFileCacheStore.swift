import Foundation

public struct UsageCachedFileEntry: Codable, Sendable, Equatable {
    public var modificationTimeIntervalSince1970: TimeInterval
    public var fileSize: Int64
    public var events: [UsageEvent]

    public init(
        modificationTimeIntervalSince1970: TimeInterval,
        fileSize: Int64,
        events: [UsageEvent]
    ) {
        self.modificationTimeIntervalSince1970 = modificationTimeIntervalSince1970
        self.fileSize = fileSize
        self.events = events
    }
}

public struct UsageSourceFileCache: Codable, Sendable, Equatable {
    public var version: Int
    public var entries: [String: UsageCachedFileEntry]

    public init(version: Int = 1, entries: [String: UsageCachedFileEntry] = [:]) {
        self.version = version
        self.entries = entries
    }
}

public struct UsageFileCacheStore {
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

    public func load(source: UsageSource) throws -> UsageSourceFileCache? {
        let url = fileURL(for: source)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try decoder.decode(UsageSourceFileCache.self, from: data)
    }

    public func write(_ cache: UsageSourceFileCache, source: UsageSource) throws {
        try ensureDirectoryExists()
        let data = try encoder.encode(cache)
        let destination = fileURL(for: source)
        let temp = destination.appendingPathExtension("tmp")
        try data.write(to: temp, options: .atomic)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temp, to: destination)
    }

    public func delete(source: UsageSource) {
        try? FileManager.default.removeItem(at: fileURL(for: source))
    }

    private func ensureDirectoryExists() throws {
        if let baseDirectory {
            try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        } else {
            try VibeBarPaths.ensureDirectories()
        }
    }

    private func fileURL(for source: UsageSource) -> URL {
        let directory = baseDirectory ?? VibeBarPaths.usageDirectory
        return directory.appendingPathComponent("\(source.rawValue)-files.json", isDirectory: false)
    }
}
