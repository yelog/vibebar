import Foundation

public enum AgentEventSource: String, Codable, Sendable {
    case claudePlugin = "claude-plugin"
    case opencodePlugin = "opencode-plugin"
    case copilotHook = "copilot-hook"
    case unknown

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode(String.self)) ?? ""
        self = AgentEventSource(rawValue: raw) ?? .unknown
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct AgentEvent: Codable, Sendable {
    public var version: Int
    public var source: AgentEventSource
    public var tool: ToolKind
    public var sessionID: String
    public var eventType: String
    public var status: ToolActivityState?
    public var timestamp: Date?
    public var pid: Int32?
    public var parentPID: Int32?
    public var cwd: String?
    public var command: [String]?
    public var notes: String?
    public var metadata: [String: String]

    public init(
        version: Int = 1,
        source: AgentEventSource,
        tool: ToolKind,
        sessionID: String,
        eventType: String,
        status: ToolActivityState? = nil,
        timestamp: Date? = nil,
        pid: Int32? = nil,
        parentPID: Int32? = nil,
        cwd: String? = nil,
        command: [String]? = nil,
        notes: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.version = version
        self.source = source
        self.tool = tool
        self.sessionID = sessionID
        self.eventType = eventType
        self.status = status
        self.timestamp = timestamp
        self.pid = pid
        self.parentPID = parentPID
        self.cwd = cwd
        self.command = command
        self.notes = notes
        self.metadata = metadata
    }

    public var compositeSessionID: String {
        "plugin-\(source.rawValue)-\(sessionID)"
    }

    enum CodingKeys: String, CodingKey {
        case version
        case source
        case tool
        case sessionID = "session_id"
        case eventType = "event_type"
        case status
        case timestamp
        case pid
        case parentPID = "parent_pid"
        case cwd
        case command
        case notes
        case metadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        source = try container.decode(AgentEventSource.self, forKey: .source)
        tool = try container.decode(ToolKind.self, forKey: .tool)
        sessionID = try container.decode(String.self, forKey: .sessionID)
        eventType = try container.decode(String.self, forKey: .eventType)
        status = try container.decodeIfPresent(ToolActivityState.self, forKey: .status)
        timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp)
        pid = try container.decodeIfPresent(Int32.self, forKey: .pid)
        parentPID = try container.decodeIfPresent(Int32.self, forKey: .parentPID)
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        command = try container.decodeIfPresent([String].self, forKey: .command)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(source, forKey: .source)
        try container.encode(tool, forKey: .tool)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(eventType, forKey: .eventType)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(pid, forKey: .pid)
        try container.encodeIfPresent(parentPID, forKey: .parentPID)
        try container.encodeIfPresent(cwd, forKey: .cwd)
        try container.encodeIfPresent(command, forKey: .command)
        try container.encodeIfPresent(notes, forKey: .notes)
        if !metadata.isEmpty {
            try container.encode(metadata, forKey: .metadata)
        }
    }
}
