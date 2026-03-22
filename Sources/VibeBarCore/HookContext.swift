import Foundation

public struct HookContext: Codable, Sendable {
    public let trigger: HookTrigger
    public let session: SessionSnapshot
    public let previousState: ToolActivityState?
    public let timestamp: Date

    private static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    public init(
        trigger: HookTrigger,
        session: SessionSnapshot,
        previousState: ToolActivityState?,
        timestamp: Date = Date()
    ) {
        self.trigger = trigger
        self.session = session
        self.previousState = previousState
        self.timestamp = timestamp
    }

    public var environment: [String: String] {
        var env: [String: String] = [
            "VIBEBAR_TRIGGER": trigger.rawValue,
            "VIBEBAR_SESSION_ID": session.id,
            "VIBEBAR_TOOL": session.tool.rawValue,
            "VIBEBAR_TOOL_DISPLAY": session.tool.displayName,
            "VIBEBAR_STATUS": session.status.rawValue,
            "VIBEBAR_PID": String(session.pid),
            "VIBEBAR_STARTED_AT": Self.iso8601String(from: session.startedAt),
            "VIBEBAR_UPDATED_AT": Self.iso8601String(from: session.updatedAt),
            "VIBEBAR_EVENT_TIME": Self.iso8601String(from: timestamp),
        ]

        if let previousState {
            env["VIBEBAR_PREV_STATUS"] = previousState.rawValue
        }

        if let cwd = session.cwd, !cwd.isEmpty {
            env["VIBEBAR_CWD"] = cwd
        }

        if let parentPID = session.parentPID {
            env["VIBEBAR_PARENT_PID"] = String(parentPID)
        }

        if let lastOutputAt = session.lastOutputAt {
            env["VIBEBAR_LAST_OUTPUT_AT"] = Self.iso8601String(from: lastOutputAt)
        }

        if let lastInputAt = session.lastInputAt {
            env["VIBEBAR_LAST_INPUT_AT"] = Self.iso8601String(from: lastInputAt)
        }

        return env
    }

    public var jsonPayload: Data? {
        let payload: [String: Any] = [
            "trigger": trigger.rawValue,
            "timestamp": Self.iso8601String(from: timestamp),
            "session": [
                "id": session.id,
                "tool": session.tool.rawValue,
                "tool_display": session.tool.displayName,
                "pid": session.pid,
                "parent_pid": session.parentPID as Any,
                "status": session.status.rawValue,
                "previous_status": previousState?.rawValue as Any,
                "source": session.source.rawValue,
                "started_at": Self.iso8601String(from: session.startedAt),
                "updated_at": Self.iso8601String(from: session.updatedAt),
                "last_output_at": session.lastOutputAt.map { Self.iso8601String(from: $0) } as Any,
                "last_input_at": session.lastInputAt.map { Self.iso8601String(from: $0) } as Any,
                "cwd": session.cwd as Any,
                "command": session.command,
                "notes": session.notes as Any,
            ]
        ]

        return try? JSONSerialization.data(withJSONObject: payload, options: [.withoutEscapingSlashes])
    }

    public var jsonString: String? {
        guard let data = jsonPayload else { return nil }
        return String(data: data, encoding: .utf8)
    }
}