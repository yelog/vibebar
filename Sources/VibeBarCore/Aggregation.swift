import Foundation

public enum SummaryBuilder {
    public static func build(sessions: [SessionSnapshot], now: Date = Date()) -> GlobalSummary {
        let active = sessions.sorted { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.pid < rhs.pid
            }
            return lhs.updatedAt > rhs.updatedAt
        }

        var globalCounts: [ToolActivityState: Int] = [:]
        var toolBuckets: [ToolKind: [SessionSnapshot]] = [:]

        for session in active {
            globalCounts[session.status, default: 0] += 1
            toolBuckets[session.tool, default: []].append(session)
        }

        var byTool: [ToolKind: ToolSummary] = [:]
        for tool in ToolKind.allCases {
            let bucket = toolBuckets[tool] ?? []
            var counts: [ToolActivityState: Int] = [:]
            for session in bucket {
                counts[session.status, default: 0] += 1
            }

            let overall = resolveOverallState(counts: counts, total: bucket.count)
            byTool[tool] = ToolSummary(tool: tool, total: bucket.count, counts: counts, overall: overall)
        }

        return GlobalSummary(total: active.count, counts: globalCounts, byTool: byTool, updatedAt: now)
    }

    private static func resolveOverallState(counts: [ToolActivityState: Int], total: Int) -> ToolOverallState {
        guard total > 0 else { return .stopped }
        if (counts[.running] ?? 0) > 0 { return .running }
        if (counts[.awaitingInput] ?? 0) > 0 { return .awaitingInput }
        if (counts[.idle] ?? 0) > 0 { return .idle }
        return .unknown
    }
}
