import Foundation
import Testing
import VibeBarCore
@testable import VibeBarApp

@Test func completedSessionDisplayStoreShowsCompletedOnlyWithinWindow() {
    let now = Date(timeIntervalSince1970: 100)
    let session = makeSession(id: "completed", status: .idle, updatedAt: 100, idleSince: 100)
    var store = CompletedSessionDisplayStore(duration: 3)
    store.begin(for: session.id, now: now)

    let displayedSessions = store.displayedSessions(from: [session], now: now.addingTimeInterval(2))

    #expect(displayedSessions.count == 1)
    #expect(displayedSessions[0].status == .completed)
    #expect(displayedSessions[0].currentStatusSince == session.currentStatusSince)
}

@Test func completedSessionDisplayStoreExpiresAndKeepsIdleState() {
    let now = Date(timeIntervalSince1970: 100)
    let session = makeSession(id: "idle", status: .idle, updatedAt: 100, idleSince: 100)
    var store = CompletedSessionDisplayStore(duration: 3)
    store.begin(for: session.id, now: now)
    store.sync(with: [session], now: now.addingTimeInterval(3))

    let displayedSessions = store.displayedSessions(from: [session], now: now.addingTimeInterval(3))

    #expect(displayedSessions[0].status == .idle)
    #expect(store.nextExpiration(now: now.addingTimeInterval(3)) == nil)
}

@Test func completedSessionDisplayStoreClearsWhenSessionResumesRunning() {
    let now = Date(timeIntervalSince1970: 100)
    let runningSession = makeSession(id: "resumed", status: .running, updatedAt: 102, statusSince: 102)
    var store = CompletedSessionDisplayStore(duration: 3)
    store.begin(for: runningSession.id, now: now)
    store.sync(with: [runningSession], now: now.addingTimeInterval(1))

    #expect(store.isActive(for: runningSession.id, now: now.addingTimeInterval(1)) == false)
}

private func makeSession(
    id: String,
    status: ToolActivityState,
    updatedAt: TimeInterval,
    idleSince: TimeInterval? = nil,
    statusSince: TimeInterval? = nil
) -> SessionSnapshot {
    SessionSnapshot(
        id: id,
        tool: .codex,
        pid: 10,
        status: status,
        source: .sessionFile,
        startedAt: Date(timeIntervalSince1970: 50),
        updatedAt: Date(timeIntervalSince1970: updatedAt),
        statusSince: statusSince.map { Date(timeIntervalSince1970: $0) },
        idleSince: idleSince.map { Date(timeIntervalSince1970: $0) },
        command: ["codex"]
    )
}
