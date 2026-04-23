import AppKit
import Foundation
import VibeBarCore

enum ToolInstallStatus: Sendable, Equatable {
    case checking
    case notInstalled
    case installed(version: String?)
}

// MARK: - Refresh Intervals

private enum RefreshInterval {
    /// Interval when there are active sessions (running or awaitingInput)
    static let active: TimeInterval = 2.0
    /// Interval when only idle sessions remain
    static let idle: TimeInterval = 10.0
    /// Interval when no sessions are visible
    static let stopped: TimeInterval = 15.0
}

@MainActor
final class MonitorViewModel: ObservableObject {
    private struct RefreshConfiguration: Sendable {
        let realtimeEventDisabledTools: Set<ToolKind>
        let codexSessionEnabled: Bool
        let openCodeHTTPEnabled: Bool
        let geminiTranscriptEnabled: Bool
        let claudeTranscriptEnabled: Bool
        let processScanTools: Set<ToolKind>
    }

    private struct RefreshResult: Sendable {
        let sessions: [SessionSnapshot]
        let summary: GlobalSummary
        let interactionsBySessionID: [String: PendingInteraction]
    }

    static let shared = MonitorViewModel()
    nonisolated private static let openCodePendingResumeGrace: TimeInterval = 3.0

    @Published private(set) var sessions: [SessionSnapshot] = []
    @Published private(set) var summary: GlobalSummary = MonitorViewModel.makeEmptySummary()
    @Published private(set) var pendingInteractionsBySessionID: [String: PendingInteraction] = [:]
    @Published private(set) var pluginStatus = PluginStatusReport()
    @Published private(set) var toolInstallStatusByTool: [ToolKind: ToolInstallStatus] = MonitorViewModel.makeCheckingToolInstallStatus()

    /// Number of sessions in running or awaitingInput state
    var runningCount: Int {
        sessions.filter { $0.status == .running || $0.status == .awaitingInput }.count
    }

    private let store = SessionFileStore()
    private let pluginDetector = PluginDetector()

    private var timer: Timer?
    private var cleanupTimer: Timer?
    private var currentInterval: TimeInterval = RefreshInterval.active
    private var lastPluginCheck: Date = .distantPast
    private let pluginCheckTTL: TimeInterval = 180
    private var lastToolInstallStatusCheck: Date = .distantPast
    private let toolInstallStatusCheckTTL: TimeInterval = 180
    private let defaults = UserDefaults.standard
    private var isPaused = false
    private var pausedInterval: TimeInterval?
    private var isRefreshing = false
    private var pendingRefresh = false
    private var refreshTask: Task<Void, Never>?

    init() {
        refreshNow()
        startTimer(with: RefreshInterval.active)
        startCleanupTimer()
        if AppSettings.shared.autoCheckUpdates {
            checkPluginStatusNow()
        }
        checkToolInstallStatusNow()
        setupToolEnabledObserver()
    }

    // MARK: - Pause/Resume

    func pauseRefresh() {
        guard !isPaused else { return }
        isPaused = true
        pausedInterval = currentInterval
        timer?.invalidate()
        timer = nil
        cleanupTimer?.invalidate()
        cleanupTimer = nil
    }

    func resumeRefresh() {
        guard isPaused else { return }
        isPaused = false
        let interval = pausedInterval ?? RefreshInterval.stopped
        startTimer(with: interval)
        startCleanupTimer()
        pausedInterval = nil
        // Refresh once to get latest data
        refreshNow()
    }

    // MARK: - Timer Management

    private func startTimer(with interval: TimeInterval) {
        timer?.invalidate()
        currentInterval = interval
        let newTimer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduleRefresh(force: false)
            }
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    private func startCleanupTimer() {
        cleanupTimer?.invalidate()
        let cleanupInterval: TimeInterval = 300 // 5 minutes
        let newTimer = Timer(timeInterval: cleanupInterval, repeats: true) { [weak self] _ in
            Task.detached {
                let store = SessionFileStore()
                store.cleanupStaleSessions(now: Date(), idleTTL: 30 * 60)
            }
        }
        RunLoop.main.add(newTimer, forMode: .common)
        cleanupTimer = newTimer
    }

    /// Adjust timer frequency based on activity state
    private func adjustTimerInterval() {
        let newInterval: TimeInterval
        if runningCount > 0 {
            newInterval = RefreshInterval.active
        } else if sessions.isEmpty {
            newInterval = RefreshInterval.stopped
        } else {
            newInterval = RefreshInterval.idle
        }
        if newInterval != currentInterval {
            startTimer(with: newInterval)
        }
    }

    // MARK: - Tool Enabled State Observer

    private func setupToolEnabledObserver() {
        NotificationCenter.default.addObserver(
            forName: .cliToolEnabledChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // Extract values outside the MainActor closure to avoid data race
            let tool = notification.userInfo?["tool"] as? ToolKind
            let isEnabled = notification.userInfo?["isEnabled"] as? Bool

            MainActor.assumeIsolated {
                guard let self = self,
                      let tool = tool,
                      let isEnabled = isEnabled else {
                    return
                }

                if isEnabled {
                    // Tool enabled: trigger immediate detection
                    self.refreshNow()
                } else {
                    // Tool disabled: immediately clear all sessions for this tool
                    self.clearSessions(for: tool)
                }
            }
        }
    }

    /// Immediately clear all sessions for a specific tool from memory and file storage
    private func clearSessions(for tool: ToolKind) {
        // Remove from file storage
        let sessionsToRemove = sessions.filter { $0.tool == tool }
        for session in sessionsToRemove {
            store.delete(sessionID: session.id)
        }

        // Remove from memory
        sessions.removeAll { $0.tool == tool }

        // Update summary
        let now = Date()
        summary = SummaryBuilder.build(sessions: sessions, now: now)
    }

    func pluginStatus(for tool: ToolKind) -> PluginInstallStatus {
        switch tool {
        case .claudeCode:
            return pluginStatus.claudeCode
        case .opencode:
            return pluginStatus.opencode
        default:
            return .cliNotFound
        }
    }

    func refreshNow() {
        scheduleRefresh(force: true)
    }

    func pendingInteraction(for session: SessionSnapshot) -> PendingInteraction? {
        pendingInteractionsBySessionID[session.id]
    }

    func resolveInteraction(_ interaction: PendingInteraction, decision: InteractionDecision) {
        Task { @MainActor [weak self] in
            let sessionPID = self?.sessions.first(where: { $0.id == interaction.sessionID })?.pid
            let success = await InteractionActionHandler.shared.submit(
                interaction: interaction,
                decision: decision,
                sessionPID: sessionPID
            )
            guard success else {
                NSSound.beep()
                return
            }
            self?.applyResolvedInteractionLocally(interaction, decision: decision)
        }
    }

    func toolInstallStatus(for tool: ToolKind) -> ToolInstallStatus {
        toolInstallStatusByTool[tool] ?? .checking
    }

    func openSessionsFolder() {
        do {
            try VibeBarPaths.ensureDirectories()
            NSWorkspace.shared.open(VibeBarPaths.sessionsDirectory)
        } catch {
            NSSound.beep()
        }
    }

    func purgeStaleNow() {
        store.cleanupStaleSessions(now: Date(), idleTTL: 1)
        refreshNow()
    }

    private func scheduleRefresh(force: Bool) {
        if isPaused && !force {
            return
        }

        if isRefreshing {
            pendingRefresh = true
            return
        }

        let configuration = makeRefreshConfiguration()
        isRefreshing = true
        pendingRefresh = false

        refreshTask?.cancel()
        let refreshOperation = Task.detached(priority: .utility) {
            await Self.performRefresh(configuration: configuration)
        }

        refreshTask = Task { @MainActor [weak self] in
            let result = await refreshOperation.value
            self?.applyRefreshResult(result)
        }
    }

    private func applyRefreshResult(_ result: RefreshResult) {
        sessions = result.sessions
        summary = result.summary
        pendingInteractionsBySessionID = result.interactionsBySessionID
        adjustTimerInterval()

        isRefreshing = false
        refreshTask = nil

        if pendingRefresh {
            pendingRefresh = false
            scheduleRefresh(force: true)
        }
    }

    private func makeRefreshConfiguration() -> RefreshConfiguration {
        let manager = CLISettingsManager.shared
        var realtimeEventDisabledTools = Set<ToolKind>()
        var processScanTools = Set<ToolKind>()

        for tool in ToolKind.allCases {
            if let realtimeMethod = Self.realtimeEventMethod(for: tool),
               !manager.isDetectionMethodEnabled(tool, method: realtimeMethod) {
                realtimeEventDisabledTools.insert(tool)
            }

            if manager.isEnabled(tool),
               manager.isDetectionMethodEnabled(tool, method: .processScan) {
                processScanTools.insert(tool)
            }
        }

        let openCodeHTTPEnabled =
            manager.isEnabled(.opencode) &&
            manager.isDetectionMethodEnabled(.opencode, method: .httpAPI)
        let codexSessionEnabled =
            manager.isEnabled(.codex) &&
            manager.isDetectionMethodEnabled(.codex, method: .sessionFile)
        let geminiTranscriptEnabled =
            manager.isEnabled(.gemini) &&
            manager.isDetectionMethodEnabled(.gemini, method: .transcriptFile)
        let claudeTranscriptEnabled =
            manager.isEnabled(.claudeCode) &&
            manager.isDetectionMethodEnabled(.claudeCode, method: .transcriptFile)

        return RefreshConfiguration(
            realtimeEventDisabledTools: realtimeEventDisabledTools,
            codexSessionEnabled: codexSessionEnabled,
            openCodeHTTPEnabled: openCodeHTTPEnabled,
            geminiTranscriptEnabled: geminiTranscriptEnabled,
            claudeTranscriptEnabled: claudeTranscriptEnabled,
            processScanTools: processScanTools
        )
    }

    private static func realtimeEventMethod(for tool: ToolKind) -> DetectionMethodPreference? {
        switch tool {
        case .claudeCode, .opencode:
            return .plugin
        case .codex:
            return .hook
        case .aider, .gemini, .githubCopilot:
            return nil
        }
    }

    // MARK: - Plugin Status

    func checkPluginStatusIfNeeded() {
        guard Date().timeIntervalSince(lastPluginCheck) > pluginCheckTTL else { return }
        checkPluginStatusNow()
    }

    func checkPluginStatusNow() {
        lastPluginCheck = Date()
        let detector = pluginDetector
        Task {
            let report = await Task.detached { await detector.detectAll() }.value
            self.pluginStatus = report
        }
    }

    // MARK: - Tool Install Status

    func refreshToolInstallStatusIfNeeded() {
        guard Date().timeIntervalSince(lastToolInstallStatusCheck) > toolInstallStatusCheckTTL else { return }
        checkToolInstallStatusNow()
    }

    func checkToolInstallStatusNow() {
        lastToolInstallStatusCheck = Date()
        let tools = ToolKind.allCases
        for tool in tools where toolInstallStatusByTool[tool] == nil {
            toolInstallStatusByTool[tool] = .checking
        }

        Task {
            let statuses = await Self.detectToolInstallStatuses(tools: tools)
            self.toolInstallStatusByTool = statuses
        }
    }

    func installPlugin(tool: ToolKind) {
        switch tool {
        case .claudeCode:
            pluginStatus.claudeCode = .installing
        case .opencode:
            pluginStatus.opencode = .installing
        default:
            return
        }

        let detector = pluginDetector
        Task {
            do {
                try await Task.detached {
                    switch tool {
                    case .claudeCode:
                        try await detector.installClaudePlugin()
                    case .opencode:
                        try await detector.installOpenCodePlugin()
                    default:
                        break
                    }
                }.value
            } catch {
                let message = error.localizedDescription
                switch tool {
                case .claudeCode:
                    self.pluginStatus.claudeCode = .installFailed(message)
                case .opencode:
                    self.pluginStatus.opencode = .installFailed(message)
                default:
                    break
                }
                return
            }
            // Re-detect after successful install
            self.markPluginUpdatedNow(tool: tool)
            self.clearSkippedPluginVersion(for: tool)
            self.clearPromptedPluginVersion(for: tool)
            let report = await Task.detached { await detector.detectAll() }.value
            self.pluginStatus = report
            self.lastPluginCheck = Date()
        }
    }

    func uninstallPlugin(tool: ToolKind) {
        switch tool {
        case .claudeCode:
            pluginStatus.claudeCode = .uninstalling
        case .opencode:
            pluginStatus.opencode = .uninstalling
        default:
            return
        }

        let detector = pluginDetector
        Task {
            do {
                try await Task.detached {
                    switch tool {
                    case .claudeCode:
                        try await detector.uninstallClaudePlugin()
                    case .opencode:
                        try await detector.uninstallOpenCodePlugin()
                    default:
                        break
                    }
                }.value
            } catch {
                let message = error.localizedDescription
                switch tool {
                case .claudeCode:
                    self.pluginStatus.claudeCode = .uninstallFailed(message)
                case .opencode:
                    self.pluginStatus.opencode = .uninstallFailed(message)
                default:
                    break
                }
                return
            }
            let report = await Task.detached { await detector.detectAll() }.value
            self.pluginStatus = report
            self.lastPluginCheck = Date()
            self.clearSkippedPluginVersion(for: tool)
            self.clearPromptedPluginVersion(for: tool)
        }
    }

    func bundledPluginVersion(for tool: ToolKind) -> String? {
        pluginDetector.readBundledVersion(tool: tool)
    }

    func updatePlugin(tool: ToolKind) {
        switch tool {
        case .claudeCode:
            pluginStatus.claudeCode = .updating
        case .opencode:
            pluginStatus.opencode = .updating
        default:
            return
        }

        let detector = pluginDetector
        Task {
            do {
                try await Task.detached {
                    switch tool {
                    case .claudeCode:
                        try await detector.updateClaudePlugin()
                    case .opencode:
                        try await detector.updateOpenCodePlugin()
                    default:
                        break
                    }
                }.value
            } catch {
                let message = error.localizedDescription
                switch tool {
                case .claudeCode:
                    self.pluginStatus.claudeCode = .updateFailed(message)
                case .opencode:
                    self.pluginStatus.opencode = .updateFailed(message)
                default:
                    break
                }
                return
            }
            self.markPluginUpdatedNow(tool: tool)
            self.clearSkippedPluginVersion(for: tool)
            self.clearPromptedPluginVersion(for: tool)
            let report = await Task.detached { await detector.detectAll() }.value
            self.pluginStatus = report
            self.lastPluginCheck = Date()
        }
    }

    func lastPluginUpdatedAt(for tool: ToolKind) -> Date? {
        guard let seconds = defaults.object(forKey: pluginLastUpdatedKey(for: tool)) as? Double else {
            return nil
        }
        return Date(timeIntervalSince1970: seconds)
    }

    func skipPluginVersion(tool: ToolKind, version: String) {
        defaults.set(version, forKey: skippedPluginVersionKey(for: tool))
    }

    func markPluginUpdatePrompted(tool: ToolKind, version: String) {
        defaults.set(version, forKey: promptedPluginVersionKey(for: tool))
    }

    func skippedPluginVersion(for tool: ToolKind) -> String? {
        defaults.string(forKey: skippedPluginVersionKey(for: tool))
    }

    func shouldPromptForPluginUpdate(tool: ToolKind, version: String) -> Bool {
        guard skippedPluginVersion(for: tool) != version else { return false }
        return promptedPluginVersion(for: tool) != version
    }

    nonisolated private static func performRefresh(configuration: RefreshConfiguration) async -> RefreshResult {
        let store = SessionFileStore()
        let interactionStore = InteractionStore()
        let now = Date()

        var fileSessions = store.loadAll()
        if !configuration.realtimeEventDisabledTools.isEmpty {
            fileSessions.removeAll {
                $0.source == .plugin && configuration.realtimeEventDisabledTools.contains($0.tool)
            }
        }

        let reliableFileTools = reliableFallbackExclusionTools(from: fileSessions, now: now)
        let detector = CompositeSessionDetector(
            codexSessionEnabled: configuration.codexSessionEnabled,
            openCodeHTTPEnabled: configuration.openCodeHTTPEnabled,
            geminiTranscriptEnabled: configuration.geminiTranscriptEnabled,
            claudeTranscriptEnabled: configuration.claudeTranscriptEnabled,
            processScanTools: configuration.processScanTools.subtracting(reliableFileTools)
        )
        let detectedSessions = await detector.detectSessions()
        interactionStore.cleanupExpired(now: now)
        let interactions = interactionStore.loadAll()
        let interactionsBySessionID = latestInteractionsBySession(interactions)
        let merged = merge(
            fileSessions: fileSessions,
            processSessions: detectedSessions,
            now: now,
            store: store
        )
        let activeInteractionsBySessionID = activeInteractionsBySession(
            interactionsBySessionID,
            sessions: merged
        )
        for interaction in interactionsBySessionID.values
            where activeInteractionsBySessionID[interaction.sessionID]?.id != interaction.id {
            interactionStore.delete(id: interaction.id)
        }
        let hydrated = hydrate(
            sessions: merged,
            interactionsBySessionID: activeInteractionsBySessionID
        )
        let enriched = await enrichTerminalTabs(in: hydrated)

        let sorted = enriched.sorted { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.pid < rhs.pid
            }
            return lhs.updatedAt > rhs.updatedAt
        }

        return RefreshResult(
            sessions: sorted,
            summary: SummaryBuilder.build(sessions: sorted, now: now),
            interactionsBySessionID: activeInteractionsBySessionID
        )
    }

    nonisolated private static func enrichTerminalTabs(in sessions: [SessionSnapshot]) async -> [SessionSnapshot] {
        let kittyEnriched = await enrichKittyTabs(in: sessions)
        let weztermEnriched = await enrichWezTermTabs(in: kittyEnriched)
        let ghosttyEnriched = await enrichGhosttyTabs(in: weztermEnriched)
        let iTermEnriched = await enrichITermTabs(in: ghosttyEnriched)
        let tmuxEnriched = await enrichTmuxTabs(in: iTermEnriched)
        return await enrichZellijTabs(in: tmuxEnriched)
    }

    nonisolated private static func enrichKittyTabs(in sessions: [SessionSnapshot]) async -> [SessionSnapshot] {
        var outputsByAddress: [String: String] = [:]
        var result: [SessionSnapshot] = []
        result.reserveCapacity(sessions.count)

        for var session in sessions {
            guard let context = session.terminalContext,
                  context.clientKind == .kitty,
                  let controlAddress = normalized(context.clientControlAddress),
                  let windowID = normalized(context.clientWindowID ?? context.clientSessionID) else {
                result.append(session)
                continue
            }

            let output: String?
            if let cached = outputsByAddress[controlAddress] {
                output = cached
            } else {
                let loaded = await SessionNavigator.kittyRemoteOutput(controlAddress: controlAddress)
                if let loaded {
                    outputsByAddress[controlAddress] = loaded
                }
                output = loaded
            }

            if let output,
               let target = SessionNavigator.resolveKittyTarget(
                    from: output,
                    requestedWindowID: windowID,
                    pid: session.pid,
                    cwd: session.cwd
               ) {
                session.terminalContext = TerminalContextResolver.merge(
                    primary: session.terminalContext,
                    fallback: TerminalContext(
                        clientTabTitle: target.tabTitle,
                        clientTabIndex: target.tabIndex
                    )
                )
            }

            result.append(session)
        }

        return result
    }

    nonisolated private static func enrichWezTermTabs(in sessions: [SessionSnapshot]) async -> [SessionSnapshot] {
        var outputsByAddress: [String: String] = [:]
        let defaultCacheKey = "__default__"
        var result: [SessionSnapshot] = []
        result.reserveCapacity(sessions.count)

        for var session in sessions {
            guard let context = session.terminalContext,
                  context.clientKind == .wezterm else {
                result.append(session)
                continue
            }

            if context.clientTabIndex != nil {
                result.append(session)
                continue
            }

            let cacheKey = normalized(context.clientControlAddress) ?? defaultCacheKey
            let output: String?
            if let cached = outputsByAddress[cacheKey] {
                output = cached
            } else {
                let loaded = await SessionNavigator.weztermListOutput(controlAddress: context.clientControlAddress)
                if let loaded {
                    outputsByAddress[cacheKey] = loaded
                }
                output = loaded
            }

            if let output,
               let target = SessionNavigator.resolveWezTermTarget(
                    from: output,
                    requestedPaneID: context.clientSessionID,
                    cwd: session.cwd
               ) {
                session.terminalContext = TerminalContextResolver.merge(
                    primary: session.terminalContext,
                    fallback: TerminalContext(
                        clientWindowID: target.windowID,
                        clientTabTitle: target.tabTitle,
                        clientTabIndex: target.tabIndex
                    )
                )
            }

            result.append(session)
        }

        return result
    }

    nonisolated private static func enrichGhosttyTabs(in sessions: [SessionSnapshot]) async -> [SessionSnapshot] {
        let needsGhostty = sessions.contains { session in
            guard let context = session.terminalContext else { return false }
            guard context.clientKind == .ghostty else { return false }
            return context.clientTabIndex == nil || context.clientTabID == nil || context.clientNativeSessionID == nil
        }
        guard needsGhostty, let output = await SessionNavigator.ghosttySnapshotOutput() else {
            return sessions
        }

        var result: [SessionSnapshot] = []
        result.reserveCapacity(sessions.count)

        for var session in sessions {
            guard let context = session.terminalContext,
                  context.clientKind == .ghostty else {
                result.append(session)
                continue
            }

            if let target = SessionNavigator.resolveGhosttyTarget(
                from: output,
                cwd: session.cwd,
                titleHints: ghosttyTitleHints(for: session)
            ) {
                session.terminalContext = TerminalContextResolver.merge(
                    primary: session.terminalContext,
                    fallback: TerminalContext(
                        clientWindowID: target.windowID,
                        clientTabID: target.tabID,
                        clientNativeSessionID: target.terminalID,
                        clientTabTitle: target.tabTitle,
                        clientTabIndex: target.tabIndex
                    )
                )
            }

            result.append(session)
        }

        return result
    }

    nonisolated private static func ghosttyTitleHints(for session: SessionSnapshot) -> [String] {
        var hints: [String] = []
        if let title = normalized(session.title) {
            hints.append(title)
        }
        if let currentTask = normalized(session.currentTask), !hints.contains(currentTask) {
            hints.append(currentTask)
        }

        let toolDisplayName = session.tool.displayName
        if !hints.contains(toolDisplayName) {
            hints.append(toolDisplayName)
        }

        if let command = normalized(session.command.first) {
            let basename = (command as NSString).lastPathComponent
            if !basename.isEmpty, !hints.contains(basename) {
                hints.append(basename)
            }
        }

        return hints
    }

    nonisolated private static func enrichITermTabs(in sessions: [SessionSnapshot]) async -> [SessionSnapshot] {
        let needsITerm = sessions.contains { session in
            guard let context = session.terminalContext else { return false }
            guard context.clientKind == .iterm else { return false }
            return context.clientTabIndex == nil || context.clientNativeSessionID == nil || context.clientWindowID == nil
        }
        guard needsITerm, let output = await SessionNavigator.iTermSnapshotOutput() else {
            return sessions
        }

        var result: [SessionSnapshot] = []
        result.reserveCapacity(sessions.count)

        for var session in sessions {
            guard let context = session.terminalContext,
                  context.clientKind == .iterm else {
                result.append(session)
                continue
            }

            if let target = SessionNavigator.resolveITermTarget(
                from: output,
                tty: context.tty,
                sessionID: context.clientSessionID
            ) {
                session.terminalContext = TerminalContextResolver.merge(
                    primary: session.terminalContext,
                    fallback: TerminalContext(
                        clientWindowID: target.windowID,
                        clientNativeSessionID: target.uniqueID,
                        clientTabIndex: target.displayTabIndex
                    )
                )
            }

            result.append(session)
        }

        return result
    }

    nonisolated private static func enrichTmuxTabs(in sessions: [SessionSnapshot]) async -> [SessionSnapshot] {
        var indicesByTarget: [String: Int] = [:]
        var result: [SessionSnapshot] = []
        result.reserveCapacity(sessions.count)

        for var session in sessions {
            guard let context = session.terminalContext,
                  context.sessionManagerKind == .tmux,
                  let socketPath = SessionNavigator.tmuxSocketPath(from: context.sessionManagerSessionID),
                  let paneID = normalized(context.sessionManagerPaneID) else {
                result.append(session)
                continue
            }

            if context.sessionManagerTabIndex != nil {
                result.append(session)
                continue
            }

            let cacheKey = "\(socketPath)|\(paneID)"
            let windowIndex: Int?
            if let cached = indicesByTarget[cacheKey] {
                windowIndex = cached
            } else {
                let loaded = await SessionNavigator.tmuxWindowIndex(socketPath: socketPath, paneID: paneID)
                if let loaded {
                    indicesByTarget[cacheKey] = loaded
                }
                windowIndex = loaded
            }

            if let windowIndex {
                session.terminalContext = TerminalContextResolver.merge(
                    primary: session.terminalContext,
                    fallback: TerminalContext(sessionManagerTabIndex: windowIndex)
                )
            }

            result.append(session)
        }

        return result
    }

    nonisolated private static func enrichZellijTabs(in sessions: [SessionSnapshot]) async -> [SessionSnapshot] {
        var layoutsBySessionName: [String: String] = [:]
        var result: [SessionSnapshot] = []
        result.reserveCapacity(sessions.count)

        for var session in sessions {
            guard let context = session.terminalContext,
                  context.sessionManagerKind == .zellij,
                  let sessionName = normalized(context.sessionManagerSessionID) else {
                result.append(session)
                continue
            }

            if context.sessionManagerTabIndex != nil {
                result.append(session)
                continue
            }

            let layoutOutput: String?
            if let cached = layoutsBySessionName[sessionName] {
                layoutOutput = cached
            } else {
                let loaded = await SessionNavigator.zellijLayoutOutput(sessionName: sessionName)
                if let loaded {
                    layoutsBySessionName[sessionName] = loaded
                }
                layoutOutput = loaded
            }

            guard let layoutOutput else {
                result.append(session)
                continue
            }

            let inferredTabIndex = SessionNavigator.inferZellijTabIndex(
                from: layoutOutput,
                tabName: context.sessionManagerTabName,
                cwd: session.cwd
            )
            let inferredTabName = context.sessionManagerTabName ?? SessionNavigator.inferZellijTabName(
                from: layoutOutput,
                cwd: session.cwd
            )

            if inferredTabIndex != nil || inferredTabName != nil {
                session.terminalContext = TerminalContextResolver.merge(
                    primary: session.terminalContext,
                    fallback: TerminalContext(
                        sessionManagerTabName: inferredTabName,
                        sessionManagerTabIndex: inferredTabIndex
                    )
                )
            }

            result.append(session)
        }

        return result
    }

    nonisolated private static func reliableFallbackExclusionTools(
        from sessions: [SessionSnapshot],
        now: Date
    ) -> Set<ToolKind> {
        let wrapperStaleTTL: TimeInterval = 10.0
        let pluginStaleTTL: TimeInterval = 45.0
        var result = Set<ToolKind>()

        for session in sessions {
            switch session.source {
            case .wrapper:
                if now.timeIntervalSince(session.updatedAt) <= wrapperStaleTTL {
                    result.insert(session.tool)
                }
            case .plugin:
                let hasPID = session.pid > 0
                let pidAlive = hasPID && kill(session.pid, 0) == 0
                if session.tool == .opencode {
                    continue
                }
                if pidAlive || (!hasPID && now.timeIntervalSince(session.updatedAt) <= pluginStaleTTL) {
                    result.insert(session.tool)
                }
            default:
                continue
            }
        }

        return result
    }

    nonisolated static func mergeDetectedDetails(
        into fileSession: SessionSnapshot,
        from detectedSession: SessionSnapshot
    ) -> SessionSnapshot {
        var merged = fileSession
        let protectClaudePluginStatusFields = shouldProtectClaudePluginStatusFields(
            merged: merged,
            detected: detectedSession
        )

        let mergedTitle = normalized(merged.title)
        let detectedTitle = normalized(detectedSession.title)
        if mergedTitle == nil ||
            (detectedTitle != nil && titlePriority(of: detectedSession) > titlePriority(of: merged)) {
            merged.title = detectedTitle
            if detectedTitle != nil {
                merged.titleSource = detectedSession.titleSource
            }
        }
        let detectedCurrentTask = normalized(detectedSession.currentTask) ?? detectedTitle
        if shouldAdoptDetectedCurrentTask(existing: merged.currentTask, detected: detectedCurrentTask, session: merged) {
            merged.currentTask = detectedCurrentTask
        }
        if shouldAdoptDetectedLastUserMessage(existing: merged.lastUserMessage, detected: detectedSession.lastUserMessage, session: merged) {
            merged.lastUserMessage = normalized(detectedSession.lastUserMessage)
        }
        if shouldAdoptDetectedRunningSummary(existing: merged.runningSummary, detected: detectedSession.runningSummary, session: merged) {
            merged.runningSummary = normalized(detectedSession.runningSummary)
        } else if shouldClearLowSignalRunningSummary(existing: merged.runningSummary, session: merged) {
            merged.runningSummary = nil
        }
        if normalized(merged.cwd) == nil {
            merged.cwd = normalized(detectedSession.cwd)
        }
        if normalized(merged.notes) == nil {
            merged.notes = normalized(detectedSession.notes)
        }
        if merged.parentPID == nil {
            merged.parentPID = detectedSession.parentPID
        }
        if merged.command.isEmpty {
            merged.command = detectedSession.command
        }
        if !protectClaudePluginStatusFields, merged.lastOutputAt == nil {
            merged.lastOutputAt = detectedSession.lastOutputAt
        }
        if !protectClaudePluginStatusFields, merged.lastInputAt == nil {
            merged.lastInputAt = detectedSession.lastInputAt
        }
        if shouldAdoptOpenCodeDetectedResumeStatus(merged: merged, detected: detectedSession) {
            merged.status = detectedSession.status
            merged.pendingInteractionID = nil
            merged.updatedAt = max(merged.updatedAt, detectedSession.updatedAt)
            merged.statusSince = detectedSession.statusSince ?? detectedSession.updatedAt
            switch detectedSession.status {
            case .running:
                merged.lastOutputAt = max(merged.lastOutputAt ?? detectedSession.updatedAt, detectedSession.updatedAt)
                merged.idleSince = nil
            case .idle:
                merged.idleSince = detectedSession.idleSince ?? detectedSession.updatedAt
            case .completed, .awaitingInput, .unknown:
                break
            }
        }
        if !protectClaudePluginStatusFields, merged.status == detectedSession.status {
            if shouldPreferDetectedCodexStatusAnchor(
                existing: merged.statusSince,
                detected: detectedSession.statusSince,
                merged: merged,
                detected: detectedSession
            ) {
                merged.statusSince = detectedSession.statusSince
            } else if merged.statusSince == nil {
                merged.statusSince = detectedSession.statusSince
            }
        }
        if merged.status == .idle {
            if !protectClaudePluginStatusFields {
                if shouldPreferDetectedCodexStatusAnchor(
                    existing: merged.idleSince,
                    detected: detectedSession.idleSince,
                    merged: merged,
                    detected: detectedSession
                ) {
                    merged.idleSince = detectedSession.idleSince
                } else if merged.idleSince == nil {
                    merged.idleSince = detectedSession.idleSince
                }
                if merged.statusSince == nil {
                    merged.statusSince = detectedSession.statusSince ?? detectedSession.idleSince
                }
            }
        } else {
            merged.idleSince = nil
        }
        merged.terminalContext = TerminalContextResolver.merge(
            primary: merged.terminalContext,
            fallback: detectedSession.terminalContext
        )

        return merged
    }

    nonisolated private static func shouldPreferDetectedCodexStatusAnchor(
        existing: Date?,
        detected: Date?,
        merged: SessionSnapshot,
        detected detectedSession: SessionSnapshot
    ) -> Bool {
        guard merged.tool == .codex,
              detectedSession.tool == .codex,
              merged.status == detectedSession.status,
              let detected else {
            return false
        }
        guard let existing else {
            return true
        }
        if merged.status == .running,
           merged.source == .plugin,
           detectedSession.source == .sessionFile {
            return false
        }
        return detected > existing
    }

    nonisolated private static func shouldProtectClaudePluginStatusFields(
        merged: SessionSnapshot,
        detected detectedSession: SessionSnapshot
    ) -> Bool {
        merged.tool == .claudeCode
            && detectedSession.tool == .claudeCode
            && merged.source == .plugin
            && detectedSession.source == .transcriptFile
    }

    nonisolated private static func shouldAdoptOpenCodeDetectedResumeStatus(
        merged: SessionSnapshot,
        detected detectedSession: SessionSnapshot
    ) -> Bool {
        guard merged.tool == .opencode,
              detectedSession.tool == .opencode,
              merged.source == .plugin,
              merged.status == .awaitingInput,
              merged.pendingInteractionID != nil,
              detectedSession.status == .running || detectedSession.status == .idle else {
            return false
        }

        let anchor = [
            merged.lastInputAt,
            merged.statusSince,
            merged.updatedAt,
        ]
            .compactMap { $0 }
            .max() ?? merged.updatedAt

        return detectedSession.updatedAt.timeIntervalSince(anchor) > openCodePendingResumeGrace
    }

    nonisolated private static func titlePriority(of session: SessionSnapshot) -> Int {
        switch session.titleSource {
        case .explicit:
            return 2
        case .derived:
            return 1
        case nil:
            return 0
        }
    }

    nonisolated private static func shouldAdoptDetectedCurrentTask(
        existing: String?,
        detected: String?,
        session: SessionSnapshot
    ) -> Bool {
        let existing = normalized(existing)
        let detected = normalized(detected)

        guard let detected else {
            return false
        }
        guard let existing else {
            return true
        }
        if existing == detected {
            return false
        }
        if session.tool == .codex,
           CodexLabelHeuristics.isLowSignalToolLabel(existing) {
            return true
        }

        return false
    }

    nonisolated private static func shouldAdoptDetectedRunningSummary(
        existing: String?,
        detected: String?,
        session: SessionSnapshot
    ) -> Bool {
        let existing = normalized(existing)
        let detected = normalized(detected)

        guard let detected else {
            return false
        }
        guard let existing else {
            return true
        }
        if existing == detected {
            return false
        }
        if session.tool == .codex,
           CodexLabelHeuristics.isLowSignalToolLabel(existing) {
            return true
        }
        guard session.tool == .opencode else {
            return false
        }

        let lowSignalValues: Set<String> = ["处理中"]
        let duplicatedValues = Set(
            [
                normalized(session.title),
                normalized(session.currentTask),
                normalized(session.lastUserMessage),
            ]
            .compactMap { $0 }
        )

        if lowSignalValues.contains(existing) {
            return true
        }
        if duplicatedValues.contains(existing), !duplicatedValues.contains(detected) {
            return true
        }

        return false
    }

    nonisolated private static func shouldClearLowSignalRunningSummary(
        existing: String?,
        session: SessionSnapshot
    ) -> Bool {
        guard session.tool == .codex else {
            return false
        }

        return CodexLabelHeuristics.isLowSignalToolLabel(existing)
    }

    nonisolated private static func shouldAdoptDetectedLastUserMessage(
        existing: String?,
        detected: String?,
        session: SessionSnapshot
    ) -> Bool {
        let existing = normalized(existing)
        let detected = normalized(detected)

        guard let detected else {
            return false
        }
        guard let existing else {
            return true
        }
        if existing == detected {
            return false
        }
        guard session.tool == .opencode else {
            return false
        }

        return isLowSignalUserMessage(existing) && !isLowSignalUserMessage(detected)
    }

    nonisolated private static func isLowSignalUserMessage(_ value: String) -> Bool {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalized.isEmpty else {
            return true
        }

        let exactMatches: Set<String> = [
            "好",
            "好的",
            "行",
            "可以",
            "嗯",
            "哦",
            "要",
            "是",
            "否",
            "继续",
            "继续吧",
            "ok",
            "okay",
            "yes",
            "no",
            "continue",
        ]
        if exactMatches.contains(normalized) {
            return true
        }

        return normalized.count <= 2
    }

    nonisolated static func merge(
        fileSessions: [SessionSnapshot],
        processSessions: [SessionSnapshot],
        now: Date,
        store: SessionFileStore
    ) -> [SessionSnapshot] {
        let activePIDs = Set(processSessions.map { $0.pid })
        let wrapperStaleTTL: TimeInterval = 10.0
        let pluginStaleTTL: TimeInterval = 45.0

        var normalized: [SessionSnapshot] = fileSessions.compactMap { session in
            if session.source == .wrapper {
                // wrapper 会话以状态心跳为准，不依赖 ps 命中，避免误删运行中的会话。
                if now.timeIntervalSince(session.updatedAt) > wrapperStaleTTL {
                    store.delete(sessionID: session.id)
                    return nil
                }
                return session
            }

            if session.source == .plugin {
                let hasPID = session.pid > 0
                let pidAlive = hasPID && kill(session.pid, 0) == 0

                // PID 已知且进程存活 → 保留（即使心跳过期，如 Claude 无心跳）
                if pidAlive {
                    return session
                }
                // PID 已知但进程已死 → 立即清理
                if hasPID {
                    store.delete(sessionID: session.id)
                    return nil
                }
                // PID 未知 → 按心跳超时兜底
                if now.timeIntervalSince(session.updatedAt) > pluginStaleTTL {
                    store.delete(sessionID: session.id)
                    return nil
                }
                return session
            }

            // 非 wrapper 的落盘会话属于旧数据，按进程存活判断后清理。
            if !activePIDs.contains(session.pid), now.timeIntervalSince(session.updatedAt) > 2.0 {
                store.delete(sessionID: session.id)
                return nil
            }
            return session
        }

        // 同一 PID 可能因插件生成不同 sessionID 而出现多条记录，按 PID 去重，
        // 保留 updatedAt 最新的会话，清理旧文件。
        var bestByPID: [Int32: Int] = [:]  // pid → index in normalized
        var duplicateIndices = Set<Int>()
        for (index, session) in normalized.enumerated() {
            guard session.pid > 0 else { continue }
            if let existingIndex = bestByPID[session.pid] {
                let existing = normalized[existingIndex]
                if shouldPreferFileSession(session, over: existing) {
                    // 新记录更新，淘汰旧记录
                    duplicateIndices.insert(existingIndex)
                    store.delete(sessionID: existing.id)
                    bestByPID[session.pid] = index
                } else {
                    // 旧记录更新，淘汰当前记录
                    duplicateIndices.insert(index)
                    store.delete(sessionID: session.id)
                }
            } else {
                bestByPID[session.pid] = index
            }
        }
        if !duplicateIndices.isEmpty {
            normalized = normalized.enumerated()
                .filter { !duplicateIndices.contains($0.offset) }
                .map { $0.element }
        }

        var detectedIndexByPID: [Int32: Int] = [:]
        var detectedIndexByCodexSessionID: [String: Int] = [:]
        for (index, session) in processSessions.enumerated() {
            if session.pid > 0 {
                detectedIndexByPID[session.pid] = index
            }
            if let codexSessionID = codexMergeSessionID(for: session) {
                detectedIndexByCodexSessionID[codexSessionID] = index
            }
        }
        var matchedDetectedIndices = Set<Int>()

        for index in normalized.indices {
            guard let detectedIndex = detectedSessionIndex(
                for: normalized[index],
                detectedIndexByPID: detectedIndexByPID,
                detectedIndexByCodexSessionID: detectedIndexByCodexSessionID,
                usedIndices: matchedDetectedIndices
            ) else {
                continue
            }
            let detectedSession = processSessions[detectedIndex]
            normalized[index] = mergeDetectedDetails(
                into: normalized[index],
                from: detectedSession
            )
            matchedDetectedIndices.insert(detectedIndex)
        }

        let normalizedPIDs = Set(normalized.map { $0.pid })
        for (index, processSession) in processSessions.enumerated()
            where !matchedDetectedIndices.contains(index) &&
                (processSession.pid <= 0 || !normalizedPIDs.contains(processSession.pid)) {
            normalized.append(processSession)
        }

        return normalized
    }

    nonisolated static func shouldPreferFileSession(
        _ candidate: SessionSnapshot,
        over existing: SessionSnapshot
    ) -> Bool {
        let candidatePriority = fileSessionPriority(candidate)
        let existingPriority = fileSessionPriority(existing)
        if candidatePriority != existingPriority {
            return candidatePriority > existingPriority
        }
        if candidate.updatedAt != existing.updatedAt {
            return candidate.updatedAt > existing.updatedAt
        }
        return candidate.id > existing.id
    }

    nonisolated static func fileSessionPriority(_ session: SessionSnapshot) -> Int {
        switch session.source {
        case .plugin:
            return 3
        case .wrapper:
            return 2
        case .sessionFile, .transcriptFile, .processScan:
            return 1
        }
    }

    nonisolated private static func detectedSessionIndex(
        for session: SessionSnapshot,
        detectedIndexByPID: [Int32: Int],
        detectedIndexByCodexSessionID: [String: Int],
        usedIndices: Set<Int>
    ) -> Int? {
        if session.pid > 0,
           let index = detectedIndexByPID[session.pid],
           !usedIndices.contains(index) {
            return index
        }

        if let codexSessionID = codexMergeSessionID(for: session),
           let index = detectedIndexByCodexSessionID[codexSessionID],
           !usedIndices.contains(index) {
            return index
        }

        return nil
    }

    nonisolated private static func codexMergeSessionID(for session: SessionSnapshot) -> String? {
        guard session.tool == .codex else {
            return nil
        }

        let prefixes = [
            "plugin-\(AgentEventSource.codexHook.rawValue)-",
            "codex-session-",
        ]
        for prefix in prefixes {
            if session.id.hasPrefix(prefix) {
                return String(session.id.dropFirst(prefix.count))
            }
        }

        return nil
    }

    nonisolated private static func latestInteractionsBySession(
        _ interactions: [PendingInteraction]
    ) -> [String: PendingInteraction] {
        var result: [String: PendingInteraction] = [:]
        for interaction in interactions {
            if let existing = result[interaction.sessionID] {
                if interaction.requestedAt > existing.requestedAt {
                    result[interaction.sessionID] = interaction
                }
            } else {
                result[interaction.sessionID] = interaction
            }
        }
        return result
    }

    nonisolated static func activeInteractionsBySession(
        _ interactionsBySessionID: [String: PendingInteraction],
        sessions: [SessionSnapshot]
    ) -> [String: PendingInteraction] {
        var sessionsByID: [String: SessionSnapshot] = [:]
        for session in sessions {
            sessionsByID[session.id] = session
        }

        return interactionsBySessionID.filter { sessionID, interaction in
            guard let session = sessionsByID[sessionID] else {
                return true
            }
            return shouldKeepInteraction(interaction, for: session)
        }
    }

    nonisolated private static func shouldKeepInteraction(
        _ interaction: PendingInteraction,
        for session: SessionSnapshot
    ) -> Bool {
        guard interaction.tool == .opencode,
              session.tool == .opencode else {
            return true
        }
        if session.status == .awaitingInput {
            return true
        }

        return !hasOpenCodeProgressAfterInteraction(interaction, in: session)
    }

    nonisolated private static func hasOpenCodeProgressAfterInteraction(
        _ interaction: PendingInteraction,
        in session: SessionSnapshot
    ) -> Bool {
        let latestActivity = [
            session.lastOutputAt,
            session.statusSince,
            session.updatedAt,
        ]
            .compactMap { $0 }
            .max() ?? session.updatedAt

        return latestActivity.timeIntervalSince(interaction.requestedAt) > openCodePendingResumeGrace
    }

    nonisolated private static func hydrate(
        sessions: [SessionSnapshot],
        interactionsBySessionID: [String: PendingInteraction]
    ) -> [SessionSnapshot] {
        sessions.map { session in
            guard let interaction = interactionsBySessionID[session.id] else {
                var session = session
                session.pendingInteractionID = nil
                return session
            }

            var hydrated = session
            hydrated.pendingInteractionID = interaction.id
            hydrated.status = .awaitingInput
            hydrated.statusSince = interaction.requestedAt
            hydrated.idleSince = nil
            if hydrated.currentTask?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                if let title = interaction.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                    hydrated.currentTask = title
                } else {
                    hydrated.currentTask = interaction.message
                }
            }
            return hydrated
        }
    }

    private static func makeEmptySummary() -> GlobalSummary {
        var byTool: [ToolKind: ToolSummary] = [:]
        for tool in ToolKind.allCases {
            byTool[tool] = ToolSummary(tool: tool, total: 0, counts: [:], overall: .stopped)
        }
        return GlobalSummary(total: 0, counts: [:], byTool: byTool, updatedAt: Date())
    }

    private static func makeCheckingToolInstallStatus() -> [ToolKind: ToolInstallStatus] {
        var statuses: [ToolKind: ToolInstallStatus] = [:]
        for tool in ToolKind.allCases {
            statuses[tool] = .checking
        }
        return statuses
    }

    private func pluginLastUpdatedKey(for tool: ToolKind) -> String {
        "plugin.lastUpdatedAt.\(tool.rawValue)"
    }

    nonisolated private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func skippedPluginVersionKey(for tool: ToolKind) -> String {
        "plugin.skippedVersion.\(tool.rawValue)"
    }

    private func promptedPluginVersionKey(for tool: ToolKind) -> String {
        "plugin.promptedVersion.\(tool.rawValue)"
    }

    private func markPluginUpdatedNow(tool: ToolKind) {
        defaults.set(Date().timeIntervalSince1970, forKey: pluginLastUpdatedKey(for: tool))
    }

    private func promptedPluginVersion(for tool: ToolKind) -> String? {
        defaults.string(forKey: promptedPluginVersionKey(for: tool))
    }

    private func clearSkippedPluginVersion(for tool: ToolKind) {
        defaults.removeObject(forKey: skippedPluginVersionKey(for: tool))
    }

    private func clearPromptedPluginVersion(for tool: ToolKind) {
        defaults.removeObject(forKey: promptedPluginVersionKey(for: tool))
    }

    private func applyResolvedInteractionLocally(
        _ interaction: PendingInteraction,
        decision: InteractionDecision
    ) {
        pendingInteractionsBySessionID.removeValue(forKey: interaction.sessionID)

        guard let index = sessions.firstIndex(where: { $0.id == interaction.sessionID }) else {
            summary = SummaryBuilder.build(sessions: sessions, now: Date())
            return
        }

        sessions[index].pendingInteractionID = nil
        let previousStatus = sessions[index].status
        if sessions[index].status == .awaitingInput {
            sessions[index].status = .running
        }
        sessions[index].idleSince = nil
        let now = Date()
        if previousStatus != sessions[index].status || sessions[index].statusSince == nil {
            sessions[index].statusSince = now
        }
        sessions[index].updatedAt = now
        sessions[index].lastOutputAt = now

        if let optionID = decision.optionID,
           let option = interaction.displayOptions.first(where: { $0.id == optionID }) {
            sessions[index].currentTask = option.label
        } else if let text = decision.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty {
            sessions[index].currentTask = text
        }

        sessions = SessionListPresentation.sortedSessions(sessions)
        summary = SummaryBuilder.build(sessions: sessions, now: now)
    }

    nonisolated private static func detectToolInstallStatuses(tools: [ToolKind]) async -> [ToolKind: ToolInstallStatus] {
        await withTaskGroup(of: (ToolKind, ToolInstallStatus).self) { group in
            for tool in tools {
                group.addTask {
                    (tool, detectToolInstallStatus(tool))
                }
            }

            var result: [ToolKind: ToolInstallStatus] = [:]
            for await (tool, status) in group {
                result[tool] = status
            }
            return result
        }
    }

    nonisolated private static func detectToolInstallStatus(_ tool: ToolKind) -> ToolInstallStatus {
        guard let which = runCommand(
            executable: "/usr/bin/which",
            arguments: [tool.executable]
        ) else {
            return .notInstalled
        }

        guard which.status == 0 else {
            return .notInstalled
        }

        let path = which.output
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? tool.executable

        let versionArguments: [[String]] = [["--version"], ["version"], ["-v"]]
        for args in versionArguments {
            guard let result = runCommand(executable: path, arguments: args) else { continue }
            guard result.status == 0 else { continue }
            if let version = parseVersion(from: result.output) {
                return .installed(version: version)
            }
        }

        return .installed(version: nil)
    }

    nonisolated private static func parseVersion(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let match = trimmed.range(
            of: #"\d+\.\d+\.\d+(?:[-+][0-9A-Za-z\.-]+)?"#,
            options: .regularExpression
        ) {
            return String(trimmed[match])
        }
        if let match = trimmed.range(of: #"\d+\.\d+"#, options: .regularExpression) {
            return String(trimmed[match])
        }
        return nil
    }

    nonisolated private static func runCommand(
        executable: String,
        arguments: [String],
        timeout: TimeInterval = 2.5
    ) -> (status: Int32, output: String)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = VibeBarPaths.childProcessEnvironment
        process.standardInput = FileHandle.nullDevice

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            semaphore.signal()
        }

        do {
            try process.run()
        } catch {
            return nil
        }

        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = semaphore.wait(timeout: .now() + 0.5)
            return nil
        }

        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
        let stdoutText = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderrText = String(data: stderrData, encoding: .utf8) ?? ""
        let output = stdoutText + stderrText

        return (status: process.terminationStatus, output: output)
    }
}
