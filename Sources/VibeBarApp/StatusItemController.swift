import AppKit
import Combine
import Foundation
import SwiftUI
import UserNotifications
import VibeBarCore

@MainActor
private enum StatusColors {
    static func activity(_ state: ToolActivityState) -> NSColor {
        AppSettings.shared.nsColor(for: state)
    }

    static func overall(_ state: ToolOverallState) -> NSColor {
        switch state {
        case .running:
            return activity(.running)
        case .awaitingInput:
            return activity(.awaitingInput)
        case .idle:
            return activity(.idle)
        case .stopped, .unknown:
            return NSColor.secondaryLabelColor
        }
    }
}

@MainActor
final class StatusItemController: NSObject {
    private enum NotificationConstants {
        static let openMenuAction = "open-menu"
    }

    private let model = MonitorViewModel.shared
    private let usageModel = UsageMonitorViewModel.shared
    private let wrapperCommandModel = WrapperCommandViewModel.shared
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let notificationCenter: UNUserNotificationCenter?
    private var cancellables = Set<AnyCancellable>()
    private var hasInitializedSessionStates = false
    private var previousSessionStates: [String: ToolActivityState] = [:]
    private var notifiedAwaitingSessionIDs = Set<String>()
    private var notifiedIdleSessionIDs = Set<String>()
    /// Sessions first seen in `running` state — their first running→idle is startup, not task completion
    private var newSessionsInStartupRun = Set<String>()
    private var didHandleStartupPluginUpdatePrompt = false
    private var isMenuOpen = false

    override init() {
        if VibeBarPaths.runMode == .published {
            notificationCenter = UNUserNotificationCenter.current()
        } else {
            notificationCenter = nil
        }

        super.init()
        menu.delegate = self
        statusItem.menu = menu
        notificationCenter?.delegate = self
        configureButtonIfPossible()
        bindModel()
        updateUI(
            summary: model.summary,
            sessions: model.sessions,
            pluginStatus: model.pluginStatus,
            wrapperStatus: wrapperCommandModel.status
        )

        if AppSettings.shared.notificationConfig.isEnabled {
            requestNotificationPermission { _ in }
        }

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.postLaunchCheck()
        }
    }

    private func configureButtonIfPossible() {
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageLeading
        button.appearsDisabled = false
        button.title = ""
        button.isHidden = false
        statusItem.isVisible = true
    }

    private func bindModel() {
        model.$summary
            .combineLatest(model.$sessions, model.$pluginStatus)
            .sink { [weak self] summary, sessions, pluginStatus in
                guard let self else { return }
                self.updateUI(
                    summary: summary,
                    sessions: sessions,
                    pluginStatus: pluginStatus,
                    wrapperStatus: self.wrapperCommandModel.status
                )
            }
            .store(in: &cancellables)

        wrapperCommandModel.$status
            .sink { [weak self] status in
                guard let self else { return }
                self.updateUI(
                    summary: self.model.summary,
                    sessions: self.model.sessions,
                    pluginStatus: self.model.pluginStatus,
                    wrapperStatus: status
                )
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(usageModel.$snapshot, usageModel.$isRefreshing)
            .sink { [weak self] _, _ in
                guard let self else { return }
                self.updateUI(
                    summary: self.model.summary,
                    sessions: self.model.sessions,
                    pluginStatus: self.model.pluginStatus,
                    wrapperStatus: self.wrapperCommandModel.status
                )
            }
            .store(in: &cancellables)

        AppSettings.shared.$iconStyle
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateUI(
                    summary: self.model.summary,
                    sessions: self.model.sessions,
                    pluginStatus: self.model.pluginStatus,
                    wrapperStatus: self.wrapperCommandModel.status
                )
            }
            .store(in: &cancellables)

        AppSettings.shared.$colorTheme
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateUI(
                    summary: self.model.summary,
                    sessions: self.model.sessions,
                    pluginStatus: self.model.pluginStatus,
                    wrapperStatus: self.wrapperCommandModel.status
                )
            }
            .store(in: &cancellables)

        AppSettings.shared.$customRunningColor
            .merge(with: AppSettings.shared.$customAwaitingColor)
            .merge(with: AppSettings.shared.$customIdleColor)
            .dropFirst(3)
            .sink { [weak self] _ in
                guard let self, AppSettings.shared.colorTheme == .custom else { return }
                self.updateUI(
                    summary: self.model.summary,
                    sessions: self.model.sessions,
                    pluginStatus: self.model.pluginStatus,
                    wrapperStatus: self.wrapperCommandModel.status
                )
            }
            .store(in: &cancellables)

        AppSettings.shared.$groupSessionsByTool
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateUI(
                    summary: self.model.summary,
                    sessions: self.model.sessions,
                    pluginStatus: self.model.pluginStatus,
                    wrapperStatus: self.wrapperCommandModel.status
                )
            }
            .store(in: &cancellables)

        L10n.shared.$resolvedLang
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateUI(
                    summary: self.model.summary,
                    sessions: self.model.sessions,
                    pluginStatus: self.model.pluginStatus,
                    wrapperStatus: self.wrapperCommandModel.status
                )
            }
            .store(in: &cancellables)

        AppSettings.shared.$notificationConfig
            .dropFirst()
            .sink { [weak self] config in
                guard let self else { return }
                guard config.isEnabled else { return }
                self.notifiedAwaitingSessionIDs.removeAll()
                self.notifiedIdleSessionIDs.removeAll()
                self.requestNotificationPermission { granted in
                    guard granted else { return }
                    self.notifyCurrentRelevantSessions()
                }
            }
            .store(in: &cancellables)
    }

    private func updateUI(
        summary: GlobalSummary,
        sessions: [SessionSnapshot],
        pluginStatus: PluginStatusReport,
        wrapperStatus: WrapperCommandUIStatus
    ) {
        guard let button = statusItem.button else { return }

        button.title = ""
        button.image = StatusImageRenderer.render(summary: summary, style: AppSettings.shared.iconStyle)
        button.toolTip = L10n.shared.string(.tooltipFmt, summary.total)

        notifyStateTransitionsIfNeeded(sessions: sessions)
        if isMenuOpen {
            rebuildMenuItems(
                summary: summary,
                sessions: sessions,
                pluginStatus: pluginStatus,
                wrapperStatus: wrapperStatus
            )
        }
    }

    private func notifyStateTransitionsIfNeeded(sessions: [SessionSnapshot]) {
        let config = AppSettings.shared.notificationConfig
        guard config.isEnabled else {
            hasInitializedSessionStates = true
            previousSessionStates = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0.status) })
            return
        }

        let waitingIDs = Set(sessions.filter { $0.status == .awaitingInput }.map { $0.id })
        let idleIDs = Set(sessions.filter { $0.status == .idle }.map { $0.id })
        notifiedAwaitingSessionIDs.formIntersection(waitingIDs)
        notifiedIdleSessionIDs.formIntersection(idleIDs)

        let currentStates = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0.status) })
        defer {
            previousSessionStates = currentStates
            hasInitializedSessionStates = true
        }

        // Skip notification checks on first initialization - we only want to notify
        // on actual state transitions, not initial states
        guard hasInitializedSessionStates else {
            return
        }

        let currentSessionIDs = Set(sessions.map { $0.id })
        newSessionsInStartupRun.formIntersection(currentSessionIDs)

        for session in sessions {
            let previous = previousSessionStates[session.id]
            let previousState = previous ?? .unknown

            // Track new sessions first seen in running state:
            // their first running→idle is the agent startup, not a real task completion
            if previous == nil, session.status == .running {
                newSessionsInStartupRun.insert(session.id)
            }

            // Check running -> idle transition
            if config.enabledTransitions.contains(.runningToIdle),
               previousState == .running,
               session.status == .idle,
               !notifiedIdleSessionIDs.contains(session.id) {
                if newSessionsInStartupRun.remove(session.id) != nil {
                    // Suppress: this is the agent's initial startup running→idle, not a task completion
                } else {
                    postNotification(for: session, from: previousState, transition: .runningToIdle)
                    notifiedIdleSessionIDs.insert(session.id)
                }
            }

            // Check running -> awaitingInput transition
            if config.enabledTransitions.contains(.runningToAwaiting),
               previousState == .running,
               session.status == .awaitingInput,
               !notifiedAwaitingSessionIDs.contains(session.id) {
                postNotification(for: session, from: previousState, transition: .runningToAwaiting)
                notifiedAwaitingSessionIDs.insert(session.id)
            }
        }
    }

    private func requestNotificationPermission(completion: @escaping @MainActor (Bool) -> Void) {
        guard let notificationCenter else {
            Task { @MainActor in completion(false) }
            return
        }

        notificationCenter.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                fputs("vibebar: 请求通知权限失败: \(error.localizedDescription)\n", stderr)
            }

            UNUserNotificationCenter.current().getNotificationSettings { settings in
                let canPresentBanner = Self.canPresentBanner(with: settings) || granted
                Task { @MainActor in
                    completion(canPresentBanner)
                }
            }
        }
    }

    nonisolated private static func canPresentBanner(with settings: UNNotificationSettings) -> Bool {
        let status = settings.authorizationStatus
        let authorized = status == .authorized || status == .provisional
        return authorized && settings.alertSetting == .enabled
    }

    private func notifyCurrentRelevantSessions() {
        let config = AppSettings.shared.notificationConfig
        guard config.isEnabled else { return }

        for session in model.sessions {
            // Check awaiting sessions
            if config.enabledTransitions.contains(.runningToAwaiting),
               session.status == .awaitingInput,
               !notifiedAwaitingSessionIDs.contains(session.id) {
                postNotification(for: session, from: nil, transition: .runningToAwaiting)
                notifiedAwaitingSessionIDs.insert(session.id)
            }

            // Check idle sessions
            if config.enabledTransitions.contains(.runningToIdle),
               session.status == .idle,
               !notifiedIdleSessionIDs.contains(session.id) {
                postNotification(for: session, from: nil, transition: .runningToIdle)
                notifiedIdleSessionIDs.insert(session.id)
            }
        }
    }

    private func postNotification(for session: SessionSnapshot, from previousState: ToolActivityState?, transition: NotificationTransition) {
        let config = AppSettings.shared.notificationConfig
        let id = "\(transition.rawValue)-\(session.id)-\(UUID().uuidString)"

        let (title, body) = NotificationTemplate.render(
            titleTemplate: config.customTitle,
            bodyTemplate: config.customBody,
            for: session,
            from: previousState
        )

        requestNotificationPermission { [weak self] granted in
            guard granted else { return }
            self?.deliverUNNotification(id: id, title: title, body: body)
        }
    }

    private func deliverUNNotification(id: String, title: String, body: String) {
        guard let notificationCenter else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["action": NotificationConstants.openMenuAction]

        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        notificationCenter.add(request) { error in
            guard let error else { return }
            fputs("vibebar: 发送通知失败: \(error.localizedDescription)\n", stderr)
        }
    }

    private func openMenuFromNotification() {
        guard let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        button.performClick(nil)
    }

    private func rebuildMenuItems(
        summary: GlobalSummary,
        sessions: [SessionSnapshot],
        pluginStatus: PluginStatusReport,
        wrapperStatus: WrapperCommandUIStatus
    ) {
        menu.removeAllItems()

        let title = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        title.attributedTitle = NSAttributedString(
            string: "VibeBar",
            attributes: [
                .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
            ]
        )
        title.isEnabled = false
        menu.addItem(title)

        // 4pt spacer between title and subtitle
        let spacer = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        let spacerView = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 4))
        spacer.view = spacerView
        menu.addItem(spacer)

        let updated = DateFormatter.vibeBarClock.string(from: summary.updatedAt)
        let subtitle = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        subtitle.attributedTitle = NSAttributedString(
            string: L10n.shared.string(.menuSubtitleFmt, summary.total, updated),
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        subtitle.isEnabled = false
        menu.addItem(subtitle)
        menu.addItem(.separator())

        if sessions.isEmpty {
            let empty = NSMenuItem(title: L10n.shared.string(.noSessions), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else if AppSettings.shared.groupSessionsByTool {
            addGroupedSessionItems(to: menu, sessions: sessions, now: summary.updatedAt)
        } else {
            for session in sessions.prefix(8) {
                let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
                let icon = toolIconImage(for: session.tool, size: CGSize(width: 16, height: 16))
                item.view = SessionMenuItemView(session: session, icon: icon, now: summary.updatedAt)
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        if AppSettings.shared.usageEnabled {
            addUsageMenuItem(to: menu)
            menu.addItem(.separator())
        }

        let settings = NSMenuItem(title: L10n.shared.string(.settings), action: #selector(onSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let about = NSMenuItem(title: L10n.shared.string(.aboutVibeBar), action: #selector(onAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let quit = NSMenuItem(title: L10n.shared.string(.quitVibeBar), action: #selector(onQuit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    /// Load tool icon image for NSMenuItem
    private func toolIconImage(for tool: ToolKind, size: CGSize) -> NSImage? {
        guard let image = ToolIconLoader.icon(for: tool) else { return nil }
        image.size = size
        return image
    }


    // MARK: - Grouped Session Items

    private func addGroupedSessionItems(to menu: NSMenu, sessions: [SessionSnapshot], now: Date) {
        // Group sessions by tool
        var groups: [ToolKind: [SessionSnapshot]] = [:]
        for session in sessions {
            groups[session.tool, default: []].append(session)
        }

        // Sort by ToolKind.allCases order
        let orderedGroups = ToolKind.allCases.compactMap { tool -> (tool: ToolKind, sessions: [SessionSnapshot])? in
            guard let toolSessions = groups[tool], !toolSessions.isEmpty else { return nil }
            return (tool, toolSessions)
        }

        for (index, group) in orderedGroups.enumerated() {
            // Add group header
            let headerItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            let headerView = GroupHeaderMenuItemView(
                tool: group.tool,
                sessionCount: group.sessions.count,
                states: group.sessions.map { $0.status }
            )
            headerItem.view = headerView
            menu.addItem(headerItem)

            // Add sessions for this group (max 5 per group)
            for session in group.sessions.prefix(5) {
                let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
                let icon = toolIconImage(for: session.tool, size: CGSize(width: 16, height: 16))
                item.view = SessionMenuItemView(session: session, icon: icon, now: now, isGrouped: true)
                menu.addItem(item)
            }

            // Add spacer between groups (except after last group)
            if index < orderedGroups.count - 1 {
                let spacer = NSMenuItem(title: "", action: nil, keyEquivalent: "")
                let spacerView = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 6))
                spacer.view = spacerView
                menu.addItem(spacer)
            }
        }
    }

    private func displayDirectory(for session: SessionSnapshot) -> String {
        guard let cwd = session.cwd, !cwd.isEmpty else {
            return L10n.shared.string(.dirUnknown)
        }

        let abbreviated = (cwd as NSString).abbreviatingWithTildeInPath
        if abbreviated.count <= 70 {
            return abbreviated
        }
        return "…" + abbreviated.suffix(69)
    }

    private func addUsageMenuItem(to menu: NSMenu) {
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        let hostingView = NSHostingView(
            rootView: UsageMenuSectionView(
                snapshot: usageModel.snapshot,
                isRefreshing: usageModel.isRefreshing,
                isRebuilding: usageModel.isRebuilding
            ) { [weak self] in
                self?.openUsageSettings()
            }
        )
        hostingView.frame = NSRect(origin: .zero, size: hostingView.fittingSize)
        item.view = hostingView
        menu.addItem(item)
    }

    // MARK: - Plugin Menu Items

    private func addPluginMenuItem(to menu: NSMenu, tool: ToolKind, status: PluginInstallStatus) {
        let l10n = L10n.shared
        let displayName = tool.displayName
        let baseToolTip = pluginTooltip(for: tool)
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")

        switch status {
        case .installed:
            let version = model.bundledPluginVersion(for: tool)
            let view = ClickableMenuItemView(
                attributedTitle: attributedPluginInstalledLine(displayName, version: version),
                toolTip: baseToolTip
            ) { [weak self] in
                self?.model.uninstallPlugin(tool: tool)
            }
            item.view = view

        case .updateAvailable(let installed, let bundled):
            let (attrString, actions) = attributedPluginUpdateLine(
                displayName, installed: "v\(installed)", bundled: "v\(bundled)",
                onUpdate: { [weak self] in self?.model.updatePlugin(tool: tool) },
                onUninstall: { [weak self] in self?.model.uninstallPlugin(tool: tool) }
            )
            let view = MultiActionMenuItemView(attributedTitle: attrString, actions: actions, toolTip: baseToolTip)
            item.view = view

        case .notInstalled:
            let view = ClickableMenuItemView(
                attributedTitle: attributedPluginInstallLine(displayName),
                toolTip: baseToolTip
            ) { [weak self] in
                self?.model.installPlugin(tool: tool)
            }
            item.view = view

        case .installing:
            item.view = StaticMenuItemView(
                attributedTitle: attributedStatusLine("  \(displayName): \(l10n.string(.pluginInstalling))"),
                toolTip: baseToolTip
            )

        case .installFailed(let message):
            let view = ClickableMenuItemView(
                attributedTitle: attributedPluginFailedLine(
                    displayName,
                    verb: l10n.string(.pluginInstall),
                    action: l10n.string(.pluginRetry)
                ),
                toolTip: "\(baseToolTip)\n\(message)"
            ) { [weak self] in
                self?.model.installPlugin(tool: tool)
            }
            item.view = view

        case .uninstalling:
            item.view = StaticMenuItemView(
                attributedTitle: attributedStatusLine("  \(displayName): \(l10n.string(.pluginUninstalling))"),
                toolTip: baseToolTip
            )

        case .uninstallFailed(let message):
            let view = ClickableMenuItemView(
                attributedTitle: attributedPluginFailedLine(
                    displayName,
                    verb: l10n.string(.pluginUninstall),
                    action: l10n.string(.pluginRetryUninstall)
                ),
                toolTip: "\(baseToolTip)\n\(message)"
            ) { [weak self] in
                self?.model.uninstallPlugin(tool: tool)
            }
            item.view = view

        case .checking:
            item.view = StaticMenuItemView(
                attributedTitle: attributedStatusLine("  \(displayName): \(l10n.string(.pluginChecking))"),
                toolTip: baseToolTip
            )

        case .cliNotFound:
            item.view = StaticMenuItemView(
                attributedTitle: attributedStatusLine("  \(displayName): \(l10n.string(.pluginCliNotFoundFmt, tool.executable))"),
                toolTip: baseToolTip
            )

        case .updating:
            item.view = StaticMenuItemView(
                attributedTitle: attributedStatusLine("  \(displayName): \(l10n.string(.pluginUpdating))"),
                toolTip: baseToolTip
            )

        case .updateFailed(let message):
            let view = ClickableMenuItemView(
                attributedTitle: attributedPluginFailedLine(
                    displayName,
                    verb: l10n.string(.pluginUpdate),
                    action: l10n.string(.pluginRetry)
                ),
                toolTip: "\(baseToolTip)\n\(message)"
            ) { [weak self] in
                self?.model.updatePlugin(tool: tool)
            }
            item.view = view
        }

        menu.addItem(item)
    }

    private func addWrapperMenuItem(to menu: NSMenu, status: WrapperCommandUIStatus) {
        let l10n = L10n.shared
        let displayName = l10n.string(.wrapperCommandDisplayName)
        let baseToolTip = l10n.string(.wrapperCommandDesc)
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")

        switch status {
        case .checking:
            item.view = StaticMenuItemView(
                attributedTitle: attributedStatusLine("  \(displayName): \(l10n.string(.wrapperCommandChecking))"),
                toolTip: baseToolTip
            )

        case .notInstalled:
            let view = ClickableMenuItemView(
                attributedTitle: attributedWrapperInstallLine(displayName),
                toolTip: baseToolTip
            ) { [weak self] in
                self?.wrapperCommandModel.installCommand()
            }
            item.view = view

        case .installedManaged(let path, let version):
            let view = ClickableMenuItemView(
                attributedTitle: attributedWrapperInstalledLine(displayName, version: version),
                toolTip: [
                    baseToolTip,
                    l10n.string(.wrapperCommandPathFmt, path),
                    version.map { "v\($0)" },
                ].compactMap { $0 }.joined(separator: "\n")
            ) { [weak self] in
                self?.wrapperCommandModel.uninstallCommand()
            }
            item.view = view

        case .updateAvailable(let path, let installedVersion, let bundledVersion):
            let (attrString, actions) = attributedWrapperUpdateLine(
                displayName,
                installedVersion: installedVersion,
                bundledVersion: bundledVersion,
                onUpdate: { [weak self] in self?.wrapperCommandModel.updateCommand() },
                onUninstall: { [weak self] in self?.wrapperCommandModel.uninstallCommand() }
            )
            let view = MultiActionMenuItemView(
                attributedTitle: attrString,
                actions: actions,
                toolTip: [
                    baseToolTip,
                    l10n.string(.wrapperCommandPathFmt, path),
                    "v\(installedVersion)→v\(bundledVersion)",
                ].joined(separator: "\n")
            )
            item.view = view

        case .installedExternal(let path):
            item.view = StaticMenuItemView(
                attributedTitle: attributedStatusLine("  \(displayName): \(l10n.string(.wrapperCommandInstalledExternal))"),
                toolTip: [
                    baseToolTip,
                    l10n.string(.wrapperCommandPathFmt, path),
                    l10n.string(.wrapperCommandExternalHint),
                ].joined(separator: "\n")
            )

        case .installing:
            item.view = StaticMenuItemView(
                attributedTitle: attributedStatusLine("  \(displayName): \(l10n.string(.wrapperCommandInstalling))"),
                toolTip: baseToolTip
            )

        case .uninstalling:
            item.view = StaticMenuItemView(
                attributedTitle: attributedStatusLine("  \(displayName): \(l10n.string(.wrapperCommandUninstalling))"),
                toolTip: baseToolTip
            )

        case .updating:
            item.view = StaticMenuItemView(
                attributedTitle: attributedStatusLine("  \(displayName): \(l10n.string(.wrapperCommandUpdating))"),
                toolTip: baseToolTip
            )

        case .installFailed(let message):
            let view = ClickableMenuItemView(
                attributedTitle: attributedPluginFailedLine(
                    displayName,
                    verb: l10n.string(.pluginInstall),
                    action: l10n.string(.wrapperCommandRetry)
                ),
                toolTip: "\(baseToolTip)\n\(message)"
            ) { [weak self] in
                self?.wrapperCommandModel.installCommand()
            }
            item.view = view

        case .uninstallFailed(let message):
            let view = ClickableMenuItemView(
                attributedTitle: attributedPluginFailedLine(
                    displayName,
                    verb: l10n.string(.pluginUninstall),
                    action: l10n.string(.wrapperCommandRetry)
                ),
                toolTip: "\(baseToolTip)\n\(message)"
            ) { [weak self] in
                self?.wrapperCommandModel.uninstallCommand()
            }
            item.view = view

        case .updateFailed(let message):
            let view = ClickableMenuItemView(
                attributedTitle: attributedPluginFailedLine(
                    displayName,
                    verb: l10n.string(.pluginUpdate),
                    action: l10n.string(.wrapperCommandRetry)
                ),
                toolTip: "\(baseToolTip)\n\(message)"
            ) { [weak self] in
                self?.wrapperCommandModel.updateCommand()
            }
            item.view = view
        }

        menu.addItem(item)
    }

    private func pluginTooltip(for tool: ToolKind) -> String {
        let l10n = L10n.shared
        switch tool {
        case .claudeCode:
            return l10n.string(.pluginClaudeDesc)
        case .opencode:
            return l10n.string(.pluginOpenCodeDesc)
        default:
            return ""
        }
    }

    private func promptPluginUpdateIfNeeded(pluginStatus: PluginStatusReport) {
        guard !didHandleStartupPluginUpdatePrompt else { return }
        guard pluginStatus.claudeCode != .checking,
              pluginStatus.opencode != .checking
        else { return }

        didHandleStartupPluginUpdatePrompt = true
        guard AppSettings.shared.autoCheckUpdates else { return }

        for (tool, status) in pluginStatus.visibleItems {
            guard case .updateAvailable(let installed, let bundled) = status else { continue }
            guard model.shouldPromptForPluginUpdate(tool: tool, version: bundled) else { continue }
            model.markPluginUpdatePrompted(tool: tool, version: bundled)
            showPluginUpdateAlert(tool: tool, installed: installed, bundled: bundled)
            break
        }
    }

    private func showPluginUpdateAlert(tool: ToolKind, installed: String, bundled: String) {
        let l10n = L10n.shared
        let alert = NSAlert()
        alert.messageText = l10n.string(.pluginUpdatePromptTitleFmt, tool.displayName, "v\(bundled)")
        alert.informativeText = l10n.string(
            .pluginUpdatePromptInfoFmt,
            "v\(installed)",
            "v\(bundled)"
        )
        alert.alertStyle = .informational
        alert.addButton(withTitle: l10n.string(.pluginUpdateNow))
        alert.addButton(withTitle: l10n.string(.pluginSkipVersion))

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            model.updatePlugin(tool: tool)
            return
        }
        if response == .alertSecondButtonReturn {
            model.skipPluginVersion(tool: tool, version: bundled)
        }
    }

    // MARK: - Plugin Attributed Strings

    private func attributedStatusLine(_ text: String) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.labelColor,
            ]
        )
    }

    private func attributedPluginInstallLine(_ name: String) -> NSAttributedString {
        let prefix = "  \(name): \(L10n.shared.string(.pluginNotInstalled))"
        let action = L10n.shared.string(.pluginInstall)
        let tabAndAction = "\t" + action
        let full = prefix + tabAndAction

        let para = NSMutableParagraphStyle()
        let rightTab = NSTextTab(textAlignment: .right, location: 280)
        para.tabStops = [rightTab]

        let attributed = NSMutableAttributedString(
            string: full,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: para,
            ]
        )
        let actionStart = prefix.count
        attributed.addAttributes(
            [
                .foregroundColor: NSColor.systemBlue,
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium),
            ],
            range: NSRange(location: actionStart, length: tabAndAction.count)
        )
        return attributed
    }

    private func attributedWrapperInstallLine(_ name: String) -> NSAttributedString {
        let prefix = "  \(name): \(L10n.shared.string(.wrapperCommandNotInstalled))"
        let action = L10n.shared.string(.pluginInstall)
        let tabAndAction = "\t" + action
        let full = prefix + tabAndAction

        let para = NSMutableParagraphStyle()
        let rightTab = NSTextTab(textAlignment: .right, location: 280)
        para.tabStops = [rightTab]

        let attributed = NSMutableAttributedString(
            string: full,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: para,
            ]
        )
        let actionStart = prefix.count
        attributed.addAttributes(
            [
                .foregroundColor: NSColor.systemBlue,
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium),
            ],
            range: NSRange(location: actionStart, length: tabAndAction.count)
        )
        return attributed
    }

    private func attributedWrapperInstalledLine(_ name: String, version: String?) -> NSAttributedString {
        let versionText = version.map { "v\($0)" } ?? ""
        let namePrefix = "  \(name)"
        let versionPart = "  \(versionText)"
        let tabAndAction = "\t" + L10n.shared.string(.pluginUninstall)
        let full = namePrefix + versionPart + tabAndAction

        let para = NSMutableParagraphStyle()
        let rightTab = NSTextTab(textAlignment: .right, location: 280)
        para.tabStops = [rightTab]

        let attributed = NSMutableAttributedString(
            string: full,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: para,
            ]
        )
        // Version text in gray
        attributed.addAttributes(
            [
                .foregroundColor: NSColor.secondaryLabelColor,
            ],
            range: NSRange(location: namePrefix.count, length: versionPart.count)
        )
        // Uninstall action in blue
        let actionStart = namePrefix.count + versionPart.count
        attributed.addAttributes(
            [
                .foregroundColor: NSColor.systemBlue,
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium),
            ],
            range: NSRange(location: actionStart, length: tabAndAction.count)
        )
        return attributed
    }

    private func attributedWrapperUpdateLine(
        _ name: String,
        installedVersion: String,
        bundledVersion: String,
        onUpdate: @escaping () -> Void,
        onUninstall: @escaping () -> Void
    ) -> (NSAttributedString, [MultiActionMenuItemView.Action]) {
        attributedPluginUpdateLine(
            name,
            installed: "v\(installedVersion)",
            bundled: "v\(bundledVersion)",
            onUpdate: onUpdate,
            onUninstall: onUninstall
        )
    }

    private func attributedPluginInstalledLine(_ name: String, version: String?) -> NSAttributedString {
        let versionText = version.map { "v\($0)" } ?? ""
        let namePrefix = "  \(name)"
        let versionPart = "  \(versionText)"
        let tabAndAction = "\t" + L10n.shared.string(.pluginUninstall)
        let full = namePrefix + versionPart + tabAndAction

        let para = NSMutableParagraphStyle()
        let rightTab = NSTextTab(textAlignment: .right, location: 280)
        para.tabStops = [rightTab]

        let attributed = NSMutableAttributedString(
            string: full,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: para,
            ]
        )
        // Version text in gray
        attributed.addAttributes(
            [
                .foregroundColor: NSColor.secondaryLabelColor,
            ],
            range: NSRange(location: namePrefix.count, length: versionPart.count)
        )
        // Uninstall action in blue
        let actionStart = namePrefix.count + versionPart.count
        attributed.addAttributes(
            [
                .foregroundColor: NSColor.systemBlue,
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium),
            ],
            range: NSRange(location: actionStart, length: tabAndAction.count)
        )
        return attributed
    }

    private func attributedPluginUpdateLine(
        _ name: String, installed: String, bundled: String,
        onUpdate: @escaping () -> Void,
        onUninstall: @escaping () -> Void
    ) -> (NSAttributedString, [MultiActionMenuItemView.Action]) {
        let namePrefix = "  \(name)"
        let versionPart = "  \(installed)→\(bundled)"
        let tabAndActions = "\t" + L10n.shared.string(.pluginUpdate) + " · " + L10n.shared.string(.pluginUninstall)
        let full = namePrefix + versionPart + tabAndActions

        let para = NSMutableParagraphStyle()
        let rightTab = NSTextTab(textAlignment: .right, location: 280)
        para.tabStops = [rightTab]

        let attributed = NSMutableAttributedString(
            string: full,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: para,
            ]
        )

        // Version text in gray
        attributed.addAttributes(
            [
                .foregroundColor: NSColor.secondaryLabelColor,
            ],
            range: NSRange(location: namePrefix.count, length: versionPart.count)
        )

        let updateAction = L10n.shared.string(.pluginUpdate)
        let separator = " · "
        let uninstallAction = L10n.shared.string(.pluginUninstall)
        let updateStart = namePrefix.count + versionPart.count + 1 // +1 for tab
        let updateRange = NSRange(location: updateStart, length: updateAction.count)
        attributed.addAttributes(
            [
                .foregroundColor: NSColor.systemBlue,
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium),
            ],
            range: updateRange
        )

        let uninstallStart = updateStart + updateAction.count + separator.count
        let uninstallRange = NSRange(location: uninstallStart, length: uninstallAction.count)
        attributed.addAttributes(
            [
                .foregroundColor: NSColor.systemBlue,
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium),
            ],
            range: uninstallRange
        )

        let actions: [MultiActionMenuItemView.Action] = [
            .init(range: updateRange, callback: onUpdate),
            .init(range: uninstallRange, callback: onUninstall),
        ]

        return (attributed, actions)
    }

    private func attributedPluginFailedLine(_ name: String, verb: String, action: String) -> NSAttributedString {
        let prefix = "  \(name): \(L10n.shared.string(.pluginFailedFmt, verb)) — "
        let full = prefix + action
        let attributed = NSMutableAttributedString(
            string: full,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.labelColor,
            ]
        )
        attributed.addAttributes(
            [
                .foregroundColor: NSColor.systemRed,
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium),
            ],
            range: NSRange(location: prefix.count, length: action.count)
        )
        return attributed
    }

    @objc
    private func onNoop() {}

    @objc
    private func onQuit() {
        NSApp.terminate(nil)
    }

    @objc
    private func onSettings() {
        SettingsWindowController.shared.showSettings(tab: .general)
    }

    private func openUsageSettings() {
        menu.cancelTracking()
        SettingsWindowController.shared.showSettings(tab: .usage)
    }

    @objc
    private func onAbout() {
        SettingsWindowController.shared.showSettings(tab: .about)
    }

    private func postLaunchCheck() {
        if statusItem.button == nil {
            fputs(L10n.shared.string(.consoleStatusBarUnavail), stderr)
        }
    }
}

extension StatusItemController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        rebuildMenuItems(
            summary: model.summary,
            sessions: model.sessions,
            pluginStatus: model.pluginStatus,
            wrapperStatus: wrapperCommandModel.status
        )
        // Pause auto-refresh while menu is open to prevent flickering
        model.pauseRefresh()
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        MenuItemTooltipController.shared.hide(for: nil)
        // Resume auto-refresh when menu closes
        model.resumeRefresh()
    }
}

extension StatusItemController: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        let userInfo = response.notification.request.content.userInfo
        guard let action = userInfo["action"] as? String,
              action == NotificationConstants.openMenuAction else { return }

        Task { @MainActor [weak self] in
            self?.openMenuFromNotification()
        }
    }
}

@MainActor
enum StatusImageRenderer {
    private enum RenderContext {
        case menuBar
        case settingsSidebar
        case preview
    }

    private static let segmentThreshold = 8
    private static let lineWidth: CGFloat = 2.8
    private static let gapDegrees: Double = 8.0
    private static var renderContext: RenderContext = .menuBar

    // MARK: - Entry point

    static func render(summary: GlobalSummary, style: IconStyle) -> NSImage {
        withRenderContext(.menuBar) {
            switch style {
            case .ring:      return renderRing(summary: summary)
            case .particles: return renderParticles(summary: summary)
            case .energyBar: return renderEnergyBar(summary: summary)
            case .iceGrid:   return renderIceGrid(summary: summary)
            }
        }
    }

    static func renderSidebar(summary: GlobalSummary, style: IconStyle) -> NSImage {
        withRenderContext(.settingsSidebar) {
            switch style {
            case .ring:      return renderRing(summary: summary)
            case .particles: return renderParticles(summary: summary)
            case .energyBar: return renderEnergyBar(summary: summary)
            case .iceGrid:   return renderIceGrid(summary: summary)
            }
        }
    }

    // MARK: - Preview renderer

    static func renderPreview(style: IconStyle, previewSize: CGFloat = 48) -> NSImage {
        withRenderContext(.preview) {
            let sample = GlobalSummary(
                total: 3,
                counts: [.running: 1, .awaitingInput: 1, .idle: 1],
                byTool: [:], updatedAt: Date()
            )

            let scale = previewSize / 18.0
            let image = NSImage(size: NSSize(width: previewSize, height: previewSize))
            image.lockFocus()

            let transform = NSAffineTransform()
            transform.scale(by: scale)
            transform.concat()

            switch style {
            case .ring:      drawRing(summary: sample)
            case .particles: drawParticles(summary: sample)
            case .energyBar: drawEnergyBar(summary: sample)
            case .iceGrid:   drawIceGrid(summary: sample)
            }

            image.unlockFocus()
            image.isTemplate = false
            return image
        }
    }

    // MARK: - Shared: center number

    private static func drawCenterNumber(summary: GlobalSummary, center: NSPoint) {
        let text = "\(min(summary.total, 99))"
        let measurementAttrs: [NSAttributedString.Key: Any] = [
            .font: numberFont,
        ]
        let textSize = text.size(withAttributes: measurementAttrs)
        let textRect = NSRect(
            x: center.x - textSize.width / 2,
            y: center.y - textSize.height / 2,
            width: textSize.width,
            height: textSize.height
        )
        drawCountText(text, in: textRect)
    }

    // MARK: - Ring renderer (original)

    private static func drawRing(summary: GlobalSummary) {
        let rect = NSRect(origin: .zero, size: NSSize(width: 18, height: 18))
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * 0.5 - 1.6

        let baseColor: NSColor = summary.total > 0
            ? neutralColor(menuBarAlpha: 0.30, sidebarAlpha: 0.34, previewAlpha: 0.34)
            : neutralColor(menuBarAlpha: 0.72, sidebarAlpha: 0.56, previewAlpha: 0.56)

        strokeArc(
            center: center,
            radius: radius,
            startFraction: 0,
            endFraction: 1,
            color: baseColor,
            lineWidth: lineWidth,
            cap: .round
        )

        if summary.total > 0 {
            let segments = expandSegments(from: summary.counts)
            if segments.count <= segmentThreshold {
                drawSegmentedRing(center: center, radius: radius, segments: segments)
            } else {
                drawContinuousRing(center: center, radius: radius, summary: summary)
            }
        }

        drawCenterNumber(summary: summary, center: center)
    }

    private static func renderRing(summary: GlobalSummary) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        drawRing(summary: summary)
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    // MARK: - Particles renderer

    private static func drawParticles(summary: GlobalSummary) {
        let rect = NSRect(origin: .zero, size: NSSize(width: 18, height: 18))
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * 0.5 - 2.0

        // Faint orbit circle
        let orbitColor = neutralColor(menuBarAlpha: 0.25, sidebarAlpha: 0.34, previewAlpha: 0.34)
        strokeArc(
            center: center,
            radius: radius,
            startFraction: 0,
            endFraction: 1,
            color: orbitColor,
            lineWidth: 0.9,
            cap: .round
        )

        if summary.total > 0 {
            let maxParticleSlots = 6
            let segments: [ToolActivityState]
            if summary.total <= maxParticleSlots {
                segments = expandSegments(from: summary.counts)
            } else {
                // Fixed positions, proportionally assigned
                segments = distributeToSlots(counts: summary.counts, slots: maxParticleSlots)
            }

            let n = segments.count
            for i in 0..<n {
                // Angle from 12 o'clock, clockwise
                let angle = (Double(i) / Double(n)) * 2.0 * .pi - .pi / 2.0
                let px = center.x + CGFloat(cos(angle)) * radius
                let py = center.y + CGFloat(sin(angle)) * radius
                let color = StatusColors.activity(segments[i])

                // Outer glow
                let glowRect = NSRect(x: px - 3, y: py - 3, width: 6, height: 6)
                let glowColor = color.withAlphaComponent(0.35)
                glowColor.setFill()
                NSBezierPath(ovalIn: glowRect).fill()

                // Inner core
                let coreRect = NSRect(x: px - 1.5, y: py - 1.5, width: 3, height: 3)
                color.setFill()
                NSBezierPath(ovalIn: coreRect).fill()
            }
        }

        drawCenterNumber(summary: summary, center: center)
    }

    private static func renderParticles(summary: GlobalSummary) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        drawParticles(summary: summary)
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    // MARK: - Energy Bar renderer

    private static func drawEnergyBar(summary: GlobalSummary) {
        let iconSize: CGFloat = 18
        let numberRegionWidth: CGFloat = 10

        // Left side: number
        let numberText = "\(min(summary.total, 99))"
        let measurementAttrs: [NSAttributedString.Key: Any] = [
            .font: numberFont,
        ]
        let numberSize = numberText.size(withAttributes: measurementAttrs)
        let numberRect = NSRect(
            x: (numberRegionWidth - numberSize.width) / 2,
            y: (iconSize - numberSize.height) / 2,
            width: numberSize.width,
            height: numberSize.height
        )
        drawCountText(numberText, in: numberRect)

        // Right side: stacked color blocks
        let blockWidth: CGFloat = 4
        let blockHeight: CGFloat = 3
        let blockSpacing: CGFloat = 1
        let maxBlocks = 5
        let rightX = numberRegionWidth + 1

        let segments: [ToolActivityState]
        if summary.total == 0 {
            // Empty state: show 3 placeholder bars
            let placeholderCount = 3
            let totalHeight = CGFloat(placeholderCount) * blockHeight + CGFloat(placeholderCount - 1) * blockSpacing
            let startY = (iconSize - totalHeight) / 2
            let placeholderColor = neutralColor(menuBarAlpha: 0.25, sidebarAlpha: 0.34, previewAlpha: 0.34)

            for i in 0..<placeholderCount {
                let y = startY + CGFloat(i) * (blockHeight + blockSpacing)
                let placeholderRect = NSRect(x: rightX, y: y, width: blockWidth, height: blockHeight)
                placeholderColor.setFill()
                NSBezierPath(roundedRect: placeholderRect, xRadius: 1, yRadius: 1).fill()
            }
            return
        } else if summary.total <= maxBlocks {
            segments = expandSegments(from: summary.counts)
        } else {
            segments = distributeToSlots(counts: summary.counts, slots: maxBlocks)
        }

        let blockCount = segments.count
        if blockCount > 0 {
            let totalHeight = CGFloat(blockCount) * blockHeight + CGFloat(blockCount - 1) * blockSpacing
            let startY = (iconSize - totalHeight) / 2

            for i in 0..<blockCount {
                let color = StatusColors.activity(segments[i])
                let y = startY + CGFloat(i) * (blockHeight + blockSpacing)
                let blockRect = NSRect(x: rightX, y: y, width: blockWidth, height: blockHeight)

                // Glow pass (expand 1pt)
                let glowRect = blockRect.insetBy(dx: -1, dy: -1)
                let glowColor = color.withAlphaComponent(0.30)
                glowColor.setFill()
                NSBezierPath(roundedRect: glowRect, xRadius: 1.5, yRadius: 1.5).fill()

                // Solid block
                color.setFill()
                NSBezierPath(roundedRect: blockRect, xRadius: 1, yRadius: 1).fill()
            }
        }
    }

    private static func renderEnergyBar(summary: GlobalSummary) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        drawEnergyBar(summary: summary)
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    // MARK: - Ice Grid renderer

    private static func drawIceGrid(summary: GlobalSummary) {
        let cellSize: CGFloat = 6
        let gap: CGFloat = 2
        let padding: CGFloat = 2
        let maxSlots = 10  // 5 columns x 2 rows
        let height: CGFloat = 18

        // Empty state
        if summary.total == 0 {
            let width: CGFloat = 18
            // 2x2 ghost grid
            let ghostColor = neutralColor(menuBarAlpha: 0.30, sidebarAlpha: 0.36, previewAlpha: 0.36)
            let ghostCols = 2
            let ghostRows = 2
            let gridW = CGFloat(ghostCols) * cellSize + CGFloat(ghostCols - 1) * gap
            let gridH = CGFloat(ghostRows) * cellSize + CGFloat(ghostRows - 1) * gap
            let originX = (width - gridW) / 2
            let originY = (height - gridH) / 2

            for col in 0..<ghostCols {
                for row in 0..<ghostRows {
                    let x = originX + CGFloat(col) * (cellSize + gap)
                    let y = originY + CGFloat(row) * (cellSize + gap)
                    let rect = NSRect(x: x, y: y, width: cellSize, height: cellSize)
                    ghostColor.setFill()
                    NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5).fill()
                }
            }

            // Center "0"
            let center = NSPoint(x: width / 2, y: height / 2)
            drawCenterNumber(summary: summary, center: center)
            return
        }

        // Active state
        let segments: [ToolActivityState]
        if summary.total <= maxSlots {
            segments = expandSegments(from: summary.counts)
        } else {
            segments = distributeToSlots(counts: summary.counts, slots: maxSlots)
        }

        let count = segments.count
        let rows = count == 1 ? 1 : 2

        let gridH = CGFloat(rows) * cellSize + CGFloat(max(rows - 1, 0)) * gap
        let originY = (height - gridH) / 2

        // Fill column-first: top-to-bottom, left-to-right
        for i in 0..<count {
            let col = i / rows
            let row = i % rows
            let x = padding + CGFloat(col) * (cellSize + gap)
            let y = originY + CGFloat(row) * (cellSize + gap)
            let cellRect = NSRect(x: x, y: y, width: cellSize, height: cellSize)
            let color = StatusColors.activity(segments[i])

            // Layer 1: outer glow (expand 2px, 15% alpha)
            let outerGlow = cellRect.insetBy(dx: -2, dy: -2)
            color.withAlphaComponent(0.15).setFill()
            NSBezierPath(roundedRect: outerGlow, xRadius: 2.5, yRadius: 2.5).fill()

            // Layer 2: inner glow (expand 1px, 35% alpha)
            let innerGlow = cellRect.insetBy(dx: -1, dy: -1)
            color.withAlphaComponent(0.35).setFill()
            NSBezierPath(roundedRect: innerGlow, xRadius: 2, yRadius: 2).fill()

            // Layer 3: solid fill (100%)
            color.setFill()
            NSBezierPath(roundedRect: cellRect, xRadius: 1.5, yRadius: 1.5).fill()

            // Layer 4: highlight (top 2px strip, white 20%)
            let highlightRect = NSRect(x: cellRect.minX, y: cellRect.maxY - 2,
                                       width: cellRect.width, height: 2)
            neutralHighlightColor().setFill()
            NSBezierPath(roundedRect: highlightRect, xRadius: 1, yRadius: 1).fill()
        }
    }

    private static func renderIceGrid(summary: GlobalSummary) -> NSImage {
        let cellSize: CGFloat = 6
        let gap: CGFloat = 2
        let padding: CGFloat = 2
        let height: CGFloat = 18

        let width: CGFloat
        if summary.total == 0 {
            width = 18
        } else {
            let maxSlots = 10
            let count = min(summary.total, maxSlots)
            let rows = count == 1 ? 1 : 2
            let cols = (count + rows - 1) / rows
            width = padding * 2 + CGFloat(cols) * cellSize + CGFloat(max(cols - 1, 0)) * gap
        }

        let size = NSSize(width: width, height: height)
        let image = NSImage(size: size)
        image.lockFocus()
        drawIceGrid(summary: summary)
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    // MARK: - Proportional slot distribution

    private static func distributeToSlots(counts: [ToolActivityState: Int], slots: Int) -> [ToolActivityState] {
        let order: [ToolActivityState] = [.running, .awaitingInput, .idle, .unknown]
        let total = counts.values.reduce(0, +)
        guard total > 0 else { return [] }

        var result: [ToolActivityState] = []
        var remaining = slots

        for (index, state) in order.enumerated() {
            let count = counts[state, default: 0]
            guard count > 0 else { continue }

            if index == order.count - 1 || remaining <= 0 {
                // Last state gets whatever remains
                if remaining > 0 {
                    result.append(contentsOf: Array(repeating: state, count: remaining))
                }
                break
            }

            let proportion = Double(count) / Double(total)
            var slotCount = Int(round(proportion * Double(slots)))
            slotCount = max(slotCount, 1) // At least 1 slot if count > 0
            slotCount = min(slotCount, remaining)
            result.append(contentsOf: Array(repeating: state, count: slotCount))
            remaining -= slotCount
        }

        // Fill any remaining slots with the dominant state
        while result.count < slots {
            let dominant = order.first { counts[$0, default: 0] > 0 } ?? .unknown
            result.append(dominant)
        }

        return Array(result.prefix(slots))
    }

    // MARK: - Segment expansion

    private static func expandSegments(from counts: [ToolActivityState: Int]) -> [ToolActivityState] {
        let order: [ToolActivityState] = [.running, .awaitingInput, .idle, .unknown]
        var segments: [ToolActivityState] = []
        for state in order {
            let count = counts[state, default: 0]
            segments.append(contentsOf: Array(repeating: state, count: count))
        }
        return segments
    }

    // MARK: - Segmented ring (N <= 8)

    private static func drawSegmentedRing(
        center: NSPoint,
        radius: CGFloat,
        segments: [ToolActivityState]
    ) {
        let n = segments.count
        guard n > 0 else { return }

        if n == 1 {
            let color = StatusColors.activity(segments[0])
            strokeArc(center: center, radius: radius,
                       startFraction: 0, endFraction: 1,
                       color: color, lineWidth: lineWidth, cap: .round)
            return
        }

        let totalGap = Double(n) * gapDegrees
        let arcDegrees = (360.0 - totalGap) / Double(n)
        let halfGap = gapDegrees / 2.0
        let highlightRatio = 0.3

        for i in 0..<n {
            let segStart = Double(i) * (arcDegrees + gapDegrees) + halfGap
            let segEnd = segStart + arcDegrees
            let color = StatusColors.activity(segments[i])

            // Base color pass — full segment
            strokeArcDegrees(center: center, radius: radius,
                             startDeg: segStart - 90, endDeg: segEnd - 90,
                             color: color, lineWidth: lineWidth, cap: .butt)

            // Highlight pass — leading 30% of the arc
            let highlightEnd = segStart + arcDegrees * highlightRatio
            let bright = color.blended(withFraction: 0.25, of: .white) ?? color
            strokeArcDegrees(center: center, radius: radius,
                             startDeg: segStart - 90, endDeg: highlightEnd - 90,
                             color: bright, lineWidth: lineWidth, cap: .butt)
        }
    }

    // MARK: - Continuous ring (N > 8, original behavior)

    private static func drawContinuousRing(
        center: NSPoint,
        radius: CGFloat,
        summary: GlobalSummary
    ) {
        let order: [ToolActivityState] = [.running, .awaitingInput, .idle]
        var current = 0.0
        for state in order {
            let count = summary.counts[state, default: 0]
            guard count > 0 else { continue }
            let fraction = Double(count) / Double(summary.total)
            let next = current + fraction
            strokeArc(
                center: center,
                radius: radius,
                startFraction: current,
                endFraction: next,
                color: StatusColors.activity(state),
                lineWidth: lineWidth,
                cap: .round
            )
            current = next
        }
    }

    // MARK: - Arc helpers

    private static let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .bold)

    /// Draws count text based on render context:
    /// - menu bar: white (native monochrome style)
    /// - settings preview: labelColor (better contrast on light cards)
    private static func drawCountText(_ text: String, in rect: NSRect) {
        let textColor: NSColor = renderContext == .menuBar ? .white : .labelColor
        let attrs: [NSAttributedString.Key: Any] = [
            .font: numberFont,
            .foregroundColor: textColor,
        ]
        text.draw(in: rect, withAttributes: attrs)
    }

    private static func neutralColor(
        menuBarAlpha: CGFloat,
        sidebarAlpha: CGFloat,
        previewAlpha: CGFloat
    ) -> NSColor {
        switch renderContext {
        case .menuBar:
            return NSColor.white.withAlphaComponent(menuBarAlpha)
        case .settingsSidebar:
            return NSColor.secondaryLabelColor.withAlphaComponent(sidebarAlpha)
        case .preview:
            return NSColor.secondaryLabelColor.withAlphaComponent(previewAlpha)
        }
    }

    private static func neutralHighlightColor() -> NSColor {
        switch renderContext {
        case .menuBar:
            return NSColor.white.withAlphaComponent(0.20)
        case .settingsSidebar, .preview:
            return NSColor.labelColor.withAlphaComponent(0.14)
        }
    }

    private static func withRenderContext<T>(_ context: RenderContext, _ body: () -> T) -> T {
        let previous = renderContext
        renderContext = context
        defer { renderContext = previous }
        return body()
    }

    private static func strokeArc(
        center: NSPoint,
        radius: CGFloat,
        startFraction: Double,
        endFraction: Double,
        color: NSColor,
        lineWidth: CGFloat,
        cap: NSBezierPath.LineCapStyle
    ) {
        let start = CGFloat(startFraction * 360.0 - 90.0)
        let end = CGFloat(endFraction * 360.0 - 90.0)

        let path = NSBezierPath()
        path.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: end)
        path.lineWidth = lineWidth
        path.lineCapStyle = cap
        color.setStroke()
        path.stroke()
    }

    private static func strokeArcDegrees(
        center: NSPoint,
        radius: CGFloat,
        startDeg: Double,
        endDeg: Double,
        color: NSColor,
        lineWidth: CGFloat,
        cap: NSBezierPath.LineCapStyle
    ) {
        let path = NSBezierPath()
        path.appendArc(withCenter: center, radius: radius,
                       startAngle: CGFloat(startDeg), endAngle: CGFloat(endDeg))
        path.lineWidth = lineWidth
        path.lineCapStyle = cap
        color.setStroke()
        path.stroke()
    }

}

private extension DateFormatter {
    static let vibeBarClock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

// MARK: - Menu Tooltip

@MainActor
private final class MenuItemTooltipController {
    private enum Layout {
        static let maxTextWidth: CGFloat = 320
        static let horizontalPadding: CGFloat = 10
        static let verticalPadding: CGFloat = 6
        static let cornerRadius: CGFloat = 6
        static let borderWidth: CGFloat = 1
        static let screenInset: CGFloat = 6
        static let offsetX: CGFloat = 12
        static let showDelay: TimeInterval = 0.35
    }

    static let shared = MenuItemTooltipController()

    private let panel: NSPanel
    private let bubbleView: NSView
    private let label: NSTextField
    private var pendingWorkItem: DispatchWorkItem?
    private weak var ownerView: NSView?

    private init() {
        label = NSTextField(wrappingLabelWithString: "")
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = .labelColor
        label.backgroundColor = .clear
        label.isBordered = false
        label.drawsBackground = false
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping

        bubbleView = NSView(frame: .zero)
        bubbleView.wantsLayer = true
        bubbleView.layer?.cornerRadius = Layout.cornerRadius
        bubbleView.layer?.borderWidth = Layout.borderWidth
        bubbleView.layer?.borderColor = NSColor.separatorColor.cgColor
        bubbleView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        bubbleView.addSubview(label)

        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.transient, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = bubbleView
    }

    func show(text: String?, from view: NSView) {
        let content = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !content.isEmpty else {
            hide(for: view)
            return
        }

        pendingWorkItem?.cancel()
        ownerView = view

        if panel.isVisible {
            present(text: content, from: view)
            return
        }

        let work = DispatchWorkItem { [weak self, weak view] in
            guard let self, let view, self.ownerView === view else { return }
            self.present(text: content, from: view)
        }
        pendingWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Layout.showDelay, execute: work)
    }

    func hide(for view: NSView?) {
        if let view, ownerView !== view {
            return
        }
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
        ownerView = nil
        panel.orderOut(nil)
    }

    private func present(text: String, from view: NSView) {
        guard let window = view.window else { return }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
        ]
        let textBounds = (text as NSString).boundingRect(
            with: NSSize(width: Layout.maxTextWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        )
        let textWidth = ceil(textBounds.width)
        let textHeight = ceil(textBounds.height)
        let width = textWidth + Layout.horizontalPadding * 2
        let height = textHeight + Layout.verticalPadding * 2

        label.stringValue = text
        label.frame = NSRect(
            x: Layout.horizontalPadding,
            y: Layout.verticalPadding,
            width: textWidth,
            height: textHeight
        )
        bubbleView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        panel.setContentSize(NSSize(width: width, height: height))

        // Compute both candidate positions (right and left of the menu window)
        let rightAnchor = view.convert(NSPoint(x: view.bounds.maxX, y: view.bounds.midY), to: nil)
        let rightScreen = window.convertPoint(toScreen: rightAnchor)
        let rightX = rightScreen.x + Layout.offsetX

        let leftAnchor = view.convert(NSPoint(x: view.bounds.minX, y: view.bounds.midY), to: nil)
        let leftScreen = window.convertPoint(toScreen: leftAnchor)
        let leftX = leftScreen.x - Layout.offsetX - width

        let midY = rightScreen.y - height / 2

        let screen = window.screen ?? NSScreen.main
        let frame = screen?.visibleFrame

        // Prefer right side; fall back to left when the right side would overlap the menu
        // (i.e. when clamping would push the tooltip back onto the menu window)
        var screenPoint: NSPoint
        if let frame, rightX + width > frame.maxX - Layout.screenInset {
            screenPoint = NSPoint(x: max(leftX, frame.minX + Layout.screenInset), y: midY)
        } else {
            screenPoint = NSPoint(x: rightX, y: midY)
        }

        if let frame {
            if screenPoint.y + height > frame.maxY - Layout.screenInset {
                screenPoint.y = frame.maxY - height - Layout.screenInset
            }
            if screenPoint.y < frame.minY + Layout.screenInset {
                screenPoint.y = frame.minY + Layout.screenInset
            }
        }

        panel.setFrameOrigin(screenPoint)
        panel.orderFront(nil)
    }
}

// MARK: - Menu Item Views

@MainActor
private final class SessionMenuItemView: NSView {
    private let row1Label: NSTextField
    private let row2Label: NSTextField
    private let iconView: NSImageView
    private let originalRow1: NSAttributedString
    private let originalRow2: NSAttributedString
    private var isHighlighted = false
    private let itemHeight: CGFloat = 36
    private var hoverTrackingArea: NSTrackingArea?

    init(session: SessionSnapshot, icon: NSImage?, now: Date, isGrouped: Bool = false) {
        let statusColor = StatusColors.activity(session.status)
        let statusText = session.status.displayName
        let duration = SessionDurationFormatter.string(startedAt: session.startedAt, now: now)

        // Row 1: Tool name (if not grouped) + ● + status text + duration
        let row1 = NSMutableAttributedString()
        if !isGrouped {
            row1.append(NSAttributedString(
                string: session.tool.displayName + " ",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                    .foregroundColor: NSColor.labelColor,
                ]
            ))
        }
        row1.append(NSAttributedString(
            string: "● ",
            attributes: [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: statusColor,
            ]
        ))
        row1.append(NSAttributedString(
            string: statusText,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: statusColor,
            ]
        ))
        row1.append(NSAttributedString(
            string: " · \(duration)",
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        ))

        // Row 2: pid + directory
        let directory: String
        if let cwd = session.cwd, !cwd.isEmpty {
            let abbreviated = (cwd as NSString).abbreviatingWithTildeInPath
            directory = abbreviated.count <= 50 ? abbreviated : "…" + abbreviated.suffix(49)
        } else {
            directory = L10n.shared.string(.dirUnknown)
        }
        let row2 = NSAttributedString(
            string: "pid \(session.pid) · \(directory)",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )

        self.originalRow1 = row1
        self.originalRow2 = row2

        self.row1Label = NSTextField(labelWithAttributedString: row1)
        self.row2Label = NSTextField(labelWithAttributedString: row2)
        self.iconView = NSImageView()
        iconView.image = icon
        iconView.imageScaling = .scaleProportionallyUpOrDown

        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: itemHeight))

        let iconSize: CGFloat = 16
        let iconX: CGFloat = isGrouped ? 34 : 14  // More indent when grouped
        let textX: CGFloat = isGrouped ? iconX + 2 : iconX + iconSize + 6  // No icon when grouped
        let textWidth = frame.width - textX - 14

        if !isGrouped {
            iconView.frame = NSRect(x: iconX, y: (itemHeight - iconSize) / 2, width: iconSize, height: iconSize)
            addSubview(iconView)
        }

        row1Label.sizeToFit()
        let row1H = row1Label.frame.height
        row1Label.frame = NSRect(x: textX, y: itemHeight - row1H - 4, width: textWidth, height: row1H)
        addSubview(row1Label)

        row2Label.sizeToFit()
        let row2H = row2Label.frame.height
        row2Label.frame = NSRect(x: textX, y: 4, width: textWidth, height: row2H)
        addSubview(row2Label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 300, height: itemHeight)
    }

    override func mouseEntered(with event: NSEvent) {
        isHighlighted = true
        row1Label.attributedStringValue = whiteColoredString(originalRow1)
        row2Label.attributedStringValue = whiteColoredString(originalRow2)
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHighlighted = false
        row1Label.attributedStringValue = originalRow1
        row2Label.attributedStringValue = originalRow2
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHighlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        }
    }

    private func whiteColoredString(_ source: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: source)
        result.addAttribute(.foregroundColor, value: NSColor.white,
                            range: NSRange(location: 0, length: result.length))
        return result
    }
}

private final class StaticMenuItemView: NSView {
    private let label: NSTextField
    private let originalAttributedTitle: NSAttributedString
    private let tooltipText: String?
    private var isHighlighted = false
    private let itemHeight: CGFloat = 22
    private var hoverTrackingArea: NSTrackingArea?

    init(attributedTitle: NSAttributedString, toolTip: String?) {
        self.originalAttributedTitle = attributedTitle
        self.tooltipText = toolTip
        self.label = NSTextField(labelWithAttributedString: attributedTitle)
        label.sizeToFit()
        let labelSize = label.frame.size
        let width = labelSize.width + 28
        super.init(frame: NSRect(x: 0, y: 0, width: max(width, 200), height: itemHeight))

        label.frame = NSRect(x: 14, y: (itemHeight - labelSize.height) / 2,
                             width: labelSize.width, height: labelSize.height)
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        NSSize(width: max(label.fittingSize.width + 28, 200), height: itemHeight)
    }

    override func mouseEntered(with event: NSEvent) {
        isHighlighted = true
        label.attributedStringValue = whiteColoredString(originalAttributedTitle)
        needsDisplay = true
        MenuItemTooltipController.shared.show(text: tooltipText, from: self)
    }

    override func mouseExited(with event: NSEvent) {
        isHighlighted = false
        label.attributedStringValue = originalAttributedTitle
        needsDisplay = true
        MenuItemTooltipController.shared.hide(for: self)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHighlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        }
    }

    private func whiteColoredString(_ source: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: source)
        result.addAttribute(.foregroundColor, value: NSColor.white,
                            range: NSRange(location: 0, length: result.length))
        return result
    }
}

/// A custom NSView for NSMenuItem that handles clicks without closing the menu.
/// NSMenu only auto-closes on click for items using the standard action/target mechanism.
/// Items with a custom `view` do not trigger menu dismissal.
private final class ClickableMenuItemView: NSView {
    private let label: NSTextField
    private let onClick: () -> Void
    private let tooltipText: String?
    private var isHighlighted = false
    private let itemHeight: CGFloat = 22
    private var originalAttributedTitle: NSAttributedString
    private var hoverTrackingArea: NSTrackingArea?

    init(attributedTitle: NSAttributedString, toolTip: String? = nil, onClick: @escaping () -> Void) {
        self.onClick = onClick
        self.tooltipText = toolTip
        self.originalAttributedTitle = attributedTitle
        self.label = NSTextField(labelWithAttributedString: attributedTitle)
        label.sizeToFit()
        let labelSize = label.frame.size
        let width = labelSize.width + 28  // 14pt padding on each side
        super.init(frame: NSRect(x: 0, y: 0, width: max(width, 200), height: itemHeight))

        label.frame = NSRect(x: 14, y: (itemHeight - labelSize.height) / 2,
                             width: labelSize.width, height: labelSize.height)
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        NSSize(width: max(label.fittingSize.width + 28, 200), height: itemHeight)
    }

    override func mouseUp(with event: NSEvent) {
        onClick()
    }

    override func mouseEntered(with event: NSEvent) {
        isHighlighted = true
        label.attributedStringValue = whiteColoredString(originalAttributedTitle)
        needsDisplay = true
        MenuItemTooltipController.shared.show(text: tooltipText, from: self)
    }

    override func mouseExited(with event: NSEvent) {
        isHighlighted = false
        label.attributedStringValue = originalAttributedTitle
        needsDisplay = true
        MenuItemTooltipController.shared.hide(for: self)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHighlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        }
    }

    private func whiteColoredString(_ source: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: source)
        result.addAttribute(.foregroundColor, value: NSColor.white,
                            range: NSRange(location: 0, length: result.length))
        return result
    }
}

// MARK: - Multi-action menu item view (dual clickable regions)

/// A custom NSView for NSMenuItem that supports multiple independently clickable action
/// regions within a single attributed string. Used for the `.updateAvailable` state where
/// both "更新" and "卸载" need to be clickable.
///
/// Uses Core Text hit testing to map click position → character index → action.
private final class MultiActionMenuItemView: NSView {
    struct Action {
        let range: NSRange
        let callback: () -> Void
    }

    private let label: NSTextField
    private let actions: [Action]
    private let originalAttributedTitle: NSAttributedString
    private let tooltipText: String?
    private var isHighlighted = false
    private let itemHeight: CGFloat = 22
    private var hoverTrackingArea: NSTrackingArea?

    init(attributedTitle: NSAttributedString, actions: [Action], toolTip: String? = nil) {
        self.originalAttributedTitle = attributedTitle
        self.tooltipText = toolTip
        self.actions = actions
        self.label = NSTextField(labelWithAttributedString: attributedTitle)
        label.sizeToFit()
        let labelSize = label.frame.size
        let width = labelSize.width + 28
        super.init(frame: NSRect(x: 0, y: 0, width: max(width, 200), height: itemHeight))

        label.frame = NSRect(x: 14, y: (itemHeight - labelSize.height) / 2,
                             width: labelSize.width, height: labelSize.height)
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        NSSize(width: max(label.fittingSize.width + 28, 200), height: itemHeight)
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let labelPoint = NSPoint(x: point.x - label.frame.origin.x,
                                 y: point.y - label.frame.origin.y)

        let line = CTLineCreateWithAttributedString(label.attributedStringValue)
        let index = CTLineGetStringIndexForPosition(line, labelPoint)

        for action in actions {
            if NSLocationInRange(index, action.range) {
                action.callback()
                return
            }
        }
    }

    override func mouseEntered(with event: NSEvent) {
        isHighlighted = true
        let white = NSMutableAttributedString(attributedString: originalAttributedTitle)
        white.addAttribute(.foregroundColor, value: NSColor.white,
                           range: NSRange(location: 0, length: white.length))
        label.attributedStringValue = white
        needsDisplay = true
        MenuItemTooltipController.shared.show(text: tooltipText, from: self)
    }

    override func mouseExited(with event: NSEvent) {
        isHighlighted = false
        label.attributedStringValue = originalAttributedTitle
        needsDisplay = true
        MenuItemTooltipController.shared.hide(for: self)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHighlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        }
    }
}


// MARK: - Group Header Menu Item View

@MainActor
private final class GroupHeaderMenuItemView: NSView {
    private let iconView: NSImageView
    private let nameLabel: NSTextField
    private let countLabel: NSTextField
    private let statusStack: NSStackView
    private let itemHeight: CGFloat = 26

    init(tool: ToolKind, sessionCount: Int, states: [ToolActivityState]) {
        self.iconView = NSImageView()
        self.nameLabel = NSTextField(labelWithString: "")
        self.countLabel = NSTextField(labelWithString: "")
        self.statusStack = NSStackView()

        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: itemHeight))

        // Load tool icon
        if let icon = ToolIconLoader.icon(for: tool) {
            iconView.image = icon
        }
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.frame = NSRect(x: 14, y: (itemHeight - 14) / 2, width: 14, height: 14)
        addSubview(iconView)

        // Tool name
        let nameAttr = NSAttributedString(
            string: tool.displayName,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
            ]
        )
        nameLabel.attributedStringValue = nameAttr
        nameLabel.sizeToFit()
        nameLabel.frame = NSRect(
            x: 32,
            y: (itemHeight - nameLabel.frame.height) / 2,
            width: nameLabel.frame.width,
            height: nameLabel.frame.height
        )
        addSubview(nameLabel)

        // Session count
        let countAttr = NSAttributedString(
            string: " (\(sessionCount))",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        countLabel.attributedStringValue = countAttr
        countLabel.sizeToFit()
        countLabel.frame = NSRect(
            x: nameLabel.frame.maxX,
            y: (itemHeight - countLabel.frame.height) / 2,
            width: countLabel.frame.width,
            height: countLabel.frame.height
        )
        addSubview(countLabel)

        // Status indicators
        let uniqueStates = Array(Set(states)).sorted { s1, s2 in
            // Sort by priority: running > awaiting > idle > unknown
            let priority: [ToolActivityState: Int] = [
                .running: 0,
                .awaitingInput: 1,
                .idle: 2,
                .unknown: 3
            ]
            return (priority[s1] ?? 4) < (priority[s2] ?? 4)
        }

        var statusViews: [NSView] = []
        for state in uniqueStates.prefix(3) {
            let dot = NSView(frame: NSRect(x: 0, y: 0, width: 5, height: 5))
            dot.wantsLayer = true
            dot.layer?.backgroundColor = StatusColors.activity(state).cgColor
            dot.layer?.cornerRadius = 2.5
            statusViews.append(dot)
        }

        statusStack.orientation = .horizontal
        statusStack.spacing = 3
        statusStack.alignment = .centerY
        statusStack.distribution = .fill
        statusViews.forEach { statusStack.addArrangedSubview($0) }

        statusStack.frame = NSRect(
            x: frame.width - CGFloat(statusViews.count * 8) - 14,
            y: (itemHeight - 5) / 2,
            width: CGFloat(statusViews.count * 8),
            height: 5
        )
        addSubview(statusStack)

        // Disable user interaction (header is not clickable)
        isEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 300, height: itemHeight)
    }

    private var isEnabled: Bool = true {
        didSet {
            alphaValue = isEnabled ? 1.0 : 0.5
        }
    }
}
