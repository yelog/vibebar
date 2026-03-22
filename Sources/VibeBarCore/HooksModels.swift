import Foundation

public enum HookTrigger: String, Codable, CaseIterable, Sendable, Identifiable {
    case sessionStarted = "session_started"
    case sessionEnded = "session_ended"
    case stateChanged = "state_changed"
    case runningToIdle = "running_to_idle"
    case runningToAwaiting = "running_to_awaiting"
    case idleToRunning = "idle_to_running"

    public var id: String { rawValue }

    @MainActor public var displayName: String {
        switch self {
        case .sessionStarted:
            return L10n.shared.string(.hookTriggerSessionStarted)
        case .sessionEnded:
            return L10n.shared.string(.hookTriggerSessionEnded)
        case .stateChanged:
            return L10n.shared.string(.hookTriggerStateChanged)
        case .runningToIdle:
            return L10n.shared.string(.hookTriggerRunningToIdle)
        case .runningToAwaiting:
            return L10n.shared.string(.hookTriggerRunningToAwaiting)
        case .idleToRunning:
            return L10n.shared.string(.hookTriggerIdleToRunning)
        }
    }

    public var description: String {
        switch self {
        case .sessionStarted: return "New session detected"
        case .sessionEnded: return "Session ended (process terminated)"
        case .stateChanged: return "Any state change"
        case .runningToIdle: return "Task completed (running → idle)"
        case .runningToAwaiting: return "Waiting for input (running → awaiting)"
        case .idleToRunning: return "Resumed (idle → running)"
        }
    }
}

public enum HookActionType: String, Codable, CaseIterable, Sendable, Identifiable {
    case shell
    case webhook

    public var id: String { rawValue }

    @MainActor public var displayName: String {
        switch self {
        case .shell:
            return L10n.shared.string(.hookActionShell)
        case .webhook:
            return L10n.shared.string(.hookActionWebhook)
        }
    }
}

public struct HookAction: Codable, Sendable {
    public var type: HookActionType
    public var shellCommand: String?
    public var webhookURL: String?
    public var webhookMethod: String?
    public var webhookHeaders: [String: String]?
    public var timeout: TimeInterval

    public init(
        type: HookActionType,
        shellCommand: String? = nil,
        webhookURL: String? = nil,
        webhookMethod: String? = nil,
        webhookHeaders: [String: String]? = nil,
        timeout: TimeInterval = 30.0
    ) {
        self.type = type
        self.shellCommand = shellCommand
        self.webhookURL = webhookURL
        self.webhookMethod = webhookMethod
        self.webhookHeaders = webhookHeaders
        self.timeout = timeout
    }

    public static func shell(command: String, timeout: TimeInterval = 30.0) -> HookAction {
        HookAction(type: .shell, shellCommand: command, timeout: timeout)
    }

    public static func webhook(
        url: String,
        method: String = "POST",
        headers: [String: String]? = nil,
        timeout: TimeInterval = 10.0
    ) -> HookAction {
        HookAction(type: .webhook, webhookURL: url, webhookMethod: method, webhookHeaders: headers, timeout: timeout)
    }
}

public struct HookConfig: Codable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var isEnabled: Bool
    public var triggers: Set<HookTrigger>
    public var tools: Set<ToolKind>?
    public var action: HookAction
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        name: String,
        isEnabled: Bool = true,
        triggers: Set<HookTrigger>,
        tools: Set<ToolKind>? = nil,
        action: HookAction
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.triggers = triggers
        self.tools = tools
        self.action = action
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    public mutating func touch() {
        updatedAt = Date()
    }
}

public struct HooksConfig: Codable, Sendable {
    public var version: Int
    public var hooks: [HookConfig]

    public init(version: Int = 1, hooks: [HookConfig] = []) {
        self.version = version
        self.hooks = hooks
    }

    public static var `default`: HooksConfig {
        HooksConfig(version: 1, hooks: [])
    }
}