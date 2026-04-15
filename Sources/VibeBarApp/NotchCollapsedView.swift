import SwiftUI
import VibeBarCore

struct NotchCollapsedView: View {
    enum Presentation: Equatable {
        case collapsed(notchWidth: CGFloat, extensionWidth: CGFloat, notchHeight: CGFloat)
        case bridge(surfaceX: CGFloat, extensionWidth: CGFloat, notchHeight: CGFloat, visibleHeight: CGFloat)
    }

    let summary: GlobalSummary
    let sessions: [SessionSnapshot]
    let presentation: Presentation

    private var statusImage: NSImage {
        StatusImageRenderer.render(summary: summary, style: AppSettings.shared.iconStyle)
    }

    /// The most active tool name to display, if any.
    private var activeToolLabel: String? {
        let activeSessions = sessions.filter { $0.status == .running || $0.status == .awaitingInput }
        guard let session = activeSessions.first else { return nil }
        return session.tool.shortDisplayName
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
        switch presentation {
        case let .collapsed(notchWidth, extensionWidth, notchHeight):
            let fullWidth = notchWidth + extensionWidth
            ZStack(alignment: .topLeading) {
                panelOutlineBackground(bottomCornerRadius: NotchPanelStyle.cornerRadius)

                iconSurface(height: notchHeight)
                    .frame(width: extensionWidth, height: notchHeight)
                    .offset(x: clampedOffset(notchWidth, in: size.width, visualWidth: extensionWidth))
            }
            .frame(width: fullWidth, height: notchHeight, alignment: .topLeading)

        case let .bridge(surfaceX, extensionWidth, notchHeight, visibleHeight):
            ZStack(alignment: .topLeading) {
                panelOutlineBackground(bottomCornerRadius: 0)

                iconSurface(height: notchHeight)
                    .frame(width: extensionWidth, height: notchHeight)
                    .offset(x: clampedOffset(surfaceX, in: size.width, visualWidth: extensionWidth))
            }
            .frame(width: size.width, height: visibleHeight, alignment: .topLeading)
        }
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

    private func iconSurface(height: CGFloat) -> some View {
        ZStack {
            Color.clear
            VStack(spacing: 2) {
                statusIcon

                if let label = activeToolLabel {
                    TypingIndicator(fontSize: 7, label: label, bright: true)
                        .frame(width: 30)
                }
            }
        }
        .frame(height: height)
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
