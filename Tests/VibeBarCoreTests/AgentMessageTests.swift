import Foundation
import Testing
@testable import VibeBarCore

private func makeMessageSession() -> SessionSnapshot {
    SessionSnapshot(
        id: "session-1",
        tool: .claudeCode,
        pid: 1001,
        parentPID: 1000,
        status: .running,
        source: .plugin,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
        cwd: "/tmp/project",
        command: ["claude"],
        notes: "note",
        title: "修复交互",
        currentTask: "等待用户确认",
        pendingInteractionID: "interaction-1"
    )
}

private func makePendingInteraction() -> PendingInteraction {
    PendingInteraction(
        id: "interaction-1",
        sessionID: "session-1",
        tool: .claudeCode,
        kind: .permission,
        title: "需要确认",
        message: "允许执行命令吗？",
        options: [
            InteractionOption(id: "allow", label: "允许"),
            InteractionOption(id: "deny", label: "拒绝"),
        ],
        requestedAt: Date(timeIntervalSince1970: 1_700_000_120),
        expiresAt: Date(timeIntervalSince1970: 1_700_000_180),
        transportContext: ["request_token": "abc123"]
    )
}

@Test func sessionSnapshotCodablePreservesCurrentTaskAndPendingInteraction() throws {
    let original = makeMessageSession()

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(original)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(SessionSnapshot.self, from: data)

    #expect(decoded.currentTask == "等待用户确认")
    #expect(decoded.pendingInteractionID == "interaction-1")
}

@Test func pendingInteractionCodablePreservesOptionsAndContext() throws {
    let original = makePendingInteraction()

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(original)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(PendingInteraction.self, from: data)

    #expect(decoded.sessionID == "session-1")
    #expect(decoded.options.count == 2)
    #expect(decoded.options[0].label == "允许")
    #expect(decoded.transportContext["request_token"] == "abc123")
}

@Test func interactionDecisionSupportsAllowDenySelectAndText() {
    let allow = InteractionDecision(behavior: .allow)
    let deny = InteractionDecision(behavior: .deny)
    let select = InteractionDecision(behavior: .select, optionID: "allow")
    let text = InteractionDecision(behavior: .text, text: "继续执行")

    #expect(allow.behavior == .allow)
    #expect(deny.behavior == .deny)
    #expect(select.optionID == "allow")
    #expect(text.text == "继续执行")
}

@Test func agentEnvelopeDecodesEventRequestAndResponse() throws {
    let event = AgentEvent(
        source: .claudePlugin,
        tool: .claudeCode,
        sessionID: "session-1",
        eventType: "status_changed",
        status: .running,
        timestamp: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let request = makePendingInteraction()
    let response = AgentInteractionResponse(
        requestID: request.id,
        decision: InteractionDecision(behavior: .allow)
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601

    let eventData = try encoder.encode(AgentEnvelope(kind: .event, event: event))
    let requestData = try encoder.encode(AgentEnvelope(kind: .interactionRequest, request: request))
    let responseData = try encoder.encode(AgentEnvelope(kind: .interactionResponse, response: response))

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let decodedEvent = try decoder.decode(AgentEnvelope.self, from: eventData)
    let decodedRequest = try decoder.decode(AgentEnvelope.self, from: requestData)
    let decodedResponse = try decoder.decode(AgentEnvelope.self, from: responseData)

    #expect(decodedEvent.kind == .event)
    #expect(decodedEvent.event?.sessionID == "session-1")
    #expect(decodedRequest.kind == .interactionRequest)
    #expect(decodedRequest.request?.id == "interaction-1")
    #expect(decodedResponse.kind == .interactionResponse)
    #expect(decodedResponse.response?.requestID == "interaction-1")
    #expect(decodedResponse.response?.decision.behavior == .allow)
}
