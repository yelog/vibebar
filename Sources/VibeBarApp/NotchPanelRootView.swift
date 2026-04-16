import SwiftUI
import VibeBarCore

struct NotchPanelRootView: View {
    @ObservedObject var state: NotchPanelViewState

    var body: some View {
        ZStack(alignment: .topLeading) {
            if state.layoutModel.showsPanelBackground {
                panelBackground
                    .opacity(state.layoutModel.surfaceOpacity)
            }

            if state.layoutModel.showsTopShell {
                topShell
            }

            if state.layoutModel.showsExpandedBody {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear
                        .frame(height: max(state.contentTopInset, 0))

                    NotchExpandedBodyView(
                        model: state.model,
                        usageSnapshot: state.usageSnapshot,
                        usageEnabled: state.usageEnabled,
                        isUsageRefreshing: state.isUsageRefreshing,
                        onRefresh: state.onRefresh,
                        onOpenSettings: state.onOpenSettings,
                        onOpenSession: state.onOpenSession,
                        onQuit: state.onQuit
                    )
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
                    .padding(.bottom, 14)
                    .opacity(state.layoutModel.bodyOpacity)
                    .offset(y: state.layoutModel.bodyOffsetY)
                    .scaleEffect(state.layoutModel.bodyScale, anchor: .top)
                    .blur(radius: state.layoutModel.bodyBlurRadius)
                    .compositingGroup()
                    .allowsHitTesting(state.layoutModel.allowsBodyHitTesting)
                }
                .transition(.blurFade.combined(with: .move(edge: .top)))
                .clipped()
            }
        }
        .frame(width: max(state.panelWidth, 1), alignment: .leading)
        .overlay {
            if state.layoutModel.showsPanelBackground {
                NotchPanelOutlineShape(bottomCornerRadius: NotchPanelStyle.bottomCornerRadius)
                    .stroke(NotchPanelStyle.strokeColor, lineWidth: 1)
                    .opacity(state.layoutModel.surfaceOpacity)
            }
        }
        .frame(
            width: max(state.panelWidth, 1),
            height: state.panelHeight.map { max($0, 1) },
            alignment: .topLeading
        )
        .shadow(
            color: state.layoutModel.showsPanelBackground ? NotchPanelStyle.shadowColor : .clear,
            radius: 20,
            x: 0,
            y: 12
        )
    }

    private var topShell: some View {
        NotchCollapsedView(
            summary: state.summary,
            sessions: state.sessions,
            presentation: state.topShellPresentation
        )
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: topShellHeight, alignment: .topLeading)
        .allowsHitTesting(false)
        .transaction { transaction in
            // Top shell already follows the animated NSPanel frame via layout callbacks.
            // Disabling SwiftUI interpolation here avoids animating between two local
            // coordinate systems when the hosting view switches to the expanded reference frame.
            transaction.animation = nil
        }
    }

    private var topShellHeight: CGFloat {
        state.topShellPresentation.visibleHeight
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
