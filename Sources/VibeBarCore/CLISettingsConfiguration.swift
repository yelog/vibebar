import Foundation

// MARK: - Detection Method Preference

/// Represents a detection method that can be enabled/disabled per CLI tool
public enum DetectionMethodPreference: String, Codable, CaseIterable, Sendable, Identifiable {
    case httpAPI = "http_api"
    case logFile = "log_file"
    case transcriptFile = "transcript_file"
    case jsonRPC = "json_rpc"
    case hookFile = "hook_file"
    case processScan = "process_scan"

    public var id: String { rawValue }

    @MainActor public var displayName: String {
        switch self {
        case .httpAPI:
            return L10n.shared.string(.detectionMethodHttpAPI)
        case .logFile:
            return L10n.shared.string(.detectionMethodLogFile)
        case .transcriptFile:
            return L10n.shared.string(.detectionMethodTranscriptFile)
        case .jsonRPC:
            return L10n.shared.string(.detectionMethodJsonRPC)
        case .hookFile:
            return L10n.shared.string(.detectionMethodHookFile)
        case .processScan:
            return L10n.shared.string(.detectionMethodProcessScan)
        }
    }

    /// Priority for ordering (higher = more accurate/preferred)
    public var priority: Int {
        switch self {
        case .httpAPI: return 5
        case .logFile: return 4
        case .jsonRPC: return 3
        case .hookFile: return 2
        case .transcriptFile: return 2
        case .processScan: return 1
        }
    }
}

// MARK: - CLI Tool Configuration

/// Configuration for a single CLI tool
public struct CLIToolConfiguration: Codable, Sendable {
    public var tool: ToolKind
    public var isEnabled: Bool
    public var enabledDetectionMethods: [DetectionMethodPreference]
    public var pluginEnabled: Bool

    public init(
        tool: ToolKind,
        isEnabled: Bool = true,
        enabledDetectionMethods: [DetectionMethodPreference]? = nil,
        pluginEnabled: Bool = false
    ) {
        self.tool = tool
        self.isEnabled = isEnabled
        self.enabledDetectionMethods = enabledDetectionMethods ?? Self.defaultMethods(for: tool)
        self.pluginEnabled = pluginEnabled
    }

    /// Returns the default detection methods for a tool
    public static func defaultMethods(for tool: ToolKind) -> [DetectionMethodPreference] {
        switch tool {
        case .claudeCode:
            return [.logFile, .processScan]
        case .codex:
            return [.processScan]
        case .opencode:
            return [.httpAPI, .processScan]
        case .githubCopilot:
            return [.jsonRPC, .hookFile, .processScan]
        case .aider:
            return [.processScan]
        case .gemini:
            return [.transcriptFile, .processScan]
        }
    }

    /// Returns all available detection methods for a tool
    public static func availableMethods(for tool: ToolKind) -> [DetectionMethodPreference] {
        switch tool {
        case .claudeCode:
            return [.logFile, .processScan]
        case .codex:
            return [.processScan]
        case .opencode:
            return [.httpAPI, .processScan]
        case .githubCopilot:
            return [.jsonRPC, .hookFile, .processScan]
        case .aider:
            return [.processScan]
        case .gemini:
            return [.transcriptFile, .processScan]
        }
    }

    /// Whether this tool supports plugin/hooks
    public static func hasPluginSupport(for tool: ToolKind) -> Bool {
        [.claudeCode, .opencode, .githubCopilot].contains(tool)
    }

    /// Whether this tool supports wrapper command
    public static func hasWrapperSupport(for tool: ToolKind) -> Bool {
        // All tools support wrapper
        true
    }
}

// MARK: - CLI Settings Manager

@MainActor
public final class CLISettingsManager: ObservableObject {
    public static let shared = CLISettingsManager()

    @Published public private(set) var configurations: [ToolKind: CLIToolConfiguration] {
        didSet {
            persistConfigurations()
        }
    }

    private init() {
        self.configurations = Self.loadConfigurations()
    }

    // MARK: - Configuration Access

    public func configuration(for tool: ToolKind) -> CLIToolConfiguration {
        configurations[tool] ?? CLIToolConfiguration(tool: tool)
    }

    public func setConfiguration(_ config: CLIToolConfiguration) {
        configurations[config.tool] = config
    }

    public func isEnabled(_ tool: ToolKind) -> Bool {
        configuration(for: tool).isEnabled
    }

    public func setEnabled(_ tool: ToolKind, enabled: Bool) {
        var config = configuration(for: tool)
        config.isEnabled = enabled
        configurations[tool] = config
    }

    public func enabledDetectionMethods(for tool: ToolKind) -> [DetectionMethodPreference] {
        configuration(for: tool).enabledDetectionMethods
    }

    public func setDetectionMethods(_ tool: ToolKind, methods: [DetectionMethodPreference]) {
        var config = configuration(for: tool)
        config.enabledDetectionMethods = methods
        configurations[tool] = config
    }

    public func isDetectionMethodEnabled(_ tool: ToolKind, method: DetectionMethodPreference) -> Bool {
        configuration(for: tool).enabledDetectionMethods.contains(method)
    }

    public func setDetectionMethod(_ tool: ToolKind, method: DetectionMethodPreference, enabled: Bool) {
        var config = configuration(for: tool)
        if enabled {
            if !config.enabledDetectionMethods.contains(method) {
                config.enabledDetectionMethods.append(method)
                config.enabledDetectionMethods.sort { $0.priority > $1.priority }
            }
        } else {
            config.enabledDetectionMethods.removeAll { $0 == method }
        }
        configurations[tool] = config
    }

    public func isPluginEnabled(_ tool: ToolKind) -> Bool {
        configuration(for: tool).pluginEnabled
    }

    public func setPluginEnabled(_ tool: ToolKind, enabled: Bool) {
        var config = configuration(for: tool)
        config.pluginEnabled = enabled
        configurations[tool] = config
    }

    // MARK: - Tool Information

    public func availableMethods(for tool: ToolKind) -> [DetectionMethodPreference] {
        CLIToolConfiguration.availableMethods(for: tool)
    }

    public func hasPluginSupport(for tool: ToolKind) -> Bool {
        CLIToolConfiguration.hasPluginSupport(for: tool)
    }

    public func hasWrapperSupport(for tool: ToolKind) -> Bool {
        CLIToolConfiguration.hasWrapperSupport(for: tool)
    }

    // MARK: - Persistence

    private func persistConfigurations() {
        guard let data = try? JSONEncoder().encode(configurations) else { return }
        UserDefaults.standard.set(data, forKey: "cliConfigurations")
    }

    private static func loadConfigurations() -> [ToolKind: CLIToolConfiguration] {
        guard let data = UserDefaults.standard.data(forKey: "cliConfigurations"),
              let configs = try? JSONDecoder().decode([ToolKind: CLIToolConfiguration].self, from: data) else {
            return defaultConfigurations()
        }
        return configs
    }

    private static func defaultConfigurations() -> [ToolKind: CLIToolConfiguration] {
        var configs: [ToolKind: CLIToolConfiguration] = [:]
        for tool in ToolKind.allCases {
            configs[tool] = CLIToolConfiguration(
                tool: tool,
                isEnabled: true,
                enabledDetectionMethods: CLIToolConfiguration.defaultMethods(for: tool),
                pluginEnabled: false
            )
        }
        return configs
    }

    // MARK: - Reset

    public func resetToDefaults() {
        configurations = Self.defaultConfigurations()
    }
}

// MARK: - Notification Configuration

/// Represents a state transition that can trigger a notification
public enum NotificationTransition: String, Codable, CaseIterable, Sendable, Identifiable {
    case runningToIdle = "running_to_idle"           // 运行→空闲（任务完成）
    case runningToAwaiting = "running_to_awaiting"   // 运行→等待输入

    public var id: String { rawValue }

    @MainActor public var displayName: String {
        switch self {
        case .runningToIdle:
            return L10n.shared.string(.notifyTransitionRunningToIdle)
        case .runningToAwaiting:
            return L10n.shared.string(.notifyTransitionRunningToAwaiting)
        }
    }
}

/// Global notification configuration
public struct NotificationConfig: Codable, Sendable {
    public var isEnabled: Bool
    public var enabledTransitions: [NotificationTransition]
    public var customTitle: String?
    public var customBody: String?

    public init(
        isEnabled: Bool = true,
        enabledTransitions: [NotificationTransition] = [.runningToIdle, .runningToAwaiting],
        customTitle: String? = nil,
        customBody: String? = nil
    ) {
        self.isEnabled = isEnabled
        self.enabledTransitions = enabledTransitions
        self.customTitle = customTitle
        self.customBody = customBody
    }

    public static var `default`: NotificationConfig {
        .init()
    }
}

// MARK: - Notification Template Renderer

public struct NotificationTemplate {
    public struct Context {
        public let tool: String
        public let state: String
        public let prevState: String
        public let cwd: String
        public let pid: String
        public let time: String

        public init(tool: String, state: String, prevState: String, cwd: String, pid: String, time: String) {
            self.tool = tool
            self.state = state
            self.prevState = prevState
            self.cwd = cwd
            self.pid = pid
            self.time = time
        }
    }

    @MainActor
    public static func render(
        titleTemplate: String?,
        bodyTemplate: String?,
        for session: SessionSnapshot,
        from previousState: ToolActivityState?
    ) -> (title: String, body: String) {
        let context = Context(
            tool: session.tool.displayName,
            state: session.status.displayName,
            prevState: previousState?.displayName ?? "-",
            cwd: session.cwd?.components(separatedBy: "/").last ?? L10n.shared.string(.dirUnknown),
            pid: String(session.pid),
            time: DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
        )

        let title = titleTemplate?.isEmpty == false ? titleTemplate! : "VibeBar"
        let body = bodyTemplate?.isEmpty == false ? bodyTemplate! : defaultBodyTemplate

        return (
            title: renderTemplate(title, with: context),
            body: renderTemplate(body, with: context)
        )
    }

    @MainActor
    private static var defaultBodyTemplate: String {
        "{tool} " + L10n.shared.string(.notifyBodyTemplateSuffix)
    }

    private static func renderTemplate(_ template: String, with context: Context) -> String {
        template
            .replacingOccurrences(of: "{tool}", with: context.tool)
            .replacingOccurrences(of: "{state}", with: context.state)
            .replacingOccurrences(of: "{prevState}", with: context.prevState)
            .replacingOccurrences(of: "{cwd}", with: context.cwd)
            .replacingOccurrences(of: "{pid}", with: context.pid)
            .replacingOccurrences(of: "{time}", with: context.time)
    }
}
