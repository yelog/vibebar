import SwiftUI
import VibeBarCore

struct SessionInteractionContentView: View {
    let interaction: PendingInteraction
    let actions: [SessionInteractionAction]
    let onAction: (InteractionDecision) -> Void

    @State private var selectedOptionIDs: [String: String] = [:]
    @State private var selectedOptionLabels: [String: String] = [:]
    @State private var selectedMultiValues: [String: Set<String>] = [:]
    @State private var textAnswers: [String: String] = [:]

    private var prompts: [InteractionPrompt] {
        let existing = interaction.prompts
        if !existing.isEmpty {
            return existing
        }

        if interaction.allowsFreeText {
            return [
                InteractionPrompt(
                    id: "answer_1",
                    title: interaction.title ?? interaction.message,
                    allowsFreeText: true
                )
            ]
        }

        return []
    }

    private var answerKeys: [String] {
        if interaction.tool == .codex {
            return CodexInteractionBridge.answerKeys(for: prompts)
        }

        return prompts.enumerated().map { index, prompt in
            let trimmed = prompt.id.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "answer_\(index + 1)" : trimmed
        }
    }

    var body: some View {
        Group {
            if SessionDisplayFormatter.requiresStructuredInput(for: interaction) {
                structuredContent
            } else {
                actionStrip
            }
        }
        .padding(.vertical, 1)
    }

    private var structuredContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if interaction.kind == .planReview, !actions.isEmpty {
                actionStrip
            }

            ForEach(Array(zip(answerKeys.indices, prompts)), id: \.0) { entry in
                let index = entry.0
                let prompt = entry.1
                promptEditor(prompt, answerKey: answerKeys[index])
            }

            if interaction.kind != .planReview {
                Button("提交") {
                    onAction(structuredDecision(behavior: .allow))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private func promptEditor(_ prompt: InteractionPrompt, answerKey: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(prompt.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            if !prompt.options.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(prompt.options) { option in
                        optionButton(option, prompt: prompt, answerKey: answerKey)
                    }
                }
            }

            if prompt.allowsFreeText {
                TextField(
                    prompt.metadata["placeholder"] ?? "输入回答",
                    text: textBinding(for: answerKey)
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
            }
        }
    }

    @ViewBuilder
    private func optionButton(
        _ option: InteractionOption,
        prompt: InteractionPrompt,
        answerKey: String
    ) -> some View {
        if prompt.allowsMultipleSelection {
            Button {
                toggleMultiSelection(option: option, answerKey: answerKey)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isMultiSelected(option: option, answerKey: answerKey) ? "checkmark.square.fill" : "square")
                        .font(.system(size: 11, weight: .medium))
                    Text(option.label)
                        .font(.system(size: 11))
                }
                .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
        } else {
            Button {
                selectedOptionIDs[answerKey] = option.id
                selectedOptionLabels[answerKey] = option.label
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: selectedOptionIDs[answerKey] == option.id ? "largecircle.fill.circle" : "circle")
                        .font(.system(size: 11, weight: .medium))
                    Text(option.label)
                        .font(.system(size: 11))
                }
                .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
        }
    }

    private var actionStrip: some View {
        HStack(spacing: 6) {
            ForEach(actions) { action in
                if action.role == .primary {
                    Button(action.label) {
                        onAction(mergedDecision(from: action.decision))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else {
                    Button(action.label) {
                        onAction(mergedDecision(from: action.decision))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private func mergedDecision(from decision: InteractionDecision) -> InteractionDecision {
        let metadata = structuredMetadata()
        if metadata.isEmpty {
            return decision
        }

        return InteractionDecision(
            behavior: decision.behavior,
            optionID: decision.optionID,
            text: decision.text,
            metadata: decision.metadata.merging(metadata) { _, new in new }
        )
    }

    private func structuredDecision(behavior: InteractionDecisionBehavior) -> InteractionDecision {
        InteractionDecision(
            behavior: behavior,
            metadata: structuredMetadata()
        )
    }

    private func structuredMetadata() -> [String: String] {
        var metadata: [String: String] = [:]

        for (index, prompt) in prompts.enumerated() {
            let answerKey = answerKeys[index]
            let promptID = prompt.id.trimmingCharacters(in: .whitespacesAndNewlines)
            if !promptID.isEmpty {
                metadata["prompt_id.\(answerKey)"] = promptID
            }

            if let text = normalized(textAnswers[answerKey]) {
                metadata["answer.\(answerKey)"] = text
                if interaction.kind == .planReview {
                    metadata["comment"] = text
                }
                continue
            }

            if let selectedID = selectedOptionIDs[answerKey],
               let selectedLabel = selectedOptionLabels[answerKey] {
                metadata["answer.\(answerKey)"] = selectedLabel
                metadata["selected_values"] = selectedLabel
                metadata["selected_values.\(answerKey)"] = selectedLabel
                metadata["option_id.\(answerKey)"] = selectedID
                continue
            }

            if let values = selectedMultiValues[answerKey], !values.isEmpty {
                let sortedValues = values.sorted()
                let joined = sortedValues.joined(separator: ", ")
                metadata["answer.\(answerKey)"] = joined
                metadata["selected_values"] = joined
                metadata["selected_values.\(answerKey)"] = joined
            }
        }

        return metadata
    }

    private func textBinding(for answerKey: String) -> Binding<String> {
        Binding(
            get: { textAnswers[answerKey] ?? "" },
            set: { textAnswers[answerKey] = $0 }
        )
    }

    private func toggleMultiSelection(option: InteractionOption, answerKey: String) {
        var values = selectedMultiValues[answerKey] ?? []
        if values.contains(option.label) {
            values.remove(option.label)
        } else {
            values.insert(option.label)
        }
        selectedMultiValues[answerKey] = values
    }

    private func isMultiSelected(option: InteractionOption, answerKey: String) -> Bool {
        selectedMultiValues[answerKey]?.contains(option.label) == true
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
