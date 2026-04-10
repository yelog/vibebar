import Foundation
import Testing
import VibeBarCore
@testable import VibeBarApp

@Test func canDirectlyReplyToOpenCodePermissionWithRequestID() {
    let interaction = PendingInteraction(
        id: "interaction-1",
        sessionID: "session-1",
        tool: .opencode,
        kind: .permission,
        message: "允许访问目录吗？",
        requestedAt: Date(),
        transportContext: [
            "opencode_request_id": "per_123",
            "server_url": "http://127.0.0.1:4321",
        ]
    )

    #expect(OpenCodeLegacyPermissionBridge.canDirectlyReply(interaction))
}

@Test func canDirectlyReplyToOpenCodeQuestionWithRequestID() {
    let interaction = PendingInteraction(
        id: "interaction-question-1",
        sessionID: "session-1",
        tool: .opencode,
        kind: .question,
        message: "请选择发版类型",
        options: [
            InteractionOption(id: "0", label: "release"),
            InteractionOption(id: "1", label: "beta"),
        ],
        requestedAt: Date(),
        transportContext: [
            "opencode_request_id": "que_123",
            "server_url": "http://127.0.0.1:4321",
        ]
    )

    #expect(OpenCodeLegacyPermissionBridge.canDirectlyReply(interaction))
}

@Test func relayDecisionKeepsLegacyOpenCodeFallbackCompatible() {
    let interaction = PendingInteraction(
        id: "interaction-legacy",
        sessionID: "session-1",
        tool: .opencode,
        kind: .permission,
        message: "允许访问目录吗？",
        requestedAt: Date(),
        transportContext: [
            "opencode_request_id": "per_123",
            "request_kind": "permission",
        ]
    )

    let once = OpenCodeLegacyPermissionBridge.relayDecision(
        for: interaction,
        userDecision: InteractionDecision(behavior: .select, optionID: "once")
    )
    let reject = OpenCodeLegacyPermissionBridge.relayDecision(
        for: interaction,
        userDecision: InteractionDecision(behavior: .select, optionID: "reject")
    )
    let always = OpenCodeLegacyPermissionBridge.relayDecision(
        for: interaction,
        userDecision: InteractionDecision(behavior: .select, optionID: "always")
    )

    #expect(once?.behavior == .allow)
    #expect(reject?.behavior == .deny)
    #expect(always == nil)
}

@Test func relayDecisionKeepsOpenCodeQuestionDecisionUntouched() {
    let interaction = PendingInteraction(
        id: "interaction-question-2",
        sessionID: "session-1",
        tool: .opencode,
        kind: .question,
        message: "请选择发版类型",
        options: [
            InteractionOption(id: "0", label: "release"),
            InteractionOption(id: "1", label: "beta"),
        ],
        requestedAt: Date(),
        transportContext: [
            "opencode_request_id": "que_123",
            "request_kind": "question",
        ]
    )

    let decision = InteractionDecision(behavior: .select, optionID: "1", text: "beta")
    let relayed = OpenCodeLegacyPermissionBridge.relayDecision(
        for: interaction,
        userDecision: decision
    )

    #expect(relayed == decision)
}
