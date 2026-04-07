import Foundation
import Testing
import VibeBarCore
@testable import VibeBarApp

@MainActor
@Test func sessionListPresentationSortsByUpdatedAtDescending() {
    let sessions = [
        makeSession(id: "b", tool: .codex, pid: 20, updatedAt: 20),
        makeSession(id: "a", tool: .codex, pid: 10, updatedAt: 30),
        makeSession(id: "c", tool: .codex, pid: 5, updatedAt: 20),
    ]

    let sorted = SessionListPresentation.sortedSessions(sessions)

    #expect(sorted.map(\.id) == ["a", "c", "b"])
}

@MainActor
@Test func sessionListPresentationPrioritizesAwaitingThenRunningThenIdle() {
    let sessions = [
        makeSession(id: "idle", tool: .codex, pid: 10, status: .idle, updatedAt: 300, idleSince: 290),
        makeSession(id: "running", tool: .codex, pid: 11, status: .running, updatedAt: 200, statusSince: 150),
        makeSession(id: "awaiting", tool: .codex, pid: 12, status: .awaitingInput, updatedAt: 100, statusSince: 90),
    ]

    let sorted = SessionListPresentation.sortedSessions(sessions)

    #expect(sorted.map(\.id) == ["awaiting", "running", "idle"])
}

@MainActor
@Test func sessionListPresentationPrioritizesMoreRecentStatusEntryWithinSameState() {
    let sessions = [
        makeSession(id: "older-running", tool: .codex, pid: 10, status: .running, updatedAt: 400, statusSince: 100),
        makeSession(id: "newer-running", tool: .codex, pid: 11, status: .running, updatedAt: 200, statusSince: 300),
    ]

    let sorted = SessionListPresentation.sortedSessions(sessions)

    #expect(sorted.map(\.id) == ["newer-running", "older-running"])
}

@MainActor
@Test func sessionListPresentationKeepsGroupsAndSortsGroupsByTopSessionPriority() {
    let sessions = [
        makeSession(id: "gemini-1", tool: .gemini, pid: 30, status: .idle, updatedAt: 300, idleSince: 290),
        makeSession(id: "codex-1", tool: .codex, pid: 20, status: .running, updatedAt: 200, statusSince: 180),
        makeSession(id: "codex-2", tool: .codex, pid: 10, status: .awaitingInput, updatedAt: 100, statusSince: 95),
    ]

    let groups = SessionListPresentation.groupedSessions(sessions, mode: .tool)

    #expect(groups.map(\.id) == ["tool:codex", "tool:gemini"])
    #expect(SessionListPresentation.title(for: groups[0]) == "Codex")
    #expect(SessionListPresentation.title(for: groups[1]) == "Gemini CLI")
    #expect(groups[0].sessions.map(\.id) == ["codex-2", "codex-1"])
    #expect(groups[1].sessions.map(\.id) == ["gemini-1"])
}

@MainActor
@Test func sessionListPresentationGroupsProjectsByFullPathAndDisambiguatesSameFolderName() {
    let sessions = [
        makeSession(
            id: "server-app",
            tool: .opencode,
            pid: 30,
            status: .running,
            updatedAt: 300,
            statusSince: 260,
            cwd: "/Users/dev/server/app"
        ),
        makeSession(
            id: "mobile-app",
            tool: .codex,
            pid: 20,
            status: .awaitingInput,
            updatedAt: 200,
            statusSince: 190,
            cwd: "/Users/dev/mobile/app"
        ),
        makeSession(
            id: "mobile-worker",
            tool: .gemini,
            pid: 10,
            status: .running,
            updatedAt: 100,
            statusSince: 80,
            cwd: "/Users/dev/mobile/app"
        ),
    ]

    let groups = SessionListPresentation.groupedSessions(sessions, mode: .project)

    #expect(groups.count == 2)
    #expect(groups.map { SessionListPresentation.title(for: $0) } == ["app", "app"])
    #expect(groups[0].sessions.map(\.id) == ["mobile-app", "mobile-worker"])
    #expect(groups[1].sessions.map(\.id) == ["server-app"])
    #expect(Set(groups.compactMap { SessionListPresentation.detail(for: $0) }) == Set(["mobile", "server"]))
}

@MainActor
@Test func sessionListPresentationUsesUnknownDirectoryBucketForMissingProjectPath() {
    let sessions = [
        makeSession(id: "unknown", tool: .codex, pid: 10, updatedAt: 300, cwd: nil),
        makeSession(id: "known", tool: .gemini, pid: 11, updatedAt: 200, cwd: "/tmp/project"),
    ]

    let groups = SessionListPresentation.groupedSessions(sessions, mode: .project)

    #expect(groups.count == 2)
    #expect(SessionListPresentation.title(for: groups[0]) == L10n.shared.string(.dirUnknown))
    #expect(SessionListPresentation.title(for: groups[1]) == "project")
}

@MainActor
@Test func sessionListPresentationCondensesOnlyIdleSessionsPastThreshold() {
    let now = Date(timeIntervalSince1970: 3_600)
    let condensedIdle = makeSession(
        id: "idle-old",
        tool: .codex,
        pid: 10,
        status: .idle,
        updatedAt: 3_000,
        idleSince: 1_700
    )
    let freshIdle = makeSession(
        id: "idle-new",
        tool: .codex,
        pid: 11,
        status: .idle,
        updatedAt: 3_500,
        idleSince: 2_000
    )
    let awaiting = makeSession(
        id: "awaiting",
        tool: .codex,
        pid: 12,
        status: .awaitingInput,
        updatedAt: 3_000,
        idleSince: 1_000
    )

    #expect(SessionListPresentation.isCondensed(condensedIdle, now: now))
    #expect(!SessionListPresentation.isCondensed(freshIdle, now: now))
    #expect(!SessionListPresentation.isCondensed(awaiting, now: now))
}

private func makeSession(
    id: String,
    tool: ToolKind,
    pid: Int32,
    status: ToolActivityState = .running,
    updatedAt: TimeInterval,
    idleSince: TimeInterval? = nil,
    statusSince: TimeInterval? = nil,
    cwd: String? = "/tmp/project"
) -> SessionSnapshot {
    SessionSnapshot(
        id: id,
        tool: tool,
        pid: pid,
        status: status,
        source: .sessionFile,
        startedAt: Date(timeIntervalSince1970: 1_000),
        updatedAt: Date(timeIntervalSince1970: updatedAt),
        statusSince: statusSince.map { Date(timeIntervalSince1970: $0) },
        idleSince: idleSince.map { Date(timeIntervalSince1970: $0) },
        cwd: cwd,
        command: [tool.executable]
    )
}
