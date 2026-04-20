import CoreGraphics
import Foundation
import VibeBarCore

enum SessionRowPresentationContext: Sendable {
    case flat
    case toolGroup
    case projectGroup

    var showsToolIcon: Bool {
        switch self {
        case .flat, .projectGroup:
            return true
        case .toolGroup:
            return false
        }
    }

    var showsDirectory: Bool {
        switch self {
        case .flat, .toolGroup:
            return true
        case .projectGroup:
            return false
        }
    }

    var contentIndent: CGFloat {
        switch self {
        case .flat:
            return 29
        case .toolGroup:
            return 13
        case .projectGroup:
            return 29
        }
    }
}

@MainActor
enum SessionListPresentation {
    struct ProjectMetadata: Sendable, Equatable {
        let path: String?
        let displayName: String
        let disambiguation: String?
    }

    enum GroupKind: Sendable, Equatable {
        case tool(ToolKind)
        case project(ProjectMetadata)

        var id: String {
            switch self {
            case .tool(let tool):
                return "tool:\(tool.rawValue)"
            case .project(let metadata):
                return "project:\(metadata.path ?? "unknown")"
            }
        }

        var rowContext: SessionRowPresentationContext {
            switch self {
            case .tool:
                return .toolGroup
            case .project:
                return .projectGroup
            }
        }
    }

    struct Group: Identifiable, Sendable {
        let kind: GroupKind
        let sessions: [SessionSnapshot]

        var id: String { kind.id }
    }

    private struct GroupEntry {
        let group: Group
        let orderHint: Int
    }

    static let idleCollapseThreshold: TimeInterval = 30 * 60

    static func sortedSessions(_ sessions: [SessionSnapshot]) -> [SessionSnapshot] {
        sessions.sorted(by: compareSessions)
    }

    static func groupedSessions(_ sessions: [SessionSnapshot], mode: SessionGroupingMode) -> [Group] {
        switch mode {
        case .none:
            return []
        case .tool:
            return toolGroups(sessions)
        case .project:
            return projectGroups(sessions)
        }
    }

    static func rowContext(for mode: SessionGroupingMode) -> SessionRowPresentationContext {
        switch mode {
        case .none:
            return .flat
        case .tool:
            return .toolGroup
        case .project:
            return .projectGroup
        }
    }

    private static func toolGroups(_ sessions: [SessionSnapshot]) -> [Group] {
        let orderedSessions = sortedSessions(sessions)
        var buckets: [ToolKind: [SessionSnapshot]] = [:]

        for session in orderedSessions {
            buckets[session.tool, default: []].append(session)
        }

        let toolOrder = Dictionary(
            uniqueKeysWithValues: ToolKind.allCases.enumerated().map { ($0.element, $0.offset) }
        )

        let entries = ToolKind.allCases.compactMap { tool -> GroupEntry? in
            guard let toolSessions = buckets[tool], !toolSessions.isEmpty else {
                return nil
            }
            return GroupEntry(
                group: Group(kind: .tool(tool), sessions: toolSessions),
                orderHint: toolOrder[tool] ?? .max
            )
        }
        return sortGroupEntries(entries).map(\.group)
    }

    private static func projectGroups(_ sessions: [SessionSnapshot]) -> [Group] {
        let orderedSessions = sortedSessions(sessions)
        var buckets: [String: [SessionSnapshot]] = [:]
        var orderedKeys: [String] = []

        for session in orderedSessions {
            let key = normalizedProjectPath(session.cwd) ?? unknownProjectBucketKey
            if buckets[key] == nil {
                orderedKeys.append(key)
            }
            buckets[key, default: []].append(session)
        }

        let metadataByKey = buildProjectMetadata(keys: orderedKeys)
        let entries = orderedKeys.compactMap { key -> GroupEntry? in
            guard let groupSessions = buckets[key], !groupSessions.isEmpty,
                  let metadata = metadataByKey[key] else {
                return nil
            }
            return GroupEntry(
                group: Group(kind: .project(metadata), sessions: groupSessions),
                orderHint: .max
            )
        }
        return sortGroupEntries(entries).map(\.group)
    }

    static func title(for group: Group) -> String {
        switch group.kind {
        case .tool(let tool):
            return tool.displayName
        case .project(let metadata):
            return metadata.displayName
        }
    }

    static func detail(for group: Group) -> String? {
        switch group.kind {
        case .tool:
            return nil
        case .project(let metadata):
            return metadata.disambiguation
        }
    }

    private static func sortGroupEntries(_ entries: [GroupEntry]) -> [GroupEntry] {
        entries.sorted { lhs, rhs in
            guard let lhsTop = lhs.group.sessions.first, let rhsTop = rhs.group.sessions.first else {
                return lhs.orderHint < rhs.orderHint
            }

            if compareSessions(lhsTop, rhsTop) {
                return true
            }
            if compareSessions(rhsTop, lhsTop) {
                return false
            }

            if lhs.orderHint != rhs.orderHint {
                return lhs.orderHint < rhs.orderHint
            }

            return lhs.group.id < rhs.group.id
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
        case .completed:
            return 2
        case .idle:
            return 3
        case .unknown:
            return 4
        }
    }

    private static let unknownProjectBucketKey = "__unknown_project__"

    private static func buildProjectMetadata(keys: [String]) -> [String: ProjectMetadata] {
        var metadataByKey: [String: ProjectMetadata] = [:]

        let pathKeys = keys.filter { $0 != unknownProjectBucketKey }
        let displayNames = Dictionary(uniqueKeysWithValues: pathKeys.map { key in
            (key, basename(for: key))
        })
        let collisions = Dictionary(grouping: pathKeys, by: { displayNames[$0] ?? "" })

        var disambiguationByKey: [String: String] = [:]
        for paths in collisions.values where paths.count > 1 {
            let resolved = resolveDisambiguation(for: paths)
            for (path, detail) in resolved {
                disambiguationByKey[path] = detail
            }
        }

        for key in pathKeys {
            metadataByKey[key] = ProjectMetadata(
                path: key,
                displayName: displayNames[key] ?? key,
                disambiguation: disambiguationByKey[key]
            )
        }

        metadataByKey[unknownProjectBucketKey] = ProjectMetadata(
            path: nil,
            displayName: L10n.shared.string(.dirUnknown),
            disambiguation: nil
        )

        return metadataByKey
    }

    private static func normalizedProjectPath(_ cwd: String?) -> String? {
        guard let cwd else { return nil }
        let trimmed = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let expanded = (trimmed as NSString).expandingTildeInPath
        let standardized = (expanded as NSString).standardizingPath
        return standardized.isEmpty ? nil : standardized
    }

    private static func basename(for path: String) -> String {
        let basename = (path as NSString).lastPathComponent
        if !basename.isEmpty {
            return basename
        }
        return path == "/" ? "/" : path
    }

    private static func resolveDisambiguation(for paths: [String]) -> [String: String] {
        let parentComponents = Dictionary(uniqueKeysWithValues: paths.map { path in
            (path, pathComponents(for: path).dropLast())
        })
        let maxDepth = max(parentComponents.values.map(\.count).max() ?? 0, 1)

        for depth in 1...maxDepth {
            var suffixes: [String: String] = [:]
            for path in paths {
                let components = Array(parentComponents[path] ?? [])
                let suffix = components.suffix(min(depth, components.count))
                let label = suffix.isEmpty ? "/" : suffix.joined(separator: "/")
                suffixes[path] = label
            }
            if Set(suffixes.values).count == suffixes.count {
                return suffixes
            }
        }

        return Dictionary(uniqueKeysWithValues: paths.map { path in
            let parent = (path as NSString).deletingLastPathComponent
            let label = (parent as NSString).abbreviatingWithTildeInPath
            return (path, label)
        })
    }

    private static func pathComponents(for path: String) -> [String] {
        (path as NSString).pathComponents.filter { $0 != "/" }
    }
}
