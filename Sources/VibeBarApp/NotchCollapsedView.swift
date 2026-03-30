import SwiftUI
import VibeBarCore

struct NotchCollapsedView: View {
    enum Presentation: Equatable {
        case collapsed(notchWidth: CGFloat, extensionWidth: CGFloat, notchHeight: CGFloat)
        case bridge(surfaceX: CGFloat, extensionWidth: CGFloat, notchHeight: CGFloat, visibleHeight: CGFloat)
    }

    let summary: GlobalSummary
    let presentation: Presentation

    private var statusImage: NSImage {
        StatusImageRenderer.render(summary: summary, style: AppSettings.shared.iconStyle)
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
            let joinRadius = NotchPanelStyle.collapsedJoinRadius
            let visualWidth = extensionWidth + joinRadius
            extensionSurface(height: notchHeight)
                .frame(width: visualWidth, height: notchHeight)
                .offset(
                    x: clampedOffset(
                        notchWidth - joinRadius,
                        in: size.width,
                        visualWidth: visualWidth
                    )
                )

        case let .bridge(surfaceX, extensionWidth, notchHeight, visibleHeight):
            ZStack(alignment: .topLeading) {
                bridgeBackground

                iconSurface(height: notchHeight)
                    .frame(width: extensionWidth, height: notchHeight)
                    .offset(x: clampedOffset(surfaceX, in: size.width, visualWidth: extensionWidth))
            }
            .frame(width: size.width, height: visibleHeight, alignment: .topLeading)
        }
    }

    private func extensionSurface(height: CGFloat) -> some View {
        ZStack {
            NotchRightExtensionShape(
                cornerRadius: NotchPanelStyle.cornerRadius,
                leadingJoinRadius: NotchPanelStyle.collapsedJoinRadius
            )
                .fill(NotchPanelStyle.fillColor)

            NotchRightExtensionShape(
                cornerRadius: NotchPanelStyle.cornerRadius,
                leadingJoinRadius: NotchPanelStyle.collapsedJoinRadius
            )
                .fill(NotchPanelStyle.topHighlight)
                .frame(height: min(height, NotchPanelStyle.topHighlightHeight))
                .clipped()

            NotchRightExtensionShape(
                cornerRadius: NotchPanelStyle.cornerRadius,
                leadingJoinRadius: NotchPanelStyle.collapsedJoinRadius
            )
                .stroke(NotchPanelStyle.strokeColor, lineWidth: 1)

            statusIcon
        }
    }

    private var bridgeBackground: some View {
        NotchPanelOutlineShape(bottomCornerRadius: 0)
            .fill(NotchPanelStyle.fillColor)
            .overlay(alignment: .top) {
                NotchPanelOutlineShape(bottomCornerRadius: 0)
                    .fill(NotchPanelStyle.topHighlight)
                    .frame(height: NotchPanelStyle.topHighlightHeight)
                    .clipped()
            }
            .overlay(
                NotchPanelOutlineShape(bottomCornerRadius: 0)
                    .stroke(NotchPanelStyle.strokeColor, lineWidth: 1)
            )
    }

    private func iconSurface(height: CGFloat) -> some View {
        ZStack {
            Color.clear
            statusIcon
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

private struct NotchRightExtensionShape: Shape {
    let cornerRadius: CGFloat
    let leadingJoinRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let trailingRadius = min(cornerRadius, rect.width, rect.height)
        let leadingRadius = min(leadingJoinRadius, rect.width, rect.height)
        let topLeadingX = rect.minX + leadingRadius

        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: topLeadingX, y: rect.maxY - leadingRadius),
            control: CGPoint(x: rect.minX, y: rect.maxY - leadingRadius)
        )
        path.addLine(to: CGPoint(x: topLeadingX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - trailingRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - trailingRadius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
