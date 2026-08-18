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
