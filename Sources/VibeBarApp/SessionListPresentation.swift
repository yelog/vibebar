import Foundation
import VibeBarCore

enum SessionListPresentation {
    struct Group: Identifiable {
        let tool: ToolKind
        let sessions: [SessionSnapshot]

        var id: String { tool.rawValue }
    }

    static let idleCollapseThreshold: TimeInterval = 30 * 60

    static func sortedSessions(_ sessions: [SessionSnapshot]) -> [SessionSnapshot] {
        sessions.sorted(by: compareSessions)
    }

    static func groupedSessions(_ sessions: [SessionSnapshot]) -> [Group] {
        let orderedSessions = sortedSessions(sessions)
        var buckets: [ToolKind: [SessionSnapshot]] = [:]

        for session in orderedSessions {
            buckets[session.tool, default: []].append(session)
        }

        let toolOrder = Dictionary(
            uniqueKeysWithValues: ToolKind.allCases.enumerated().map { ($0.element, $0.offset) }
        )

        return ToolKind.allCases.compactMap { tool in
            guard let toolSessions = buckets[tool], !toolSessions.isEmpty else {
                return nil
            }
            return Group(tool: tool, sessions: toolSessions)
        }
        .sorted { lhs, rhs in
            guard let lhsTop = lhs.sessions.first, let rhsTop = rhs.sessions.first else {
                return (toolOrder[lhs.tool] ?? .max) < (toolOrder[rhs.tool] ?? .max)
            }

            if compareSessions(lhsTop, rhsTop) {
                return true
            }
            if compareSessions(rhsTop, lhsTop) {
                return false
            }
            return (toolOrder[lhs.tool] ?? .max) < (toolOrder[rhs.tool] ?? .max)
        }
    }

    static func isCondensed(_ session: SessionSnapshot, now: Date) -> Bool {
        guard session.status == .idle, let idleSince = session.idleSince else {
            return false
        }
        return now.timeIntervalSince(idleSince) > idleCollapseThreshold
    }

    private static func compareSessions(_ lhs: SessionSnapshot, _ rhs: SessionSnapshot) -> Bool {
        let lhsPriority = statusPriority(lhs.status)
        let rhsPriority = statusPriority(rhs.status)
        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }

        if lhs.currentStatusSince != rhs.currentStatusSince {
            return lhs.currentStatusSince > rhs.currentStatusSince
        }

        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }

        if lhs.pid != rhs.pid {
            return lhs.pid < rhs.pid
        }

        return lhs.id < rhs.id
    }

    private static func statusPriority(_ status: ToolActivityState) -> Int {
        switch status {
        case .awaitingInput:
            return 0
        case .running:
            return 1
        case .idle:
            return 2
        case .unknown:
            return 3
        }
    }
}
