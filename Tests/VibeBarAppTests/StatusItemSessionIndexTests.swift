import Foundation
import Testing
@testable import VibeBarApp
@testable import VibeBarCore

@Test func statusItemSessionIndexKeepsOneDeterministicValueForDuplicateID() {
    let older = makeStatusItemSession(
        id: "duplicate",
        pid: 101,
        status: .running,
        updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let newer = makeStatusItemSession(
        id: "duplicate",
        pid: 202,
        status: .idle,
        updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
    )

    let indexed = StatusItemController.indexSessionsByID([older, newer])
    let reversed = StatusItemController.indexSessionsByID([newer, older])

    #expect(indexed.count == 1)
    #expect(indexed["duplicate"]?.pid == 202)
    #expect(indexed["duplicate"]?.status == .idle)
    #expect(reversed["duplicate"]?.pid == indexed["duplicate"]?.pid)
}

@Test func statusItemSessionIndexUsesLowerPIDWhenTimestampsMatch() {
    let higherPID = makeStatusItemSession(
        id: "duplicate",
        pid: 202,
        status: .running,
        updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let lowerPID = makeStatusItemSession(
        id: "duplicate",
        pid: 101,
        status: .idle,
        updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )

    let indexed = StatusItemController.indexSessionsByID([higherPID, lowerPID])

    #expect(indexed["duplicate"]?.pid == 101)
    #expect(indexed["duplicate"]?.status == .idle)
}

private func makeStatusItemSession(
    id: String,
    pid: Int32,
    status: ToolActivityState,
    updatedAt: Date
) -> SessionSnapshot {
    SessionSnapshot(
        id: id,
        tool: .opencode,
        pid: pid,
        status: status,
        source: .processScan,
        startedAt: updatedAt,
        updatedAt: updatedAt,
        command: ["opencode"]
    )
}
