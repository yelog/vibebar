import Foundation

public struct InteractionStore {
    private let baseDirectory: URL
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(baseDirectory: URL? = nil) {
        self.baseDirectory = baseDirectory ?? VibeBarPaths.interactionsDirectory

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601

        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
    }

    public func write(_ interaction: PendingInteraction) throws {
        try ensureBaseDirectory()
        let envelope = InteractionFileEnvelope(interaction: interaction)
        let data = try encoder.encode(envelope)
        let destination = fileURL(for: interaction.id)
        let temp = destination.appendingPathExtension("tmp")
        try data.write(to: temp, options: .atomic)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temp, to: destination)
    }

    public func loadAll() -> [PendingInteraction] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: baseDirectory, includingPropertiesForKeys: nil) else {
            return []
        }

        return files.compactMap { url in
            guard url.pathExtension == "json" else { return nil }
            guard let data = try? Data(contentsOf: url) else { return nil }
            guard let envelope = try? decoder.decode(InteractionFileEnvelope.self, from: data) else { return nil }
            return envelope.interaction
        }
    }

    public func load(id: String) -> PendingInteraction? {
        let url = fileURL(for: id)
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let envelope = try? decoder.decode(InteractionFileEnvelope.self, from: data) else { return nil }
        return envelope.interaction
    }

    public func delete(id: String) {
        try? FileManager.default.removeItem(at: fileURL(for: id))
    }

    public func deleteAll(sessionID: String) {
        for interaction in loadAll() where interaction.sessionID == sessionID {
            delete(id: interaction.id)
        }
    }

    public func cleanupExpired(now: Date = Date()) {
        for interaction in loadAll() {
            guard let expiresAt = interaction.expiresAt else { continue }
            if expiresAt <= now {
                delete(id: interaction.id)
            }
        }
    }

    private func ensureBaseDirectory() throws {
        if baseDirectory.path == VibeBarPaths.interactionsDirectory.path {
            try VibeBarPaths.ensureDirectories()
            return
        }
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    }

    private func fileURL(for id: String) -> URL {
        baseDirectory.appendingPathComponent("\(id).json")
    }
}
