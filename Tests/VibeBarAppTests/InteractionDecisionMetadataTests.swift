import Foundation
import Testing

@testable import VibeBarApp
@testable import VibeBarCore

@Test func interactionDecisionMetadataEncodesMultiSelectionAsJSON() throws {
    let prompts = [
        InteractionPrompt(
            id: "question.0",
            title: "选择检查",
            allowsMultipleSelection: true
        ),
    ]
    let interaction = PendingInteraction(
        id: "opencode-que_123",
        sessionID: "plugin-opencode-test",
        tool: .opencode,
        kind: .question,
        message: "选择检查",
        prompts: prompts,
        requestedAt: Date()
    )

    let metadata = InteractionDecisionMetadataBuilder.build(
        interaction: interaction,
        prompts: prompts,
        answerKeys: ["question.0"],
        textAnswers: [:],
        selectedOptionIDs: [:],
        selectedOptionLabels: [:],
        selectedMultiValues: ["question.0": ["完整测试", "相关测试"]]
    )

    let raw = try #require(metadata["selected_values.question.0"])
    let values = try JSONDecoder().decode([String].self, from: Data(raw.utf8))
    #expect(values == ["完整测试", "相关测试"])
    #expect(metadata["answer.question.0"] == "完整测试, 相关测试")
}

@Test func interactionDecisionMetadataPreservesSingleSelectionAndFreeText() {
    let prompts = [
        InteractionPrompt(id: "question.0", title: "模式"),
        InteractionPrompt(id: "question.1", title: "说明", allowsFreeText: true),
    ]
    let interaction = PendingInteraction(
        id: "opencode-que_123",
        sessionID: "plugin-opencode-test",
        tool: .opencode,
        kind: .question,
        message: "请选择",
        prompts: prompts,
        requestedAt: Date()
    )

    let metadata = InteractionDecisionMetadataBuilder.build(
        interaction: interaction,
        prompts: prompts,
        answerKeys: ["question.0", "question.1"],
        textAnswers: ["question.1": "补充说明"],
        selectedOptionIDs: ["question.0": "0"],
        selectedOptionLabels: ["question.0": "直接实现"],
        selectedMultiValues: [:]
    )

    #expect(metadata["answer.question.0"] == "直接实现")
    #expect(metadata["option_id.question.0"] == "0")
    #expect(metadata["answer.question.1"] == "补充说明")
}

@Test func interactionDecisionMetadataRequiresEveryPromptAnswer() {
    let answerKeys = ["question.0", "question.1"]

    #expect(
        InteractionDecisionMetadataBuilder.hasAnswersForEveryPrompt(
            answerKeys: answerKeys,
            textAnswers: [:],
            selectedOptionIDs: ["question.0": "0"],
            selectedMultiValues: [:]
        ) == false
    )
    #expect(
        InteractionDecisionMetadataBuilder.hasAnswersForEveryPrompt(
            answerKeys: answerKeys,
            textAnswers: ["question.1": "补充说明"],
            selectedOptionIDs: ["question.0": "0"],
            selectedMultiValues: [:]
        )
    )
}
