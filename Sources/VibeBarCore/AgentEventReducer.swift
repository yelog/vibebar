import Foundation

public struct AgentEventReduction: Sendable, Equatable {
    public var shouldDeleteSession: Bool
    public var status: ToolActivityState?

    public init(shouldDeleteSession: Bool, status: ToolActivityState?) {
        self.shouldDeleteSession = shouldDeleteSession
        self.status = status
    }
}

public enum AgentEventReducer {
    public static func reduce(event: AgentEvent, previous: SessionSnapshot?) -> AgentEventReduction {
        let normalizedType = normalize(event.eventType)
        if isSessionEndEvent(normalizedType) {
            return AgentEventReduction(shouldDeleteSession: true, status: nil)
        }

        return AgentEventReduction(
            shouldDeleteSession: false,
            status: resolveStatus(event: event, previous: previous, normalizedType: normalizedType)
        )
    }

    public static func normalize(_ rawType: String) -> String {
        rawType
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "_")
            .lowercased()
    }

    private static func isSessionEndEvent(_ normalizedType: String) -> Bool {
        switch normalizedType {
        case "session_end", "sessionended", "session_ended", "end", "exit", "logout":
            return true
        default:
            return false
        }
    }

    private static func resolveStatus(
        event: AgentEvent,
        previous: SessionSnapshot?,
        normalizedType: String
    ) -> ToolActivityState {
        if let status = event.status {
            return status
        }

        switch normalizedType {
        case "afteragent", "after_agent":
            return .awaitingInput
        case "sessionstart", "session_start", "session_started", "beforeagent", "before_agent",
            "userpromptsubmit", "user_prompt_submit", "pretooluse", "pre_tool_use",
            "posttooluse", "post_tool_use":
            return .running
        case "stop":
            return .idle
        case "notification":
            let notificationType = event.metadata["notification_type"]?.lowercased() ?? ""
            if notificationType.contains("permission") {
                return .awaitingInput
            }
        default:
            break
        }

        if normalizedType.contains("permission") || normalizedType.contains("await") || normalizedType.contains("prompt") || normalizedType.contains("approval") || normalizedType.contains("question") {
            return .awaitingInput
        }
        if normalizedType.contains("idle") {
            return .idle
        }
        if normalizedType.contains("run") || normalizedType.contains("start") || normalizedType.contains("tool") || normalizedType.contains("progress") {
            return .running
        }
        return previous?.status ?? .running
    }
}
