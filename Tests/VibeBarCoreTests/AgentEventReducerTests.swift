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
