import Foundation
import Testing
@testable import VibeBarCore

@Test func agentEventReducerTreatsStopAsIdleNotDeletion() {
    let event = AgentEvent(
        source: .codexHook,
        tool: .codex,
        sessionID: "sess-stop",
        eventType: "stop"
    )

    let reduction = AgentEventReducer.reduce(event: event, previous: nil)

    #expect(reduction.shouldDeleteSession == false)
    #expect(reduction.status == .idle)
}

@Test func claudeTaskCompletedPreservesRunningStatus() {
    let previous = SessionSnapshot(
        id: "claude-plugin-session",
        tool: .claudeCode,
        pid: 10,
        status: .running,
        source: .plugin,
        startedAt: Date(timeIntervalSince1970: 100),
        updatedAt: Date(timeIntervalSince1970: 101),
        command: ["claude"]
    )
    let event = AgentEvent(
        source: .claudePlugin,
        tool: .claudeCode,
        sessionID: "session",
        eventType: "task_completed"
    )

    let reduction = AgentEventReducer.reduce(event: event, previous: previous)

    #expect(reduction.shouldDeleteSession == false)
    #expect(reduction.status == .running)
}

@Test func agentEventReducerTreatsSessionEndAsDeletion() {
    let event = AgentEvent(
        source: .codexHook,
        tool: .codex,
        sessionID: "sess-end",
        eventType: "session_end"
    )

    let reduction = AgentEventReducer.reduce(event: event, previous: nil)

    #expect(reduction.shouldDeleteSession == true)
    #expect(reduction.status == nil)
}

@Test func agentEventReducerMarksSessionStartAsRunning() {
    let event = AgentEvent(
        source: .codexHook,
        tool: .codex,
        sessionID: "sess-start",
        eventType: "session_start"
    )

    let reduction = AgentEventReducer.reduce(event: event, previous: nil)

    #expect(reduction.shouldDeleteSession == false)
    #expect(reduction.status == .running)
}

@Test func agentEventReducerPreservesExplicitStatusOverride() {
    let event = AgentEvent(
        source: .codexHook,
        tool: .codex,
        sessionID: "sess-explicit",
        eventType: "post_tool_use",
        status: .awaitingInput
    )

    let reduction = AgentEventReducer.reduce(event: event, previous: nil)

    #expect(reduction.shouldDeleteSession == false)
    #expect(reduction.status == .awaitingInput)
}

@Test func piFamilySessionEndEventRequestsDeletion() {
    let event = AgentEvent(
        source: .piExtension,
        tool: .pi,
        sessionID: "pi-sess",
        eventType: "session_ended"
    )

    let reduction = AgentEventReducer.reduce(event: event, previous: nil)

    #expect(reduction.shouldDeleteSession == true)
    #expect(reduction.status == nil)
}

@Test func piFamilyExplicitRunningStatusWins() {
    let event = AgentEvent(
        source: .piExtension,
        tool: .pi,
        sessionID: "pi-sess",
        eventType: "message_update",
        status: .running
    )

    let reduction = AgentEventReducer.reduce(event: event, previous: nil)

    #expect(reduction.shouldDeleteSession == false)
    #expect(reduction.status == .running)
}

@Test func ohMyPiExplicitIdleStatusWins() {
    let event = AgentEvent(
        source: .ohMyPiExtension,
        tool: .ohMyPi,
        sessionID: "omp-sess",
        eventType: "session_stop",
        status: .idle
    )

    let reduction = AgentEventReducer.reduce(event: event, previous: nil)

    #expect(reduction.shouldDeleteSession == false)
    #expect(reduction.status == .idle)
}

@Test func piFamilyEventWithoutExplicitStatusFallsBackToGenericHeuristics() {
    let event = AgentEvent(
        source: .piExtension,
        tool: .pi,
        sessionID: "pi-sess",
        eventType: "input"
    )

    let reduction = AgentEventReducer.reduce(event: event, previous: nil)

    #expect(reduction.shouldDeleteSession == false)
    #expect(reduction.status == .running)
}
