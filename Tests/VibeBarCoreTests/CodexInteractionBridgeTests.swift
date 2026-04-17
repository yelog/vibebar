import Foundation
import Testing
@testable import VibeBarCore

@Test func codexInteractionBridgeMapsPermissionRequestToPermissionInteraction() throws {
    let interaction = try #require(
        CodexInteractionBridge.interaction(
            from: Data(
                """
                {
                  "hook_event_name": "PermissionRequest",
                  "session_id": "sess-1",
                  "cwd": "/tmp/project",
                  "tool_name": "exec_command",
                  "tool_input": {
                    "command": "rm -rf build"
                  }
                }
                """.utf8
            ),
            context: testCodexBridgeContext()
        )
    )

    #expect(interaction.tool == .codex)
    #expect(interaction.kind == .permission)
    #expect(interaction.sessionID == "plugin-codex-hook-sess-1")
    #expect(interaction.transportContext["hook_event_name"] == "PermissionRequest")
    #expect(interaction.transportContext["tool_name"] == "exec_command")
    #expect(interaction.transportContext["cwd"] == "/tmp/project")
    #expect(interaction.transportContext["request_kind"] == "permission")
}

@Test func codexInteractionBridgeMapsAskUserQuestionToStructuredPrompts() throws {
    let interaction = try #require(
        CodexInteractionBridge.interaction(
            from: Data(
                """
                {
                  "hook_event_name": "PermissionRequest",
                  "session_id": "sess-2",
                  "cwd": "/tmp/project",
                  "tool_name": "AskUserQuestion",
                  "tool_input": {
                    "question": "回答以下问题",
                    "questions": [
                      {
                        "header": "工作模式",
                        "title": "你希望我接下来以哪种方式协作？",
                        "options": [
                          { "value": "direct", "label": "直接执行" },
                          { "value": "plan", "label": "先给方案" }
                        ]
                      },
                      {
                        "header": "工作模式",
                        "title": "是否补充额外约束？",
                        "free_text": true,
                        "allow_multiple": false
                      }
                    ]
                  }
                }
                """.utf8
            ),
            context: testCodexBridgeContext()
        )
    )

    #expect(interaction.kind == .question)
    #expect(interaction.message == "回答以下问题")
    #expect(interaction.prompts.count == 2)
    #expect(interaction.prompts[0].id == "工作模式")
    #expect(interaction.prompts[0].options.map(\.id) == ["direct", "plan"])
    #expect(interaction.prompts[1].id == "工作模式")
    #expect(interaction.prompts[1].allowsFreeText)
    #expect(interaction.transportContext["request_kind"] == "question")
}

@Test func codexInteractionBridgeMapsPlanReviewPayload() throws {
    let interaction = try #require(
        CodexInteractionBridge.interaction(
            from: Data(
                """
                {
                  "hook_event_name": "PlanReview",
                  "session_id": "sess-3",
                  "cwd": "/tmp/project",
                  "title": "计划审查",
                  "message": "是否继续按这个计划执行？"
                }
                """.utf8
            ),
            context: testCodexBridgeContext()
        )
    )

    #expect(interaction.kind == .planReview)
    #expect(interaction.title == "计划审查")
    #expect(interaction.message == "是否继续按这个计划执行？")
    #expect(interaction.transportContext["request_kind"] == "plan_review")
}

@Test func codexInteractionBridgeBuildsPermissionReplyJSON() throws {
    let interaction = PendingInteraction(
        id: "permission-1",
        sessionID: "plugin-codex-hook-sess-1",
        tool: .codex,
        kind: .permission,
        message: "允许执行吗？",
        requestedAt: Date(timeIntervalSince1970: 1_700_000_000),
        transportContext: ["hook_event_name": "PermissionRequest"]
    )

    let reply = try jsonObject(
        from: CodexInteractionBridge.responseData(
            for: interaction,
            decision: InteractionDecision(behavior: .allow)
        )
    )

    let hookSpecificOutput = try #require(reply["hookSpecificOutput"] as? [String: Any])
    #expect(hookSpecificOutput["hookEventName"] as? String == "PermissionRequest")
    let decision = try #require(hookSpecificOutput["decision"] as? [String: Any])
    #expect(decision["behavior"] as? String == "allow")
}

@Test func codexInteractionBridgeBuildsQuestionAnswersWithStableKeys() throws {
    let interaction = PendingInteraction(
        id: "question-1",
        sessionID: "plugin-codex-hook-sess-2",
        tool: .codex,
        kind: .question,
        message: "回答以下问题",
        prompts: [
            InteractionPrompt(
                id: "工作模式",
                title: "你希望我接下来以哪种方式协作？",
                options: [InteractionOption(id: "direct", label: "直接执行")]
            ),
            InteractionPrompt(
                id: "工作模式",
                title: "是否补充额外约束？",
                allowsFreeText: true
            ),
            InteractionPrompt(
                id: "",
                title: "其他说明",
                allowsFreeText: true
            ),
        ],
        requestedAt: Date(timeIntervalSince1970: 1_700_000_000),
        transportContext: ["hook_event_name": "PermissionRequest"]
    )

    let decision = InteractionDecision(
        behavior: .allow,
        metadata: [
            "answer.工作模式": "direct",
            "answer.工作模式_2": "需要先拆计划",
            "answer.answer_3": "请保守修改",
        ]
    )

    let reply = try jsonObject(from: CodexInteractionBridge.responseData(for: interaction, decision: decision))
    let hookSpecificOutput = try #require(reply["hookSpecificOutput"] as? [String: Any])
    let responseDecision = try #require(hookSpecificOutput["decision"] as? [String: Any])
    #expect(responseDecision["behavior"] as? String == "allow")
    let updatedInput = try #require(responseDecision["updatedInput"] as? [String: Any])
    let answers = try #require(updatedInput["answers"] as? [String: String])
    #expect(answers["工作模式"] == "direct")
    #expect(answers["工作模式_2"] == "需要先拆计划")
    #expect(answers["answer_3"] == "请保守修改")
}

@Test func codexInteractionBridgeDefaultDecisionUsesConservativeDeny() {
    let permission = PendingInteraction(
        id: "permission-timeout",
        sessionID: "plugin-codex-hook-sess-4",
        tool: .codex,
        kind: .permission,
        message: "允许执行吗？",
        requestedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let planReview = PendingInteraction(
        id: "plan-timeout",
        sessionID: "plugin-codex-hook-sess-5",
        tool: .codex,
        kind: .planReview,
        message: "是否继续？",
        requestedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )

    let permissionDecision = CodexInteractionBridge.defaultDecision(for: permission, reason: "timeout")
    let planReviewDecision = CodexInteractionBridge.defaultDecision(for: planReview, reason: "disconnect")

    #expect(permissionDecision?.behavior == .deny)
    #expect(permissionDecision?.metadata["reason"] == "timeout")
    #expect(planReviewDecision?.behavior == .deny)
    #expect(planReviewDecision?.metadata["reason"] == "disconnect")
}

private func testCodexBridgeContext() -> CodexHookBridgeContext {
    CodexHookBridgeContext(
        environment: [:],
        currentDirectory: "/tmp/current",
        processID: 9001,
        parentPID: 4242
    )
}

private func jsonObject(from data: Data) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}
