import SwiftUI
import VibeBarCore

struct NotchPanelRootView: View {
    @ObservedObject var state: NotchPanelViewState
    @ObservedObject private var l10n = L10n.shared

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
                expandedTopBar
            }

            if state.layoutModel.showsExpandedBody {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear
                        .frame(height: max(state.contentTopInset, 0))

                    NotchExpandedBodyView(
                        summary: state.summary,
                        sessions: state.sessions,
                        model: state.model,
                        usageSnapshot: state.usageSnapshot,
                        usageEnabled: state.usageEnabled,
                        isUsageRefreshing: state.isUsageRefreshing,
                        focusedSessionID: state.focusedSessionID,
                        onRefresh: state.onRefresh,
                        onOpenSettings: state.onOpenSettings,
                        onOpenSession: state.onOpenSession,
                        onQuit: state.onQuit
                    )
                    .padding(.horizontal, NotchPanelStyle.horizontalPadding)
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
            radius: 28,
            x: 0,
            y: 14
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

    private var expandedTopBar: some View {
        HStack(spacing: 10) {
            Text("VibeBar")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(NotchPanelStyle.primaryTextColor)
                .lineLimit(1)

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                NotchTopBarIconButton(
                    systemImage: "gearshape",
                    accessibilityLabel: l10n.string(.settings),
                    action: state.onOpenSettings
                )

                NotchTopBarIconButton(
                    systemImage: "power",
                    accessibilityLabel: l10n.string(.quit),
                    action: state.onQuit
                )
            }
        }
        .padding(.horizontal, NotchPanelStyle.horizontalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: state.topShellPresentation.notchHeight, alignment: .center)
        .opacity(state.layoutModel.bodyOpacity)
        .allowsHitTesting(state.layoutModel.allowsBodyHitTesting)
        .transition(.opacity)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(NotchPanelStyle.dividerColor)
                .frame(height: 1)
                .padding(.horizontal, NotchPanelStyle.horizontalPadding)
                .opacity(state.layoutModel.bodyOpacity)
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

private struct NotchTopBarIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NotchPanelStyle.primaryTextColor.opacity(isHovered ? 0.98 : 0.86))
                .frame(width: NotchPanelStyle.iconButtonSize, height: NotchPanelStyle.iconButtonSize)
                .background(
                    RoundedRectangle(cornerRadius: NotchPanelStyle.smallButtonCornerRadius, style: .continuous)
                        .fill(isHovered ? NotchPanelStyle.hoverFillColor : Color.clear)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: NotchPanelStyle.smallButtonCornerRadius, style: .continuous)
                        .strokeBorder(
                            isHovered ? NotchPanelStyle.strokeColor : Color.clear,
                            lineWidth: 1
                        )
                }
                .contentShape(RoundedRectangle(cornerRadius: NotchPanelStyle.smallButtonCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .accessibilityLabel(Text(accessibilityLabel))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }
}
