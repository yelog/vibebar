import Foundation

import VibeBarCore

struct CompletedSessionDisplayStore {
    let duration: TimeInterval
    private(set) var expirationBySessionID: [String: Date] = [:]

    @discardableResult
    mutating func begin(for sessionID: String, now: Date = Date()) -> Date {
        let expiration = now.addingTimeInterval(duration)
        expirationBySessionID[sessionID] = expiration
        return expiration
    }

    mutating func sync(with sessions: [SessionSnapshot], now: Date = Date()) {
        let idleSessionIDs = Set(sessions.filter { $0.status == .idle }.map(\.id))
        expirationBySessionID = expirationBySessionID.filter { sessionID, expiration in
            idleSessionIDs.contains(sessionID) && expiration > now
        }
    }

    func isActive(for sessionID: String, now: Date = Date()) -> Bool {
        guard let expiration = expirationBySessionID[sessionID] else { return false }
        return expiration > now
    }

    func nextExpiration(now: Date = Date()) -> Date? {
        expirationBySessionID.values.filter { $0 > now }.min()
    }

    func displayedSessions(from sessions: [SessionSnapshot], now: Date = Date()) -> [SessionSnapshot] {
        sessions.map { session in
            guard session.status == .idle,
                  isActive(for: session.id, now: now) else {
                return session
            }

            var displayed = session
            displayed.status = .completed
            displayed.statusSince = session.statusSince ?? session.idleSince ?? session.updatedAt
            return displayed
        }
    }
}
