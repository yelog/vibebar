import Foundation

public struct SessionFileStore {
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init() {
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601

        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
    }

    public func write(_ snapshot: SessionSnapshot) throws {
        try VibeBarPaths.ensureDirectories()
        let envelope = SessionFileEnvelope(session: snapshot)
        let data = try encoder.encode(envelope)
        let destination = fileURL(for: snapshot.id)
        let temp = destination.appendingPathExtension("tmp")
        try data.write(to: temp, options: .atomic)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temp, to: destination)
    }

    public func delete(sessionID: String) {
        let url = fileURL(for: sessionID)
        try? FileManager.default.removeItem(at: url)
    }

    public func loadAll() -> [SessionSnapshot] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: VibeBarPaths.sessionsDirectory, includingPropertiesForKeys: nil) else {
            return []
        }

        return files.compactMap { url in
            guard url.pathExtension == "json" else { return nil }
            guard let data = try? Data(contentsOf: url) else { return nil }
            guard let envelope = try? decoder.decode(SessionFileEnvelope.self, from: data) else { return nil }
            return envelope.session
        }
    }

    public func load(sessionID: String) -> SessionSnapshot? {
        let url = fileURL(for: sessionID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let envelope = try? decoder.decode(SessionFileEnvelope.self, from: data) else { return nil }
        return envelope.session
    }

    /// 清理同一 PID 的其他会话文件（插件可能对同一进程生成不同 sessionID）。
    public func deleteOtherSessions(forPID pid: Int32, keeping sessionID: String) {
        guard pid > 0 else { return }
        let sessions = loadAll()
        for session in sessions where session.pid == pid && session.id != sessionID {
            delete(sessionID: session.id)
        }
    }

    public func cleanupStaleSessions(now: Date, idleTTL: TimeInterval) {
        let sessions = loadAll()
        for session in sessions {
            let age = now.timeIntervalSince(session.updatedAt)
            let shouldDeleteInactive = session.status != .running && session.status != .awaitingInput && age > idleTTL
            if shouldDeleteInactive {
                delete(sessionID: session.id)
            }
        }
    }

    private func fileURL(for sessionID: String) -> URL {
        VibeBarPaths.sessionsDirectory.appendingPathComponent("\(sessionID).json")
    }
}
