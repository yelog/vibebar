import Foundation

public enum ToolKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case claudeCode = "claude-code"
    case codex = "codex"
    case opencode = "opencode"
    case aider = "aider"
    case githubCopilot = "github-copilot"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claudeCode:
            return "Claude Code"
        case .codex:
            return "Codex"
        case .opencode:
            return "OpenCode"
        case .aider:
            return "Aider"
        case .githubCopilot:
            return "GitHub Copilot"
        }
    }

    public var executable: String {
        switch self {
        case .claudeCode:
            return "claude"
        case .codex:
            return "codex"
        case .opencode:
            return "opencode"
        case .aider:
            return "aider"
        case .githubCopilot:
            return "copilot"
        }
    }

    public static func fromCLIArgument(_ value: String) -> ToolKind? {
        switch value.lowercased() {
        case "claude", "claude-code", "claudecode":
            return .claudeCode
        case "codex":
            return .codex
        case "opencode", "open-code", "open_code":
            return .opencode
        case "aider":
            return .aider
        case "copilot", "github-copilot", "githubcopilot", "github_copilot":
            return .githubCopilot
        default:
            return nil
        }
    }

    public static func detect(command: String, args: String) -> ToolKind? {
        let commandName = URL(fileURLWithPath: command).lastPathComponent.lowercased()

        // Direct match on binary name
        if commandName == "claude" { return .claudeCode }
        if commandName == "codex" { return .codex }
        if commandName == "opencode" { return .opencode }
        if commandName == "aider" { return .aider }
        if commandName == "copilot" { return .githubCopilot }

        // For runtime-based invocations (e.g. `/usr/bin/env claude`, `node .../claude`),
        // check the basename of the first two arg tokens only.
        let tokens = args.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        for token in tokens.prefix(2) {
            let name = URL(fileURLWithPath: String(token)).lastPathComponent.lowercased()
            if name == "claude" { return .claudeCode }
            if name == "codex" { return .codex }
            if name == "opencode" { return .opencode }
            if name == "aider" { return .aider }
            if name == "copilot" { return .githubCopilot }
        }

        return nil
    }
}

public enum SessionSource: String, Codable, Sendable {
    case wrapper
    case processScan = "process_scan"
    case plugin
}

public enum ToolActivityState: String, Codable, CaseIterable, Sendable {
    case idle
    case running
    case awaitingInput = "awaiting_input"
    case unknown

    @MainActor public var displayName: String {
        switch self {
        case .idle:
            return L10n.shared.string(.stateIdle)
        case .running:
            return L10n.shared.string(.stateRunning)
        case .awaitingInput:
            return L10n.shared.string(.stateAwaitingInput)
        case .unknown:
            return L10n.shared.string(.stateUnknown)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "idle":
            self = .idle
        case "running":
            self = .running
        case "awaiting_input":
            self = .awaitingInput
        case "completed":
            // Backward compat: completed → idle
            self = .idle
        default:
            self = .unknown
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum ToolOverallState: String, Codable, CaseIterable, Sendable {
    case stopped
    case idle
    case running
    case awaitingInput = "awaiting_input"
    case unknown

    @MainActor public var displayName: String {
        switch self {
        case .stopped:
            return L10n.shared.string(.stateStopped)
        case .idle:
            return L10n.shared.string(.stateIdle)
        case .running:
            return L10n.shared.string(.stateRunning)
        case .awaitingInput:
            return L10n.shared.string(.stateAwaitingInput)
        case .unknown:
            return L10n.shared.string(.stateUnknown)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "stopped":
            self = .stopped
        case "idle", "completed":
            self = .idle
        case "running":
            self = .running
        case "awaiting_input":
            self = .awaitingInput
        default:
            self = .unknown
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct SessionSnapshot: Codable, Identifiable, Sendable {
    public var id: String
    public var tool: ToolKind
    public var pid: Int32
    public var parentPID: Int32?
    public var status: ToolActivityState
    public var source: SessionSource
    public var startedAt: Date
    public var updatedAt: Date
    public var lastOutputAt: Date?
    public var lastInputAt: Date?
    public var cwd: String?
    public var command: [String]
    public var notes: String?

    public init(
        id: String,
        tool: ToolKind,
        pid: Int32,
        parentPID: Int32? = nil,
        status: ToolActivityState,
        source: SessionSource,
        startedAt: Date,
        updatedAt: Date,
        lastOutputAt: Date? = nil,
        lastInputAt: Date? = nil,
        cwd: String? = nil,
        command: [String],
        notes: String? = nil
    ) {
        self.id = id
        self.tool = tool
        self.pid = pid
        self.parentPID = parentPID
        self.status = status
        self.source = source
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.lastOutputAt = lastOutputAt
        self.lastInputAt = lastInputAt
        self.cwd = cwd
        self.command = command
        self.notes = notes
    }
}

public struct SessionFileEnvelope: Codable, Sendable {
    public var version: Int
    public var session: SessionSnapshot

    public init(version: Int = 1, session: SessionSnapshot) {
        self.version = version
        self.session = session
    }
}

public struct ToolSummary: Sendable {
    public var tool: ToolKind
    public var total: Int
    public var counts: [ToolActivityState: Int]
    public var overall: ToolOverallState

    public init(tool: ToolKind, total: Int, counts: [ToolActivityState: Int], overall: ToolOverallState) {
        self.tool = tool
        self.total = total
        self.counts = counts
        self.overall = overall
    }
}

public struct GlobalSummary: Sendable {
    public var total: Int
    public var counts: [ToolActivityState: Int]
    public var byTool: [ToolKind: ToolSummary]
    public var updatedAt: Date

    public init(total: Int, counts: [ToolActivityState: Int], byTool: [ToolKind: ToolSummary], updatedAt: Date) {
        self.total = total
        self.counts = counts
        self.byTool = byTool
        self.updatedAt = updatedAt
    }
}
