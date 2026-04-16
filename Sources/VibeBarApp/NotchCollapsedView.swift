import SwiftUI
import VibeBarCore

struct NotchCollapsedView: View {
    struct Presentation: Equatable {
        var surfaceX: CGFloat
        var surfaceWidth: CGFloat
        var iconWidth: CGFloat
        var leftIconX: CGFloat
        var rightIconX: CGFloat
        var notchHeight: CGFloat
        var visibleHeight: CGFloat
        var bottomCornerRadius: CGFloat

        static func collapsed(notchWidth: CGFloat, extensionWidth: CGFloat, notchHeight: CGFloat) -> Self {
            let surfaceWidth = notchWidth + (extensionWidth * 2)
            return Self(
                surfaceX: 0,
                surfaceWidth: surfaceWidth,
                iconWidth: extensionWidth,
                leftIconX: 0,
                rightIconX: surfaceWidth - extensionWidth,
                notchHeight: notchHeight,
                visibleHeight: notchHeight,
                bottomCornerRadius: NotchPanelStyle.cornerRadius
            )
        }
    }

    let summary: GlobalSummary
    let sessions: [SessionSnapshot]
    let presentation: Presentation

    private var statusImage: NSImage {
        StatusImageRenderer.render(summary: summary, style: AppSettings.shared.iconStyle)
    }

    /// The most active tool to surface in the collapsed notch, if any.
    private var activeTool: ToolKind? {
        let activeSessions = sessions.filter { $0.status == .running || $0.status == .awaitingInput }
        return activeSessions.first?.tool
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color.clear
                visibleSurface(in: proxy.size)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(L10n.shared.string(.accessibilityFmt, summary.total)))
    }

    @ViewBuilder
    private func visibleSurface(in size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            panelOutlineBackground(bottomCornerRadius: presentation.bottomCornerRadius)
                .frame(width: presentation.surfaceWidth, height: presentation.visibleHeight)
                .offset(
                    x: clampedOffset(
                        presentation.surfaceX,
                        in: size.width,
                        visualWidth: presentation.surfaceWidth
                    )
                )

            agentIconSurface(height: presentation.notchHeight)
                .frame(width: presentation.iconWidth, height: presentation.notchHeight)
                .offset(
                    x: clampedOffset(
                        presentation.leftIconX,
                        in: size.width,
                        visualWidth: presentation.iconWidth
                    )
                )

            statusIconSurface(height: presentation.notchHeight)
                .frame(width: presentation.iconWidth, height: presentation.notchHeight)
                .offset(
                    x: clampedOffset(
                        presentation.rightIconX,
                        in: size.width,
                        visualWidth: presentation.iconWidth
                    )
                )
        }
        .frame(width: size.width, height: presentation.visibleHeight, alignment: .topLeading)
    }

    private func panelOutlineBackground(bottomCornerRadius: CGFloat) -> some View {
        NotchPanelOutlineShape(bottomCornerRadius: bottomCornerRadius)
            .fill(NotchPanelStyle.fillColor)
            .overlay(alignment: .top) {
                NotchPanelOutlineShape(bottomCornerRadius: bottomCornerRadius)
                    .fill(NotchPanelStyle.topHighlight)
                    .frame(height: NotchPanelStyle.topHighlightHeight)
                    .clipped()
            }
            .overlay(
                NotchPanelOutlineShape(bottomCornerRadius: bottomCornerRadius)
                    .stroke(NotchPanelStyle.strokeColor, lineWidth: 1)
            )
    }

    private func agentIconSurface(height: CGFloat) -> some View {
        ZStack {
            Color.clear
            if let activeTool {
                toolIcon(for: activeTool)
            }
        }
        .frame(height: height)
    }

    private func statusIconSurface(height: CGFloat) -> some View {
        ZStack {
            Color.clear
            statusIcon
        }
        .frame(height: height)
    }

    @ViewBuilder
    private func toolIcon(for tool: ToolKind) -> some View {
        if let icon = ToolIconLoader.icon(for: tool) {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 10, height: 10)
        } else {
            Image(systemName: tool.iconName)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 10, height: 10)
        }
    }

    private var statusIcon: some View {
        Image(nsImage: statusImage)
            .interpolation(.high)
            .frame(width: 18, height: 18)
    }

    private func clampedOffset(_ proposed: CGFloat, in totalWidth: CGFloat, visualWidth: CGFloat) -> CGFloat {
        let maxOffset = max(totalWidth - visualWidth, 0)
        return min(max(proposed, 0), maxOffset)
    }
}
