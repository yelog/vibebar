import AppKit
import Foundation
import VibeBarCore

final class MonitorViewModel: ObservableObject {
    @Published private(set) var sessions: [SessionSnapshot] = []
    @Published private(set) var summary: GlobalSummary = MonitorViewModel.makeEmptySummary()

    private let store = SessionFileStore()
    private let scanner = ProcessScanner()

    private var timer: Timer?

    init() {
        refreshNow()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshNow()
        }
    }

    func refreshNow() {
        let now = Date()
        store.cleanupStaleSessions(now: now, completedTTL: 20, idleTTL: 30 * 60)

        let fileSessions = store.loadAll()
        let processSessions = scanner.scan(now: now)

        let merged = merge(fileSessions: fileSessions, processSessions: processSessions, now: now)
        sessions = merged.sorted { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.pid < rhs.pid
            }
            return lhs.updatedAt > rhs.updatedAt
        }

        summary = SummaryBuilder.build(sessions: sessions, now: now)
    }

    func openSessionsFolder() {
        do {
            try VibeBarPaths.ensureDirectories()
            NSWorkspace.shared.open(VibeBarPaths.sessionsDirectory)
        } catch {
            NSSound.beep()
        }
    }

    func purgeCompleted() {
        let all = store.loadAll()
        for session in all where session.status == .completed {
            store.delete(sessionID: session.id)
        }
        refreshNow()
    }

    private func merge(
        fileSessions: [SessionSnapshot],
        processSessions: [SessionSnapshot],
        now: Date
    ) -> [SessionSnapshot] {
        let activePIDs = Set(processSessions.map { $0.pid })

        var normalized: [SessionSnapshot] = fileSessions.map { session in
            guard session.status != .completed else { return session }
            guard !activePIDs.contains(session.pid) else { return session }
            guard now.timeIntervalSince(session.updatedAt) > 2.0 else { return session }

            var updated = session
            updated.status = .completed
            updated.updatedAt = now
            updated.notes = "process-exited"
            try? store.write(updated)
            return updated
        }

        let wrapperPIDs = Set(normalized.map { $0.pid })
        for processSession in processSessions where !wrapperPIDs.contains(processSession.pid) {
            normalized.append(processSession)
        }

        return normalized
    }

    private static func makeEmptySummary() -> GlobalSummary {
        var byTool: [ToolKind: ToolSummary] = [:]
        for tool in ToolKind.allCases {
            byTool[tool] = ToolSummary(tool: tool, total: 0, counts: [:], overall: .stopped)
        }
        return GlobalSummary(total: 0, counts: [:], byTool: byTool, updatedAt: Date())
    }
}
