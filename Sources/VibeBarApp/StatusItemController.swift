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

    private let model = MonitorViewModel()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let notificationCenter: UNUserNotificationCenter?
    private let legacyNotificationCenter: NSUserNotificationCenter?
    private var cancellables = Set<AnyCancellable>()
    private var hasInitializedSessionStates = false
    private var previousSessionStates: [String: ToolActivityState] = [:]
    private var notifiedAwaitingSessionIDs = Set<String>()
    private var didHandleStartupPluginUpdatePrompt = false

    override init() {
        if VibeBarPaths.runMode == .published {
            notificationCenter = UNUserNotificationCenter.current()
            legacyNotificationCenter = nil
        } else {
            notificationCenter = nil
            legacyNotificationCenter = NSUserNotificationCenter.default
        }

        super.init()
        menu.delegate = self
        statusItem.menu = menu
        notificationCenter?.delegate = self
        legacyNotificationCenter?.delegate = self
        configureButtonIfPossible()
        bindModel()
        updateUI(summary: model.summary, sessions: model.sessions, pluginStatus: model.pluginStatus)

        if AppSettings.shared.notifyAwaitingInput {
            requestNotificationPermission { [weak self] granted in
                guard let self, granted else { return }
                self.notifyCurrentAwaitingSessions()
            }
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
                self?.updateUI(summary: summary, sessions: sessions, pluginStatus: pluginStatus)
            }
            .store(in: &cancellables)

        AppSettings.shared.$iconStyle
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateUI(summary: self.model.summary, sessions: self.model.sessions, pluginStatus: self.model.pluginStatus)
            }
            .store(in: &cancellables)

        AppSettings.shared.$colorTheme
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateUI(summary: self.model.summary, sessions: self.model.sessions, pluginStatus: self.model.pluginStatus)
            }
            .store(in: &cancellables)

        AppSettings.shared.$customRunningColor
            .merge(with: AppSettings.shared.$customAwaitingColor)
            .merge(with: AppSettings.shared.$customIdleColor)
            .dropFirst(3)
            .sink { [weak self] _ in
                guard let self, AppSettings.shared.colorTheme == .custom else { return }
                self.updateUI(summary: self.model.summary, sessions: self.model.sessions, pluginStatus: self.model.pluginStatus)
            }
            .store(in: &cancellables)

        L10n.shared.$resolvedLang
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateUI(summary: self.model.summary, sessions: self.model.sessions, pluginStatus: self.model.pluginStatus)
            }
            .store(in: &cancellables)

        AppSettings.shared.$notifyAwaitingInput
            .dropFirst()
            .sink { [weak self] enabled in
                guard let self else { return }
                guard enabled else { return }
                self.notifiedAwaitingSessionIDs.removeAll()
                self.requestNotificationPermission { granted in
                    guard granted else { return }
                    self.notifyCurrentAwaitingSessions()
                }
            }
            .store(in: &cancellables)
    }

    private func updateUI(summary: GlobalSummary, sessions: [SessionSnapshot], pluginStatus: PluginStatusReport) {
        guard let button = statusItem.button else { return }

        button.title = ""
        button.image = StatusImageRenderer.render(summary: summary, style: AppSettings.shared.iconStyle)
        button.toolTip = L10n.shared.string(.tooltipFmt, summary.total)

        notifyAwaitingInputTransitionsIfNeeded(sessions: sessions)
        rebuildMenuItems(summary: summary, sessions: sessions, pluginStatus: pluginStatus)
        promptPluginUpdateIfNeeded(pluginStatus: pluginStatus)
    }

    private func notifyAwaitingInputTransitionsIfNeeded(sessions: [SessionSnapshot]) {
        let waitingIDs = Set(sessions.filter { $0.status == .awaitingInput }.map { $0.id })
        notifiedAwaitingSessionIDs.formIntersection(waitingIDs)

        let currentStates = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0.status) })
        defer {
            previousSessionStates = currentStates
            hasInitializedSessionStates = true
        }

        guard hasInitializedSessionStates else {
            guard AppSettings.shared.notifyAwaitingInput else { return }
            notifyCurrentAwaitingSessions()
            return
        }
        guard AppSettings.shared.notifyAwaitingInput else { return }

        for session in sessions where session.status == .awaitingInput {
            let previous = previousSessionStates[session.id]
            let hasNotified = notifiedAwaitingSessionIDs.contains(session.id)
            guard previous != .awaitingInput || !hasNotified else { continue }
            postAwaitingInputNotification(for: session)
            notifiedAwaitingSessionIDs.insert(session.id)
        }
    }

    private func requestNotificationPermission(completion: @escaping @MainActor (Bool) -> Void) {
        guard let notificationCenter else {
            Task { @MainActor in completion(true) }
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

    private func notifyCurrentAwaitingSessions() {
        for session in model.sessions where session.status == .awaitingInput {
            guard !notifiedAwaitingSessionIDs.contains(session.id) else { continue }
            postAwaitingInputNotification(for: session)
            notifiedAwaitingSessionIDs.insert(session.id)
        }
    }

    private func postAwaitingInputNotification(for session: SessionSnapshot) {
        let id = "awaiting-\(session.id)-\(UUID().uuidString)"
        let body = L10n.shared.string(.notifyAwaitingInputBodyFmt, notificationToolName(for: session.tool))

        if notificationCenter != nil {
            requestNotificationPermission { [weak self] granted in
                guard granted else { return }
                self?.deliverUNNotification(id: id, body: body)
            }
            return
        }

        if let legacyNotificationCenter {
            let notification = NSUserNotification()
            notification.identifier = id
            notification.title = "VibeBar"
            notification.informativeText = body
            notification.soundName = NSUserNotificationDefaultSoundName
            notification.userInfo = ["action": NotificationConstants.openMenuAction]
            legacyNotificationCenter.deliver(notification)
        }
    }

    private func deliverUNNotification(id: String, body: String) {
        guard let notificationCenter else { return }

        let content = UNMutableNotificationContent()
        content.title = "VibeBar"
        content.body = body
        content.sound = .default
        content.userInfo = ["action": NotificationConstants.openMenuAction]

        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        notificationCenter.add(request) { error in
            guard let error else { return }
            fputs("vibebar: 发送通知失败: \(error.localizedDescription)\n", stderr)
        }
    }

    private func notificationToolName(for tool: ToolKind) -> String {
        switch tool {
        case .claudeCode:
            return "Claude Code"
        case .codex:
            return "Codex"
        case .opencode:
            return "Opencode"
        }
    }

    private func openMenuFromNotification() {
        guard let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        button.performClick(nil)
    }

    private func rebuildMenuItems(summary: GlobalSummary, sessions: [SessionSnapshot], pluginStatus: PluginStatusReport) {
        menu.removeAllItems()

        let title = NSMenuItem(title: "VibeBar", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)

        let updated = DateFormatter.vibeBarClock.string(from: summary.updatedAt)
        let subtitle = NSMenuItem(title: L10n.shared.string(.menuSubtitleFmt, summary.total, updated), action: nil, keyEquivalent: "")
        subtitle.isEnabled = false
        menu.addItem(subtitle)
        menu.addItem(.separator())

        if sessions.isEmpty {
            let empty = NSMenuItem(title: L10n.shared.string(.noSessions), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for session in sessions.prefix(8) {
                let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
                item.attributedTitle = attributedSessionLine(session)
                item.target = self
                item.action = #selector(onNoop)
                item.isEnabled = true
                menu.addItem(item)
            }
        }

        // Plugin status section
        if pluginStatus.needsAttention {
            menu.addItem(.separator())
            let header = NSMenuItem(title: L10n.shared.string(.pluginTitle), action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)

            for (tool, status) in pluginStatus.visibleItems {
                addPluginMenuItem(to: menu, tool: tool, status: status)
            }
        }

        menu.addItem(.separator())

        let refresh = NSMenuItem(title: L10n.shared.string(.refresh), action: #selector(onRefresh), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        let openFolder = NSMenuItem(title: L10n.shared.string(.openSessionsDir), action: #selector(onOpenFolder), keyEquivalent: "o")
        openFolder.target = self
        menu.addItem(openFolder)

        let purge = NSMenuItem(title: L10n.shared.string(.purgeStale), action: #selector(onPurgeStale), keyEquivalent: "c")
        purge.target = self
        menu.addItem(purge)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: L10n.shared.string(.settings), action: #selector(onSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let about = NSMenuItem(title: L10n.shared.string(.tabAbout), action: #selector(onAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let quit = NSMenuItem(title: L10n.shared.string(.quitVibeBar), action: #selector(onQuit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func attributedSessionLine(_ session: SessionSnapshot) -> NSAttributedString {
        let prefix = "● "
        let base = "\(session.tool.displayName) · pid \(session.pid) · "
        let status = session.status.displayName
        let separator = " · "
        let directory = displayDirectory(for: session)
        let full = prefix + base + status + separator + directory

        let attributed = NSMutableAttributedString(
            string: full,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.labelColor,
            ]
        )

        let statusColor = StatusColors.activity(session.status)
        attributed.addAttribute(.foregroundColor, value: statusColor, range: NSRange(location: 0, length: 1))
        attributed.addAttributes(
            [
                .foregroundColor: statusColor,
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold),
            ],
            range: NSRange(location: prefix.count + base.count, length: status.count)
        )
        attributed.addAttribute(
            .foregroundColor,
            value: NSColor.secondaryLabelColor,
            range: NSRange(location: prefix.count + base.count + status.count + separator.count, length: directory.count)
        )

        return attributed
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

    // MARK: - Plugin Menu Items

    private func addPluginMenuItem(to menu: NSMenu, tool: ToolKind, status: PluginInstallStatus) {
        let l10n = L10n.shared
        let displayName = tool.displayName + l10n.string(.pluginSuffix)
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")

        switch status {
        case .installed:
            let version = model.bundledPluginVersion(for: tool)
            let view = ClickableMenuItemView(
                attributedTitle: attributedPluginInstalledLine(displayName, version: version)
            ) { [weak self] in
                self?.model.uninstallPlugin(tool: tool)
            }
            item.view = view

        case .updateAvailable(let installed, let bundled):
            let (attrString, actions) = attributedPluginUpdateLine(
                displayName, installed: installed, bundled: bundled,
                onUpdate: { [weak self] in self?.model.updatePlugin(tool: tool) },
                onUninstall: { [weak self] in self?.model.uninstallPlugin(tool: tool) }
            )
            let view = MultiActionMenuItemView(attributedTitle: attrString, actions: actions)
            item.view = view

        case .notInstalled:
            let view = ClickableMenuItemView(
                attributedTitle: attributedPluginInstallLine(displayName)
            ) { [weak self] in
                self?.model.installPlugin(tool: tool)
            }
            item.view = view

        case .installing:
            item.title = "  \(displayName): \(l10n.string(.pluginInstalling))"
            item.isEnabled = false

        case .installFailed(let message):
            let view = ClickableMenuItemView(
                attributedTitle: attributedPluginFailedLine(displayName, verb: l10n.string(.pluginInstall), action: l10n.string(.pluginRetry))
            ) { [weak self] in
                self?.model.installPlugin(tool: tool)
            }
            item.view = view
            item.toolTip = message

        case .uninstalling:
            item.title = "  \(displayName): \(l10n.string(.pluginUninstalling))"
            item.isEnabled = false

        case .uninstallFailed(let message):
            let view = ClickableMenuItemView(
                attributedTitle: attributedPluginFailedLine(displayName, verb: l10n.string(.pluginUninstall), action: l10n.string(.pluginRetryUninstall))
            ) { [weak self] in
                self?.model.uninstallPlugin(tool: tool)
            }
            item.view = view
            item.toolTip = message

        case .checking:
            item.title = "  \(displayName): \(l10n.string(.pluginChecking))"
            item.isEnabled = false

        case .cliNotFound:
            return

        case .updating:
            item.title = "  \(displayName): \(l10n.string(.pluginUpdating))"
            item.isEnabled = false

        case .updateFailed(let message):
            let view = ClickableMenuItemView(
                attributedTitle: attributedPluginFailedLine(displayName, verb: l10n.string(.pluginUpdate), action: l10n.string(.pluginRetry))
            ) { [weak self] in
                self?.model.updatePlugin(tool: tool)
            }
            item.view = view
            item.toolTip = message
        }

        menu.addItem(item)
    }

    private func promptPluginUpdateIfNeeded(pluginStatus: PluginStatusReport) {
        guard !didHandleStartupPluginUpdatePrompt else { return }
        guard pluginStatus.claudeCode != .checking, pluginStatus.opencode != .checking else { return }

        didHandleStartupPluginUpdatePrompt = true
        guard AppSettings.shared.autoCheckUpdates else { return }

        for (tool, status) in pluginStatus.visibleItems {
            guard case .updateAvailable(let installed, let bundled) = status else { continue }
            guard model.shouldPromptForPluginUpdate(tool: tool, version: bundled) else { continue }
            showPluginUpdateAlert(tool: tool, installed: installed, bundled: bundled)
            break
        }
    }

    private func showPluginUpdateAlert(tool: ToolKind, installed: String, bundled: String) {
        let l10n = L10n.shared
        let alert = NSAlert()
        alert.messageText = l10n.string(.pluginUpdatePromptTitleFmt, tool.displayName, bundled)
        alert.informativeText = l10n.string(.pluginUpdatePromptInfoFmt, installed, bundled)
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

    private func attributedPluginInstallLine(_ name: String) -> NSAttributedString {
        let prefix = "  \(name): \(L10n.shared.string(.pluginNotInstalled)) — "
        let action = L10n.shared.string(.pluginInstall)
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
                .foregroundColor: NSColor.systemBlue,
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium),
            ],
            range: NSRange(location: prefix.count, length: action.count)
        )
        return attributed
    }

    private func attributedPluginInstalledLine(_ name: String, version: String?) -> NSAttributedString {
        let versionText = version.map { "v\($0) " } ?? ""
        let prefix = "  \(name): \(versionText)\(L10n.shared.string(.pluginInstalled)) — "
        let action = L10n.shared.string(.pluginUninstall)
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
                .foregroundColor: NSColor.systemOrange,
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium),
            ],
            range: NSRange(location: prefix.count, length: action.count)
        )
        return attributed
    }

    private func attributedPluginUpdateLine(
        _ name: String, installed: String, bundled: String,
        onUpdate: @escaping () -> Void,
        onUninstall: @escaping () -> Void
    ) -> (NSAttributedString, [MultiActionMenuItemView.Action]) {
        let prefix = "  \(name): \(installed)→\(bundled) — "
        let updateAction = L10n.shared.string(.pluginUpdate)
        let separator = " · "
        let uninstallAction = L10n.shared.string(.pluginUninstall)
        let full = prefix + updateAction + separator + uninstallAction

        let attributed = NSMutableAttributedString(
            string: full,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.labelColor,
            ]
        )

        let updateRange = NSRange(location: prefix.count, length: updateAction.count)
        attributed.addAttributes(
            [
                .foregroundColor: NSColor.systemBlue,
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium),
            ],
            range: updateRange
        )

        let uninstallStart = prefix.count + updateAction.count + separator.count
        let uninstallRange = NSRange(location: uninstallStart, length: uninstallAction.count)
        attributed.addAttributes(
            [
                .foregroundColor: NSColor.systemOrange,
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
    private func onRefresh() {
        model.refreshNow()
    }

    @objc
    private func onNoop() {}

    @objc
    private func onOpenFolder() {
        model.openSessionsFolder()
    }

    @objc
    private func onPurgeStale() {
        model.purgeStaleNow()
    }

    @objc
    private func onQuit() {
        NSApp.terminate(nil)
    }

    @objc
    private func onSettings() {
        SettingsWindowController.shared.showSettings(tab: .general)
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
        model.checkPluginStatusIfNeeded()
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

extension StatusItemController: NSUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: NSUserNotificationCenter,
        shouldPresent notification: NSUserNotification
    ) -> Bool {
        true
    }

    nonisolated func userNotificationCenter(
        _ center: NSUserNotificationCenter,
        didActivate notification: NSUserNotification
    ) {
        guard let action = notification.userInfo?["action"] as? String,
              action == NotificationConstants.openMenuAction else { return }

        Task { @MainActor [weak self] in
            self?.openMenuFromNotification()
        }
    }
}

@MainActor
enum StatusImageRenderer {
    private static let segmentThreshold = 8
    private static let lineWidth: CGFloat = 2.8
    private static let gapDegrees: Double = 8.0

    // MARK: - Entry point

    static func render(summary: GlobalSummary, style: IconStyle) -> NSImage {
        switch style {
        case .ring:      return renderRing(summary: summary)
        case .particles: return renderParticles(summary: summary)
        case .energyBar: return renderEnergyBar(summary: summary)
        case .iceGrid:   return renderIceGrid(summary: summary)
        }
    }

    // MARK: - Preview renderer

    static func renderPreview(style: IconStyle, previewSize: CGFloat = 48) -> NSImage {
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

    // MARK: - Shared: center number

    private static func drawCenterNumber(summary: GlobalSummary, center: NSPoint) {
        let text = "\(min(summary.total, 99))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .bold),
            .foregroundColor: NSColor.labelColor,
        ]
        let textSize = text.size(withAttributes: attrs)
        let textRect = NSRect(
            x: center.x - textSize.width / 2,
            y: center.y - textSize.height / 2,
            width: textSize.width,
            height: textSize.height
        )
        text.draw(in: textRect, withAttributes: attrs)
    }

    // MARK: - Ring renderer (original)

    private static func drawRing(summary: GlobalSummary) {
        let rect = NSRect(origin: .zero, size: NSSize(width: 18, height: 18))
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * 0.5 - 1.6

        let baseColor: NSColor = summary.total > 0
            ? NSColor.secondaryLabelColor.withAlphaComponent(0.32)
            : NSColor.labelColor.withAlphaComponent(0.68)

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
        let orbitColor = NSColor.secondaryLabelColor.withAlphaComponent(0.15)
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
        let numberAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .bold),
            .foregroundColor: NSColor.labelColor,
        ]
        let numberSize = numberText.size(withAttributes: numberAttrs)
        let numberRect = NSRect(
            x: (numberRegionWidth - numberSize.width) / 2,
            y: (iconSize - numberSize.height) / 2,
            width: numberSize.width,
            height: numberSize.height
        )
        numberText.draw(in: numberRect, withAttributes: numberAttrs)

        // Right side: stacked color blocks
        let blockWidth: CGFloat = 4
        let blockHeight: CGFloat = 3
        let blockSpacing: CGFloat = 1
        let maxBlocks = 5
        let rightX = numberRegionWidth + 1

        let segments: [ToolActivityState]
        if summary.total == 0 {
            segments = []
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
            let ghostColor = NSColor.secondaryLabelColor.withAlphaComponent(0.20)
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
            NSColor.white.withAlphaComponent(0.20).setFill()
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

// MARK: - Non-closing menu item view

/// A custom NSView for NSMenuItem that handles clicks without closing the menu.
/// NSMenu only auto-closes on click for items using the standard action/target mechanism.
/// Items with a custom `view` do not trigger menu dismissal.
private final class ClickableMenuItemView: NSView {
    private let label: NSTextField
    private let onClick: () -> Void
    private var isHighlighted = false
    private let itemHeight: CGFloat = 22
    private var originalAttributedTitle: NSAttributedString

    init(attributedTitle: NSAttributedString, onClick: @escaping () -> Void) {
        self.onClick = onClick
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
    }

    override func mouseExited(with event: NSEvent) {
        isHighlighted = false
        label.attributedStringValue = originalAttributedTitle
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self
        ))
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
    private var isHighlighted = false
    private let itemHeight: CGFloat = 22

    init(attributedTitle: NSAttributedString, actions: [Action]) {
        self.originalAttributedTitle = attributedTitle
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
    }

    override func mouseExited(with event: NSEvent) {
        isHighlighted = false
        label.attributedStringValue = originalAttributedTitle
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self
        ))
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHighlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        }
    }
}
