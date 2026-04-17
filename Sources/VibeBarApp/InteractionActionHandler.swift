import Darwin
import Foundation
import VibeBarCore

actor InteractionActionHandler {
    static let shared = InteractionActionHandler()
    private let socketClient: AgentSocketClient

    init(socketClient: AgentSocketClient = AgentSocketClient()) {
        self.socketClient = socketClient
    }

    func submit(
        interaction: PendingInteraction,
        decision: InteractionDecision,
        sessionPID: Int32?
    ) async -> Bool {
        if OpenCodeLegacyPermissionBridge.canDirectlyReply(interaction) {
            let submitted = await OpenCodeLegacyPermissionBridge.submitDecision(
                interaction: interaction,
                userDecision: decision,
                sessionPID: sessionPID
            )
            if submitted {
                return await submitToAgent(requestID: interaction.id, decision: nil)
            }
        }

        let relayDecision = OpenCodeLegacyPermissionBridge.relayDecision(
            for: interaction,
            userDecision: decision
        )
        return await submitToAgent(requestID: interaction.id, decision: relayDecision)
    }

    private func submitToAgent(requestID: String, decision: InteractionDecision?) async -> Bool {
        let response = AgentInteractionResponse(requestID: requestID, decision: decision)
        let envelope = AgentEnvelope(kind: .interactionResponse, response: response)
        return await Task.detached(priority: .userInitiated) {
            self.socketClient.send(envelope)
        }.value
    }
}
