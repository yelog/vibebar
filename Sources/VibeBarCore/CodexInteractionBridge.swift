import Foundation

public enum CodexInteractionBridge {
    public static func answerKeys(for prompts: [InteractionPrompt]) -> [String] {
        stableAnswerKeys(for: prompts)
    }

    public static func interaction(from data: Data, context: CodexHookBridgeContext) -> PendingInteraction? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return interaction(from: json, context: context)
    }

    public static func responseData(for interaction: PendingInteraction, decision: InteractionDecision?) -> Data {
        let effectiveDecision = decision ?? defaultDecision(for: interaction, reason: "no_response")
        let hookEventName = interaction.transportContext["hook_event_name"] ?? defaultHookEventName(for: interaction)

        var hookSpecificOutput: [String: Any] = [
            "hookEventName": hookEventName,
        ]

        if let decisionPayload = decisionPayload(for: interaction, decision: effectiveDecision) {
            hookSpecificOutput["decision"] = decisionPayload
        }

        let payload: [String: Any] = ["hookSpecificOutput": hookSpecificOutput]
        let data = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data()
        return data
    }

    public static func defaultDecision(
        for interaction: PendingInteraction,
        reason: String
    ) -> InteractionDecision? {
        InteractionDecision(
            behavior: .deny,
            metadata: ["reason": reason]
        )
    }

    static func interaction(
        from json: [String: Any],
        context: CodexHookBridgeContext
    ) -> PendingInteraction? {
        guard let rawSessionID = firstString(in: json, keys: ["session_id", "sessionId"]),
              let kind = interactionKind(from: json) else {
            return nil
        }

        let sessionID = compositeSessionID(from: rawSessionID)
        let hookEventName = firstString(
            in: json,
            keys: ["hook_event_name", "hookEventName", "event_name", "eventName"]
        ) ?? defaultHookEventName(for: kind)
        let toolName = firstString(in: json, keys: ["tool_name", "toolName", "tool", "name"])
        let cwd = firstString(in: json, keys: ["cwd"]) ?? context.currentDirectory
        let toolInput = firstDictionary(in: json, keys: ["tool_input", "toolInput"])
        let requestedAt = Date()

        let prompts = prompts(from: json, toolInput: toolInput, kind: kind)
        let message = interactionMessage(from: json, toolInput: toolInput, kind: kind, prompts: prompts)
        let title = interactionTitle(from: json, toolInput: toolInput, kind: kind)
        let options = interactionOptions(from: json, toolInput: toolInput, kind: kind, prompts: prompts)
        let allowsFreeText = prompts.contains(where: \.allowsFreeText) || boolValue(
            in: toolInput,
            keys: ["allows_free_text", "allowsFreeText", "free_text"]
        )

        var transportContext = flattenedMetadata(from: json)
        transportContext["source"] = AgentEventSource.codexHook.rawValue
        transportContext["hook_event_name"] = hookEventName
        transportContext["session_id"] = rawSessionID
        transportContext["cwd"] = cwd
        transportContext["request_kind"] = kind.rawValue
        if let toolName, !toolName.isEmpty {
            transportContext["tool_name"] = toolName
        }

        if let ttyPath = context.ttyPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !ttyPath.isEmpty {
            transportContext["_tty"] = ttyPath
        }

        return PendingInteraction(
            id: interactionID(sessionID: rawSessionID, hookEventName: hookEventName, kind: kind),
            sessionID: sessionID,
            tool: .codex,
            kind: kind,
            title: title,
            message: message,
            options: options,
            prompts: prompts,
            allowsFreeText: allowsFreeText,
            requestedAt: requestedAt,
            transportContext: transportContext
        )
    }

    private static func interactionKind(from json: [String: Any]) -> InteractionKind? {
        let hookEventName = firstString(
            in: json,
            keys: ["hook_event_name", "hookEventName", "event_name", "eventName"]
        )?.lowercased() ?? ""
        let toolName = firstString(in: json, keys: ["tool_name", "toolName", "tool", "name"])?.lowercased()
        let explicitKind = firstString(in: json, keys: ["request_kind", "requestKind"])?.lowercased()

        if explicitKind == InteractionKind.planReview.rawValue.lowercased() ||
            hookEventName.contains("planreview") ||
            hookEventName.contains("plan_review") ||
            toolName == "planreview" {
            return .planReview
        }

        if toolName == "askuserquestion" || hookEventName.contains("question") {
            return .question
        }

        if hookEventName.contains("permission") {
            return .permission
        }

        return nil
    }

    private static func interactionTitle(
        from json: [String: Any],
        toolInput: [String: Any]?,
        kind: InteractionKind
    ) -> String? {
        if let title = firstString(in: json, keys: ["title", "header", "thread_name"]) {
            return title
        }

        if let title = firstString(in: toolInput, keys: ["title", "header"]) {
            return title
        }

        switch kind {
        case .permission:
            return "需要权限确认"
        case .question:
            return "需要用户回答"
        case .planReview:
            return "计划审查"
        }
    }

    private static func interactionMessage(
        from json: [String: Any],
        toolInput: [String: Any]?,
        kind: InteractionKind,
        prompts: [InteractionPrompt]
    ) -> String {
        if let message = firstString(in: json, keys: ["message", "prompt", "question", "description"]) {
            return message
        }

        if let message = firstString(in: toolInput, keys: ["question", "message", "prompt", "description"]) {
            return message
        }

        if kind == .permission,
           let toolName = firstString(in: json, keys: ["tool_name", "toolName", "tool", "name"]) {
            if let command = firstString(in: toolInput, keys: ["command", "cmd"]) {
                return "\(toolName): \(command)"
            }
            return toolName
        }

        if prompts.count == 1 {
            return prompts[0].title
        }

        switch kind {
        case .permission:
            return "需要权限确认"
        case .question:
            return "请回答以下问题"
        case .planReview:
            return "是否继续按当前计划执行？"
        }
    }

    private static func interactionOptions(
        from json: [String: Any],
        toolInput: [String: Any]?,
        kind: InteractionKind,
        prompts: [InteractionPrompt]
    ) -> [InteractionOption] {
        if kind == .question, prompts.count == 1, !prompts[0].options.isEmpty {
            return prompts[0].options
        }

        if let options = options(from: json["options"]) {
            return options
        }

        if let options = options(from: toolInput?["options"]) {
            return options
        }

        return []
    }

    private static func prompts(
        from json: [String: Any],
        toolInput: [String: Any]?,
        kind: InteractionKind
    ) -> [InteractionPrompt] {
        switch kind {
        case .permission:
            return []
        case .question:
            if let questions = firstArray(in: toolInput, keys: ["questions", "prompts"]) {
                let parsed = questions.enumerated().compactMap { index, item in
                    prompt(from: item, fallbackIndex: index + 1)
                }
                if !parsed.isEmpty {
                    return parsed
                }
            }

            let options = options(from: toolInput?["options"]) ?? options(from: json["options"]) ?? []
            let fallbackTitle = firstString(in: toolInput, keys: ["title", "question", "prompt"]) ??
                firstString(in: json, keys: ["title", "message", "question"]) ??
                "问题"
            return [
                InteractionPrompt(
                    id: firstString(in: toolInput, keys: ["header", "id"]) ?? "answer_1",
                    title: fallbackTitle,
                    options: options,
                    allowsFreeText: boolValue(
                        in: toolInput,
                        keys: ["allows_free_text", "allowsFreeText", "free_text"]
                    ),
                    allowsMultipleSelection: boolValue(
                        in: toolInput,
                        keys: ["allows_multiple_selection", "allowsMultipleSelection", "allow_multiple"]
                    )
                )
            ]
        case .planReview:
            return [
                InteractionPrompt(
                    id: "review",
                    title: "补充意见",
                    allowsFreeText: true
                )
            ]
        }
    }

    private static func prompt(from value: Any, fallbackIndex: Int) -> InteractionPrompt? {
        guard let dictionary = value as? [String: Any] else { return nil }
        let id = firstString(in: dictionary, keys: ["id", "header", "key", "name"]) ?? "answer_\(fallbackIndex)"
        let title = firstString(in: dictionary, keys: ["title", "question", "prompt", "label", "header"]) ?? id
        let metadata = compactMetadata(
            placeholder: firstString(in: dictionary, keys: ["placeholder", "description", "detail"])
        )

        return InteractionPrompt(
            id: id,
            title: title,
            options: options(from: dictionary["options"]) ?? [],
            allowsFreeText: boolValue(
                in: dictionary,
                keys: ["allows_free_text", "allowsFreeText", "free_text"]
            ),
            allowsMultipleSelection: boolValue(
                in: dictionary,
                keys: ["allows_multiple_selection", "allowsMultipleSelection", "allow_multiple"]
            ),
            metadata: metadata
        )
    }

    private static func options(from value: Any?) -> [InteractionOption]? {
        guard let value else { return nil }
        if let strings = value as? [String] {
            return strings.map { InteractionOption(id: $0, label: $0) }
        }

        guard let array = value as? [Any] else { return nil }
        return array.compactMap { item in
            if let string = item as? String {
                return InteractionOption(id: string, label: string)
            }
            guard let dictionary = item as? [String: Any] else { return nil }
            let id = firstString(in: dictionary, keys: ["id", "value", "key", "name"])
            let label = firstString(in: dictionary, keys: ["label", "title", "name", "value"])
            guard let resolvedID = id ?? label, let resolvedLabel = label ?? id else {
                return nil
            }
            return InteractionOption(
                id: resolvedID,
                label: resolvedLabel,
                detail: firstString(in: dictionary, keys: ["detail", "description"])
            )
        }
    }

    private static func decisionPayload(
        for interaction: PendingInteraction,
        decision: InteractionDecision?
    ) -> [String: Any]? {
        guard let decision else { return nil }

        switch interaction.kind {
        case .permission, .planReview:
            var payload: [String: Any] = [
                "behavior": normalizedBehavior(for: interaction, decision: decision),
            ]
            if let comment = normalizedComment(from: decision) {
                payload["updatedInput"] = ["comment": comment]
            }
            return payload
        case .question:
            let behavior = normalizedBehavior(for: interaction, decision: decision)
            var payload: [String: Any] = ["behavior": behavior]
            if behavior == "allow",
               let answers = answers(for: interaction, decision: decision),
               !answers.isEmpty {
                payload["updatedInput"] = ["answers": answers]
            }
            return payload
        }
    }

    private static func normalizedBehavior(
        for interaction: PendingInteraction,
        decision: InteractionDecision
    ) -> String {
        if let optionID = decision.optionID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           ["deny", "reject", "decline", "no"].contains(optionID) {
            return "deny"
        }

        switch decision.behavior {
        case .deny:
            return "deny"
        case .allow:
            return "allow"
        case .select, .text:
            return interaction.kind == .question ? "allow" : "allow"
        }
    }

    private static func answers(
        for interaction: PendingInteraction,
        decision: InteractionDecision
    ) -> [String: String]? {
        if let explicit = explicitAnswers(from: decision.metadata), !explicit.isEmpty {
            return explicit
        }

        let prompts = interaction.prompts
        guard !prompts.isEmpty else {
            guard let single = singleAnswerValue(for: interaction, decision: decision) else {
                return nil
            }
            return ["answer_1": single]
        }

        let answerKeys = stableAnswerKeys(for: prompts)
        if prompts.count == 1,
           let value = singleAnswerValue(for: interaction, decision: decision) {
            return [answerKeys[0]: value]
        }

        return nil
    }

    private static func explicitAnswers(from metadata: [String: String]) -> [String: String]? {
        var answers: [String: String] = [:]
        for (key, value) in metadata {
            guard key.hasPrefix("answer.") else { continue }
            let answerKey = String(key.dropFirst("answer.".count))
            let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !answerKey.isEmpty, !trimmedValue.isEmpty {
                answers[answerKey] = trimmedValue
            }
        }

        return answers.isEmpty ? nil : answers
    }

    private static func singleAnswerValue(
        for interaction: PendingInteraction,
        decision: InteractionDecision
    ) -> String? {
        if let text = decision.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return text
        }

        if let selectedValues = decision.metadata["selected_values"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !selectedValues.isEmpty {
            return selectedValues
        }

        if let optionID = decision.optionID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !optionID.isEmpty {
            let options = interaction.prompts.first?.options ?? interaction.options
            if let option = options.first(where: { $0.id == optionID }) {
                return option.label
            }
            return optionID
        }

        if let comment = normalizedComment(from: decision) {
            return comment
        }

        return nil
    }

    private static func stableAnswerKeys(for prompts: [InteractionPrompt]) -> [String] {
        var counts: [String: Int] = [:]

        return prompts.enumerated().map { index, prompt in
            let raw = prompt.id.trimmingCharacters(in: .whitespacesAndNewlines)
            let base: String
            if raw.isEmpty {
                base = "answer_\(index + 1)"
            } else {
                base = raw.replacingOccurrences(
                    of: "\\s+",
                    with: "_",
                    options: .regularExpression
                )
            }

            let nextCount = (counts[base] ?? 0) + 1
            counts[base] = nextCount
            if nextCount == 1 {
                return base
            }
            return "\(base)_\(nextCount)"
        }
    }

    private static func normalizedComment(from decision: InteractionDecision) -> String? {
        for key in ["comment", "review_comment", "reason"] {
            if let value = decision.metadata[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }

        if let text = decision.text?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return text
        }

        return nil
    }

    private static func interactionID(
        sessionID: String,
        hookEventName: String,
        kind: InteractionKind
    ) -> String {
        let suffix = hookEventName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
        return "codex-\(sessionID)-\(kind.rawValue)-\(suffix)-\(UUID().uuidString)"
    }

    private static func compositeSessionID(from rawSessionID: String) -> String {
        if rawSessionID.hasPrefix("plugin-") {
            return rawSessionID
        }
        return "plugin-\(AgentEventSource.codexHook.rawValue)-\(rawSessionID)"
    }

    private static func defaultHookEventName(for interaction: PendingInteraction) -> String {
        interaction.transportContext["hook_event_name"] ?? defaultHookEventName(for: interaction.kind)
    }

    private static func defaultHookEventName(for kind: InteractionKind) -> String {
        switch kind {
        case .permission, .question:
            return "PermissionRequest"
        case .planReview:
            return "PlanReview"
        }
    }

    private static func firstString(in json: [String: Any]?, keys: [String]) -> String? {
        guard let json else { return nil }
        for key in keys {
            if let value = normalizedString(json[key]) {
                return value
            }
        }
        return nil
    }

    private static func firstDictionary(in json: [String: Any], keys: [String]) -> [String: Any]? {
        for key in keys {
            if let dictionary = json[key] as? [String: Any] {
                return dictionary
            }
        }
        return nil
    }

    private static func firstArray(in json: [String: Any]?, keys: [String]) -> [Any]? {
        guard let json else { return nil }
        for key in keys {
            if let array = json[key] as? [Any] {
                return array
            }
        }
        return nil
    }

    private static func boolValue(in json: [String: Any]?, keys: [String]) -> Bool {
        guard let json else { return false }
        for key in keys {
            if let bool = json[key] as? Bool {
                return bool
            }
            if let string = normalizedString(json[key])?.lowercased() {
                if ["true", "yes", "1"].contains(string) {
                    return true
                }
                if ["false", "no", "0"].contains(string) {
                    return false
                }
            }
        }
        return false
    }

    private static func normalizedString(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private static func flattenedMetadata(from json: [String: Any]) -> [String: String] {
        var metadata: [String: String] = [:]
        for (key, value) in json {
            switch value {
            case let string as String:
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    metadata[key] = trimmed
                }
            case let number as NSNumber:
                metadata[key] = number.stringValue
            case let dictionary as [String: Any]:
                for (nestedKey, nestedValue) in dictionary {
                    if let nestedString = normalizedString(nestedValue) {
                        metadata["\(key).\(nestedKey)"] = nestedString
                    }
                }
            default:
                continue
            }
        }
        return metadata
    }

    private static func compactMetadata(placeholder: String?) -> [String: String] {
        guard let placeholder, !placeholder.isEmpty else {
            return [:]
        }
        return ["placeholder": placeholder]
    }
}
