import SwiftUI
import VibeBarCore

struct NotchPanelRootView: View {
    let summary: GlobalSummary
    let sessions: [SessionSnapshot]
    @ObservedObject var model: MonitorViewModel
    let usageSnapshot: UsageSnapshot?
    let usageEnabled: Bool
    let isUsageRefreshing: Bool
    let contentTopInset: CGFloat
    let panelWidth: CGFloat
    let panelHeight: CGFloat?
    let topShellPresentation: NotchCollapsedView.Presentation
    let layoutModel: NotchPanelLayoutModel
    let onRefresh: () -> Void
    let onOpenSettings: () -> Void
    let onOpenSession: (SessionSnapshot) -> Void
    let onQuit: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            if layoutModel.showsPanelBackground {
                panelBackground
            }

            if layoutModel.showsTopShell {
                NotchCollapsedView(summary: summary, sessions: sessions, presentation: topShellPresentation)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .frame(height: topShellHeight, alignment: .topLeading)
                    .allowsHitTesting(false)
            }

            if layoutModel.showsExpandedBody {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear
                        .frame(height: max(contentTopInset, 0))

                    NotchExpandedBodyView(
                        model: model,
                        usageSnapshot: usageSnapshot,
                        usageEnabled: usageEnabled,
                        isUsageRefreshing: isUsageRefreshing,
                        onRefresh: onRefresh,
                        onOpenSettings: onOpenSettings,
                        onOpenSession: onOpenSession,
                        onQuit: onQuit
                    )
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
                    .padding(.bottom, 14)
                    .opacity(layoutModel.bodyOpacity)
                    .allowsHitTesting(layoutModel.allowsBodyHitTesting)
                }
                .clipped()
            }
        }
        .frame(width: max(panelWidth, 1), alignment: .leading)
        .overlay {
            if layoutModel.showsPanelBackground {
                NotchPanelOutlineShape(bottomCornerRadius: NotchPanelStyle.bottomCornerRadius)
                    .stroke(NotchPanelStyle.strokeColor, lineWidth: 1)
            }
        }
        .frame(
            width: max(panelWidth, 1),
            height: panelHeight.map { max($0, 1) },
            alignment: .topLeading
        )
        .shadow(
            color: layoutModel.showsPanelBackground ? NotchPanelStyle.shadowColor : .clear,
            radius: 20,
            x: 0,
            y: 12
        )
    }

    private var topShellHeight: CGFloat {
        switch topShellPresentation {
        case let .collapsed(_, _, notchHeight):
            return notchHeight
        case let .bridge(_, _, _, _, visibleHeight):
            return visibleHeight
        }
    }

    private var panelBackground: some View {
        NotchPanelOutlineShape(bottomCornerRadius: NotchPanelStyle.bottomCornerRadius)
            .fill(NotchPanelStyle.fillColor)
            .overlay(alignment: .top) {
                NotchPanelOutlineShape(bottomCornerRadius: NotchPanelStyle.bottomCornerRadius)
                    .fill(NotchPanelStyle.topHighlight)
                    .frame(height: NotchPanelStyle.topHighlightHeight)
                    .clipped()
            }
    }
}
