import Foundation
import VibeBarCore

enum OpenCodeLegacyPermissionBridge {
    static func canDirectlyReply(_ interaction: PendingInteraction) -> Bool {
        interaction.tool == .opencode &&
            (interaction.kind == .permission || interaction.kind == .question) &&
            interaction.transportContext["opencode_request_id"] != nil
    }

    static func relayDecision(
        for interaction: PendingInteraction,
        userDecision: InteractionDecision
    ) -> InteractionDecision? {
        guard interaction.isLegacyOpenCodePermission else {
            return userDecision
        }

        switch normalizedOptionID(from: userDecision) {
        case "once":
            return InteractionDecision(
                behavior: .allow,
                optionID: "once",
                text: userDecision.text,
                metadata: userDecision.metadata
            )
        case "reject":
            return InteractionDecision(
                behavior: .deny,
                optionID: "reject",
                text: userDecision.text,
                metadata: userDecision.metadata
            )
        case "always":
            return nil
        default:
            return nil
        }
    }

    static func submitDecision(
        interaction: PendingInteraction,
        userDecision: InteractionDecision,
        sessionPID: Int32?
    ) async -> Bool {
        switch interaction.kind {
        case .permission:
            return await submitPermissionDecision(
                interaction: interaction,
                userDecision: userDecision,
                sessionPID: sessionPID
            )
        case .question:
            return await submitQuestionDecision(
                interaction: interaction,
                userDecision: userDecision,
                sessionPID: sessionPID
            )
        case .planReview:
            return false
        }
    }

    private static func submitPermissionDecision(
        interaction: PendingInteraction,
        userDecision: InteractionDecision,
        sessionPID: Int32?
    ) async -> Bool {
        guard let url = await replyURL(
            for: interaction,
            sessionPID: sessionPID
        ) else {
            return false
        }

        let message = normalizedMessage(from: userDecision)
        guard let reply = normalizedOptionID(from: userDecision) else { return false }
        let body = compactJSON(["reply": reply, "message": message])

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 2.0
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            return (200 ..< 300).contains(httpResponse.statusCode)
        } catch {
            return false
        }
    }

    private static func submitQuestionDecision(
        interaction: PendingInteraction,
        userDecision: InteractionDecision,
        sessionPID: Int32?
    ) async -> Bool {
        guard let url = await replyURL(
            for: interaction,
            sessionPID: sessionPID
        ),
              let answer = normalizedQuestionAnswer(
                from: userDecision,
                interaction: interaction
              ) else {
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 2.0
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(
            withJSONObject: ["answers": [[answer]]]
        )

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            return (200 ..< 300).contains(httpResponse.statusCode)
        } catch {
            return false
        }
    }

    private static func replyURL(
        for interaction: PendingInteraction,
        sessionPID: Int32?
    ) async -> URL? {
        guard let requestID = interaction.transportContext["opencode_request_id"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !requestID.isEmpty else {
            return nil
        }

        if let explicitBaseURL = normalizedServerURL(from: interaction) {
            return buildReplyURL(
                baseURL: explicitBaseURL,
                requestID: requestID,
                kind: interaction.kind
            )
        }

        guard let sessionPID, sessionPID > 0,
              let port = await DetectorSupport.findListeningPort(pid: sessionPID),
              let fallbackBaseURL = URL(string: "http://127.0.0.1:\(port)") else {
            return nil
        }

        return buildReplyURL(
            baseURL: fallbackBaseURL,
            requestID: requestID,
            kind: interaction.kind
        )
    }

    private static func normalizedServerURL(from interaction: PendingInteraction) -> URL? {
        guard let raw = interaction.transportContext["server_url"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let url = URL(string: raw) else {
            return nil
        }

        if url.port == 0 || raw.contains(":0") {
            let fallbackPort = ProcessInfo.processInfo.environment["OPENCODE_PORT"]?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let port = (fallbackPort?.isEmpty == false ? fallbackPort : nil) ?? "4096"
            return URL(string: "http://127.0.0.1:\(port)")
        }

        return url
    }

    private static func buildReplyURL(
        baseURL: URL,
        requestID: String,
        kind: InteractionKind
    ) -> URL? {
        let path: String
        switch kind {
        case .permission:
            path = "permission/\(requestID)/reply"
        case .question:
            path = "question/\(requestID)/reply"
        case .planReview:
            return nil
        }

        return URL(string: path, relativeTo: baseURL)?.absoluteURL
    }

    private static func normalizedOptionID(from decision: InteractionDecision) -> String? {
        if let optionID = decision.optionID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
           !optionID.isEmpty {
            return optionID
        }

        switch decision.behavior {
        case .allow:
            return "once"
        case .deny:
            return "reject"
        case .select, .text:
            return nil
        }
    }

    private static func normalizedMessage(from decision: InteractionDecision) -> String? {
        let text = decision.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let text, !text.isEmpty {
            return text
        }

        let reason = decision.metadata["reason"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let reason, !reason.isEmpty {
            return reason
        }

        return nil
    }

    private static func normalizedQuestionAnswer(
        from decision: InteractionDecision,
        interaction: PendingInteraction
    ) -> String? {
        let text = decision.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let text, !text.isEmpty {
            return text
        }

        guard let optionID = decision.optionID?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !optionID.isEmpty else {
            return nil
        }

        return interaction.options.first(where: { $0.id == optionID })?.label
    }

    private static func compactJSON(_ values: [String: String?]) -> [String: String] {
        values.reduce(into: [:]) { partialResult, entry in
            if let value = entry.value {
                partialResult[entry.key] = value
            }
        }
    }
}
