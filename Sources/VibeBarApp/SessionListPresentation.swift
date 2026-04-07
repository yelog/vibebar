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
        sessions.sorted { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.pid < rhs.pid
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    static func groupedSessions(_ sessions: [SessionSnapshot]) -> [Group] {
        let orderedSessions = sortedSessions(sessions)
        var buckets: [ToolKind: [SessionSnapshot]] = [:]

        for session in orderedSessions {
            buckets[session.tool, default: []].append(session)
        }

        return ToolKind.allCases.compactMap { tool in
            guard let toolSessions = buckets[tool], !toolSessions.isEmpty else {
                return nil
            }
            return Group(tool: tool, sessions: toolSessions)
        }
    }

    static func isCondensed(_ session: SessionSnapshot, now: Date) -> Bool {
        guard session.status == .idle, let idleSince = session.idleSince else {
            return false
        }
        return now.timeIntervalSince(idleSince) > idleCollapseThreshold
    }
}
