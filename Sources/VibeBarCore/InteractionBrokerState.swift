import Foundation

public struct InteractionBrokerState: Sendable, Equatable {
    private var interactionsByRequestID: [String: PendingInteraction] = [:]
    private var requestIDsBySessionID: [String: String] = [:]
    private var seenRequestIDs: Set<String> = []

    public init() {}

    public mutating func begin(_ interaction: PendingInteraction) -> PendingInteraction? {
        var drained: PendingInteraction?
        if let existingRequestID = requestIDsBySessionID[interaction.sessionID],
           existingRequestID != interaction.id {
            drained = interactionsByRequestID.removeValue(forKey: existingRequestID)
        }

        seenRequestIDs.insert(interaction.id)
        interactionsByRequestID[interaction.id] = interaction
        requestIDsBySessionID[interaction.sessionID] = interaction.id
        return drained
    }

    public mutating func resolve(
        requestID: String,
        response: AgentInteractionResponse
    ) -> PendingInteraction? {
        remove(requestID: requestID)
    }

    public mutating func timeout(requestID: String) -> PendingInteraction? {
        remove(requestID: requestID)
    }

    public mutating func disconnect(requestID: String) -> PendingInteraction? {
        remove(requestID: requestID)
    }

    public mutating func clear(sessionID: String) -> PendingInteraction? {
        guard let requestID = requestIDsBySessionID[sessionID] else {
            return nil
        }
        return remove(requestID: requestID)
    }

    public func interaction(requestID: String) -> PendingInteraction? {
        interactionsByRequestID[requestID]
    }

    public func requestID(sessionID: String) -> String? {
        requestIDsBySessionID[sessionID]
    }

    public func hasSeen(requestID: String) -> Bool {
        seenRequestIDs.contains(requestID)
    }

    private mutating func remove(requestID: String) -> PendingInteraction? {
        guard let interaction = interactionsByRequestID.removeValue(forKey: requestID) else {
            return nil
        }

        if requestIDsBySessionID[interaction.sessionID] == requestID {
            requestIDsBySessionID.removeValue(forKey: interaction.sessionID)
        }
        return interaction
    }
}
