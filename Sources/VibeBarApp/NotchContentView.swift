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

    var body: some View {
        NotchPanelRootView(
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
    }
}
