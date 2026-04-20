import Foundation

public struct CodexHookBridgeContext: Sendable {
    public var environment: [String: String]
    public var currentDirectory: String
    public var processID: Int32
    public var parentPID: Int32
    public var ttyPath: String?

    public init(
        environment: [String: String],
        currentDirectory: String,
        processID: Int32,
        parentPID: Int32,
        ttyPath: String? = nil
    ) {
        self.environment = environment
        self.currentDirectory = currentDirectory
        self.processID = processID
        self.parentPID = parentPID
        self.ttyPath = ttyPath
    }
}

public enum CodexHookEventBridge {
    public static func makeEvent(from data: Data, context: CodexHookBridgeContext) -> AgentEvent? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return makeEvent(from: json, context: context)
    }

    static func makeEvent(from json: [String: Any], context: CodexHookBridgeContext) -> AgentEvent? {
        guard let sessionID = firstString(in: json, keys: ["session_id", "sessionId"]), !sessionID.isEmpty else {
            return nil
        }

        let hookEventName = firstString(in: json, keys: ["hook_event_name", "hookEventName", "event_name", "eventName"])
            ?? "unknown"
        let eventType = normalizedEventType(from: hookEventName)
        let status = status(for: eventType)
        let pid = context.parentPID > 0 ? context.parentPID : context.processID

        var metadata = flattenedMetadata(from: json)
        metadata["hook_event_name"] = hookEventName
        metadata["session_id"] = sessionID
        metadata["cwd"] = firstString(in: json, keys: ["cwd"]) ?? context.currentDirectory

        if let prompt = firstString(in: json, keys: ["prompt", "user_prompt", "message", "input", "content"]) {
            metadata["prompt"] = prompt
            metadata["first_user_message"] = metadata["first_user_message"] ?? prompt
            metadata["last_user_message"] = metadata["last_user_message"] ?? prompt
        }

        if let toolName = firstString(in: json, keys: ["tool_name", "toolName", "tool", "name"]) {
            metadata["tool_name"] = toolName
        }

        if let threadName = firstString(in: json, keys: ["thread_name", "session_title", "title"]) {
            metadata["thread_name"] = threadName
        }

        if let ttyPath = context.ttyPath?.trimmingCharacters(in: .whitespacesAndNewlines), !ttyPath.isEmpty {
            metadata["_tty"] = ttyPath
        }

        for key in environmentPassthroughKeys {
            if let value = context.environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                metadata[key] = value
            }
        }

        let sessionMetadata = CodexSessionMetadataStore(environment: context.environment).metadata(for: sessionID)
        if metadata["thread_name"] == nil,
           let title = sessionMetadata?.title {
            metadata["thread_name"] = title
            metadata["title"] = metadata["title"] ?? title
            metadata["session_title"] = metadata["session_title"] ?? title
        }
        if metadata["first_user_message"] == nil,
           let firstUserMessage = sessionMetadata?.firstUserMessage {
            metadata["first_user_message"] = firstUserMessage
        }
        if metadata["last_user_message"] == nil,
           let lastUserMessage = sessionMetadata?.firstUserMessage {
            metadata["last_user_message"] = lastUserMessage
        }
        if let rolloutPath = sessionMetadata?.rolloutPath,
           metadata["transcript_path"] == nil {
            metadata["transcript_path"] = rolloutPath
        }
        if let source = sessionMetadata?.source,
           metadata["source"] == nil {
            metadata["source"] = source
        }
        if let cwd = sessionMetadata?.cwd,
           let existingCwd = metadata["cwd"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           existingCwd.isEmpty {
            metadata["cwd"] = cwd
        }

        return AgentEvent(
            source: .codexHook,
            tool: .codex,
            sessionID: sessionID,
            eventType: eventType,
            status: status,
            timestamp: Date(),
            pid: pid,
            parentPID: context.processID,
            cwd: metadata["cwd"],
            command: [ToolKind.codex.executable],
            notes: "codex-hook:\(hookEventName)",
            metadata: metadata
        )
    }

    private static let environmentPassthroughKeys: [String] = [
        "TERM_PROGRAM",
        "__CFBundleIdentifier",
        "KITTY_WINDOW_ID",
        "KITTY_LISTEN_ON",
        "WEZTERM_PANE",
        "WEZTERM_UNIX_SOCKET",
        "ITERM_SESSION_ID",
        "TERM_SESSION_ID",
        "TMUX",
        "TMUX_PANE",
        "ZELLIJ",
        "ZELLIJ_SESSION_NAME",
        "CODEX_INTERNAL_ORIGINATOR_OVERRIDE",
        "CODEX_THREAD_ID",
        "CODEX_SHELL",
    ]

    private static func firstString(in json: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = normalizedString(json[key]) {
                return value
            }
        }
        return nil
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

    private static func normalizedEventType(from hookEventName: String) -> String {
        switch hookEventName.lowercased() {
        case "sessionstart", "session_start", "session_started":
            return "session_start"
        case "sessionend", "session_end", "session_ended":
            return "session_end"
        case "userpromptsubmit", "user_prompt_submit":
            return "user_prompt_submit"
        case "pretooluse", "pre_tool_use":
            return "pre_tool_use"
        case "posttooluse", "post_tool_use":
            return "post_tool_use"
        case "stop":
            return "stop"
        default:
            return snakeCased(hookEventName)
        }
    }

    private static func status(for eventType: String) -> ToolActivityState? {
        switch eventType {
        case "session_end":
            return nil
        case "stop":
            return .idle
        case "session_start", "user_prompt_submit", "pre_tool_use", "post_tool_use":
            return .running
        default:
            if eventType.contains("permission") || eventType.contains("question") {
                return .awaitingInput
            }
            return .running
        }
    }

    private static func snakeCased(_ value: String) -> String {
        guard !value.isEmpty else { return value }

        var result = ""
        result.reserveCapacity(value.count + 4)
        for scalar in value.unicodeScalars {
            let character = Character(scalar)
            if character.isUppercase {
                if !result.isEmpty {
                    result.append("_")
                }
                result.append(String(character).lowercased())
            } else if character == "-" || character == " " {
                result.append("_")
            } else {
                result.append(String(character).lowercased())
            }
        }
        return result
    }
}
