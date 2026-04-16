import SwiftUI
import VibeBarCore

struct NotchContentView: View {
    let summary: GlobalSummary
    @ObservedObject var model: MonitorViewModel
    let usageSnapshot: UsageSnapshot?
    let usageEnabled: Bool
    let isUsageRefreshing: Bool
    let contentTopInset: CGFloat
    let topCoverPresentation: NotchCollapsedView.Presentation
    let onRefresh: () -> Void
    let onOpenSettings: () -> Void
    let onOpenSession: (SessionSnapshot) -> Void
    let onQuit: () -> Void
    @StateObject private var state: NotchPanelViewState

    init(
        summary: GlobalSummary,
        model: MonitorViewModel,
        usageSnapshot: UsageSnapshot?,
        usageEnabled: Bool,
        isUsageRefreshing: Bool,
        contentTopInset: CGFloat,
        topCoverPresentation: NotchCollapsedView.Presentation,
        onRefresh: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onOpenSession: @escaping (SessionSnapshot) -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.summary = summary
        self.model = model
        self.usageSnapshot = usageSnapshot
        self.usageEnabled = usageEnabled
        self.isUsageRefreshing = isUsageRefreshing
        self.contentTopInset = contentTopInset
        self.topCoverPresentation = topCoverPresentation
        self.onRefresh = onRefresh
        self.onOpenSettings = onOpenSettings
        self.onOpenSession = onOpenSession
        self.onQuit = onQuit
        _state = StateObject(
            wrappedValue: NotchPanelViewState(
                summary: summary,
                sessions: model.sessions,
                model: model,
                usageSnapshot: usageSnapshot,
                usageEnabled: usageEnabled,
                isUsageRefreshing: isUsageRefreshing,
                contentTopInset: contentTopInset,
                panelWidth: 440,
                panelHeight: nil,
                topShellPresentation: topCoverPresentation,
                layoutModel: NotchPanelLayoutModel(phase: .expanded),
                onRefresh: onRefresh,
                onOpenSettings: onOpenSettings,
                onOpenSession: onOpenSession,
                onQuit: onQuit
            )
        )
    }

    var body: some View {
        NotchPanelRootView(state: state)
    }
}
