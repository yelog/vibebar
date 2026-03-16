import Foundation

public struct UsageIncrementalStore: Sendable {
    private let baseDirectory: URL?
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(baseURL: URL? = nil) {
        self.baseDirectory = baseURL

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601

        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
    }

    public func load() -> UsageIncrementalState? {
        let url = fileURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let state = try decoder.decode(UsageIncrementalState.self, from: data)
            guard state.version == UsageIncrementalState.currentVersion else {
                return nil
            }
            return state
        } catch {
            return nil
        }
    }

    public func write(_ state: UsageIncrementalState) throws {
        try ensureDirectoryExists()
        let data = try encoder.encode(state)
        let destination = fileURL()
        let temp = destination.appendingPathExtension("tmp")
        try data.write(to: temp, options: .atomic)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temp, to: destination)
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
        return directory.appendingPathComponent("incremental-state.json", isDirectory: false)
    }
}