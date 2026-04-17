import Foundation
import Testing
@testable import VibeBarCore

@Test func interactionBrokerStateDrainsPreviousInteractionForSameSession() {
    var state = InteractionBrokerState()
    let first = brokerInteraction(id: "interaction-1", sessionID: "plugin-codex-hook-sess-1")
    let second = brokerInteraction(id: "interaction-2", sessionID: "plugin-codex-hook-sess-1")

    let initialDrain = state.begin(first)
    let replacementDrain = state.begin(second)

    #expect(initialDrain == nil)
    #expect(replacementDrain?.id == first.id)
    #expect(state.interaction(requestID: second.id)?.id == second.id)
    #expect(state.interaction(requestID: first.id) == nil)
}

@Test func interactionBrokerStateTimeoutRemovesPendingInteraction() {
    var state = InteractionBrokerState()
    let interaction = brokerInteraction(id: "interaction-timeout", sessionID: "plugin-codex-hook-sess-2")
    _ = state.begin(interaction)

    let removed = state.timeout(requestID: interaction.id)

    #expect(removed?.id == interaction.id)
    #expect(state.interaction(requestID: interaction.id) == nil)
}

@Test func interactionBrokerStateDisconnectRemovesPendingInteraction() {
    var state = InteractionBrokerState()
    let interaction = brokerInteraction(id: "interaction-disconnect", sessionID: "plugin-codex-hook-sess-3")
    _ = state.begin(interaction)

    let removed = state.disconnect(requestID: interaction.id)

    #expect(removed?.id == interaction.id)
    #expect(state.interaction(requestID: interaction.id) == nil)
}

@Test func interactionBrokerStateLateResponseDoesNotRestoreInteraction() {
    var state = InteractionBrokerState()
    let interaction = brokerInteraction(id: "interaction-late", sessionID: "plugin-codex-hook-sess-4")
    _ = state.begin(interaction)
    _ = state.timeout(requestID: interaction.id)

    let resolved = state.resolve(
        requestID: interaction.id,
        response: AgentInteractionResponse(
            requestID: interaction.id,
            decision: InteractionDecision(behavior: .deny)
        )
    )

    #expect(resolved == nil)
    #expect(state.interaction(requestID: interaction.id) == nil)
}

private func brokerInteraction(id: String, sessionID: String) -> PendingInteraction {
    PendingInteraction(
        id: id,
        sessionID: sessionID,
        tool: .codex,
        kind: .permission,
        message: "允许执行吗？",
        requestedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
}
