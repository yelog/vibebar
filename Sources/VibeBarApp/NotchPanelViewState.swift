import SwiftUI
import VibeBarCore

@MainActor
final class NotchPanelViewState: ObservableObject {
    var summary: GlobalSummary
    var sessions: [SessionSnapshot]
    var model: MonitorViewModel
    var usageSnapshot: UsageSnapshot?
    var usageEnabled: Bool
    var isUsageRefreshing: Bool
    var contentTopInset: CGFloat
    var panelWidth: CGFloat
    var panelHeight: CGFloat?
    var topShellPresentation: NotchCollapsedView.Presentation
    var layoutModel: NotchPanelLayoutModel
    var onRefresh: () -> Void
    var onOpenSettings: () -> Void
    var onOpenSession: (SessionSnapshot) -> Void
    var onQuit: () -> Void

    init(
        summary: GlobalSummary,
        sessions: [SessionSnapshot],
        model: MonitorViewModel,
        usageSnapshot: UsageSnapshot?,
        usageEnabled: Bool,
        isUsageRefreshing: Bool,
        contentTopInset: CGFloat,
        panelWidth: CGFloat,
        panelHeight: CGFloat?,
        topShellPresentation: NotchCollapsedView.Presentation,
        layoutModel: NotchPanelLayoutModel,
        onRefresh: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onOpenSession: @escaping (SessionSnapshot) -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.summary = summary
        self.sessions = sessions
        self.model = model
        self.usageSnapshot = usageSnapshot
        self.usageEnabled = usageEnabled
        self.isUsageRefreshing = isUsageRefreshing
        self.contentTopInset = contentTopInset
        self.panelWidth = panelWidth
        self.panelHeight = panelHeight
        self.topShellPresentation = topShellPresentation
        self.layoutModel = layoutModel
        self.onRefresh = onRefresh
        self.onOpenSettings = onOpenSettings
        self.onOpenSession = onOpenSession
        self.onQuit = onQuit
    }

    func update(
        summary: GlobalSummary,
        sessions: [SessionSnapshot],
        model: MonitorViewModel,
        usageSnapshot: UsageSnapshot?,
        usageEnabled: Bool,
        isUsageRefreshing: Bool,
        contentTopInset: CGFloat,
        panelWidth: CGFloat,
        panelHeight: CGFloat?,
        topShellPresentation: NotchCollapsedView.Presentation,
        layoutModel: NotchPanelLayoutModel,
        onRefresh: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onOpenSession: @escaping (SessionSnapshot) -> Void,
        onQuit: @escaping () -> Void
    ) {
        objectWillChange.send()
        self.summary = summary
        self.sessions = sessions
        self.model = model
        self.usageSnapshot = usageSnapshot
        self.usageEnabled = usageEnabled
        self.isUsageRefreshing = isUsageRefreshing
        self.contentTopInset = contentTopInset
        self.panelWidth = panelWidth
        self.panelHeight = panelHeight
        self.topShellPresentation = topShellPresentation
        self.layoutModel = layoutModel
        self.onRefresh = onRefresh
        self.onOpenSettings = onOpenSettings
        self.onOpenSession = onOpenSession
        self.onQuit = onQuit
    }

    func updateTopShellPresentation(_ topShellPresentation: NotchCollapsedView.Presentation) {
        guard self.topShellPresentation != topShellPresentation else { return }
        objectWillChange.send()
        self.topShellPresentation = topShellPresentation
    }
}
