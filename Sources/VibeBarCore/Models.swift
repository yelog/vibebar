import Foundation

public enum ToolKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case claudeCode = "claude-code"
    case codex = "codex"
    case opencode = "opencode"
    case aider = "aider"
    case gemini = "gemini"
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
        case .gemini:
            return "Gemini CLI"
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
        case .gemini:
            return "gemini"
        case .githubCopilot:
            return "copilot"
        }
    }

    /// Icon resource name for the tool
    public var iconResourceName: String {
        switch self {
        case .claudeCode:
            return "claudeCode"
        case .codex:
            return "codex"
        case .opencode:
            return "opencode"
        case .aider:
            return "aider_final"
        case .gemini:
            return "gemini"
        case .githubCopilot:
            return "github"
        }
    }

    /// SF Symbol fallback icon name for the tool
    public var iconName: String {
        switch self {
        case .claudeCode:
            return "sparkles"
        case .codex:
            return "chevron.left.forwardslash.chevron.right"
        case .opencode:
            return "network"
        case .aider:
            return "person.2.fill"
        case .gemini:
            return "diamond.fill"
        case .githubCopilot:
            return "airplane.fill"
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
        case "gemini", "gemini-cli", "geminicli":
            return .gemini
        case "copilot", "github-copilot", "githubcopilot", "github_copilot":
            return .githubCopilot
        default:
            return nil
        }
    }

    public static func detect(command: String, args: String) -> ToolKind? {
        let commandName = DetectorSupport.pathBasename(command).lowercased()

        // Direct match on binary name
        if commandName == "claude" { return .claudeCode }
        if commandName == "codex" { return .codex }
        if commandName == "opencode" { return .opencode }
        if commandName == "aider" { return .aider }
        if commandName == "gemini" { return .gemini }
        if commandName == "copilot" { return .githubCopilot }

        // For runtime-based invocations (e.g. `/usr/bin/env claude`, `node .../claude`),
        // check the basename of the first two arg tokens only.
        let tokens = args.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        for token in tokens.prefix(2) {
            let name = DetectorSupport.pathBasename(String(token)).lowercased()
            if name == "claude" { return .claudeCode }
            if name == "codex" { return .codex }
            if name == "opencode" { return .opencode }
            if name == "aider" { return .aider }
            if name == "gemini" { return .gemini }
            if name == "copilot" { return .githubCopilot }
        }

        return nil
    }
}

public enum SessionSource: String, Codable, Sendable {
    case wrapper
    case processScan = "process_scan"
    case plugin
    case transcriptFile = "transcript_file"
    case sessionFile = "session_file"
}

public enum TerminalClientKind: String, Codable, CaseIterable, Sendable {
    case kitty
    case ghostty
    case wezterm
    case iterm
    case warp
    case terminal
    case unknown
}

public enum SessionManagerKind: String, Codable, CaseIterable, Sendable {
    case none
    case tmux
    case zellij
    case unknown
}

public enum SessionOriginKind: String, Codable, CaseIterable, Sendable {
    case cli
    case desktop
    case unknown
}

public enum SessionTitleSource: String, Codable, CaseIterable, Sendable {
    case explicit
    case derived
}

public enum InteractionKind: String, Codable, CaseIterable, Sendable {
    case permission
    case question
    case planReview = "plan_review"
}

public struct InteractionOption: Codable, Identifiable, Sendable, Equatable {
    public var id: String
    public var label: String
    public var detail: String?

    public init(
        id: String,
        label: String,
        detail: String? = nil
    ) {
        self.id = id
        self.label = label
        self.detail = detail
    }
}

public enum InteractionDecisionBehavior: String, Codable, CaseIterable, Sendable {
    case allow
    case deny
    case select
    case text
}

public struct InteractionDecision: Codable, Sendable, Equatable {
    public var behavior: InteractionDecisionBehavior
    public var optionID: String?
    public var text: String?
    public var metadata: [String: String]

    public init(
        behavior: InteractionDecisionBehavior,
        optionID: String? = nil,
        text: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.behavior = behavior
        self.optionID = optionID
        self.text = text
        self.metadata = metadata
    }
}

public struct PendingInteraction: Codable, Identifiable, Sendable, Equatable {
    public var id: String
    public var sessionID: String
    public var tool: ToolKind
    public var kind: InteractionKind
    public var title: String?
    public var message: String
    public var options: [InteractionOption]
    public var allowsFreeText: Bool
    public var requestedAt: Date
    public var expiresAt: Date?
    public var transportContext: [String: String]

    public init(
        id: String,
        sessionID: String,
        tool: ToolKind,
        kind: InteractionKind,
        title: String? = nil,
        message: String,
        options: [InteractionOption] = [],
        allowsFreeText: Bool = false,
        requestedAt: Date,
        expiresAt: Date? = nil,
        transportContext: [String: String] = [:]
    ) {
        self.id = id
        self.sessionID = sessionID
        self.tool = tool
        self.kind = kind
        self.title = title
        self.message = message
        self.options = options
        self.allowsFreeText = allowsFreeText
        self.requestedAt = requestedAt
        self.expiresAt = expiresAt
        self.transportContext = transportContext
    }

    enum CodingKeys: String, CodingKey {
        case id
        case sessionID = "session_id"
        case tool
        case kind
        case title
        case message
        case options
        case allowsFreeText = "allows_free_text"
        case requestedAt = "requested_at"
        case expiresAt = "expires_at"
        case transportContext = "transport_context"
    }
}

public struct TerminalContext: Codable, Sendable, Equatable {
    public var clientKind: TerminalClientKind
    public var bundleIdentifier: String?
    public var clientControlAddress: String?
    public var tty: String?
    public var clientSessionID: String?
    public var clientWindowID: String?
    public var clientTabID: String?
    public var clientNativeSessionID: String?
    public var clientTabTitle: String?
    public var clientTabIndex: Int?
    public var sessionManagerKind: SessionManagerKind
    public var sessionManagerSessionID: String?
    public var sessionManagerPaneID: String?
    public var sessionManagerTabName: String?
    public var sessionManagerTabIndex: Int?
    public var origin: SessionOriginKind

    public init(
        clientKind: TerminalClientKind = .unknown,
        bundleIdentifier: String? = nil,
        clientControlAddress: String? = nil,
        tty: String? = nil,
        clientSessionID: String? = nil,
        clientWindowID: String? = nil,
        clientTabID: String? = nil,
        clientNativeSessionID: String? = nil,
        clientTabTitle: String? = nil,
        clientTabIndex: Int? = nil,
        sessionManagerKind: SessionManagerKind = .unknown,
        sessionManagerSessionID: String? = nil,
        sessionManagerPaneID: String? = nil,
        sessionManagerTabName: String? = nil,
        sessionManagerTabIndex: Int? = nil,
        origin: SessionOriginKind = .unknown
    ) {
        self.clientKind = clientKind
        self.bundleIdentifier = bundleIdentifier
        self.clientControlAddress = clientControlAddress
        self.tty = tty
        self.clientSessionID = clientSessionID
        self.clientWindowID = clientWindowID
        self.clientTabID = clientTabID
        self.clientNativeSessionID = clientNativeSessionID
        self.clientTabTitle = clientTabTitle
        self.clientTabIndex = clientTabIndex
        self.sessionManagerKind = sessionManagerKind
        self.sessionManagerSessionID = sessionManagerSessionID
        self.sessionManagerPaneID = sessionManagerPaneID
        self.sessionManagerTabName = sessionManagerTabName
        self.sessionManagerTabIndex = sessionManagerTabIndex
        self.origin = origin
    }
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
    public var statusSince: Date?
    public var idleSince: Date?
    public var lastOutputAt: Date?
    public var lastInputAt: Date?
    public var cwd: String?
    public var command: [String]
    public var notes: String?
    public var title: String?
    public var titleSource: SessionTitleSource?
    public var currentTask: String?
    public var pendingInteractionID: String?
    public var terminalContext: TerminalContext?

    public init(
        id: String,
        tool: ToolKind,
        pid: Int32,
        parentPID: Int32? = nil,
        status: ToolActivityState,
        source: SessionSource,
        startedAt: Date,
        updatedAt: Date,
        statusSince: Date? = nil,
        idleSince: Date? = nil,
        lastOutputAt: Date? = nil,
        lastInputAt: Date? = nil,
        cwd: String? = nil,
        command: [String],
        notes: String? = nil,
        title: String? = nil,
        titleSource: SessionTitleSource? = nil,
        currentTask: String? = nil,
        pendingInteractionID: String? = nil,
        terminalContext: TerminalContext? = nil
    ) {
        self.id = id
        self.tool = tool
        self.pid = pid
        self.parentPID = parentPID
        self.status = status
        self.source = source
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.statusSince = statusSince
        self.idleSince = idleSince
        self.lastOutputAt = lastOutputAt
        self.lastInputAt = lastInputAt
        self.cwd = cwd
        self.command = command
        self.notes = notes
        self.title = title
        self.titleSource = titleSource
        self.currentTask = currentTask
        self.pendingInteractionID = pendingInteractionID
        self.terminalContext = terminalContext
    }

    public var currentStatusSince: Date {
        if let statusSince {
            return statusSince
        }
        switch status {
        case .idle:
            return idleSince ?? startedAt
        case .awaitingInput:
            return lastInputAt ?? startedAt
        case .running, .unknown:
            return startedAt
        }
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

public struct InteractionFileEnvelope: Codable, Sendable {
    public var version: Int
    public var interaction: PendingInteraction

    public init(version: Int = 1, interaction: PendingInteraction) {
        self.version = version
        self.interaction = interaction
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
