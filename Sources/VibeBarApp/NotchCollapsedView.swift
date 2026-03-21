import SwiftUI
import VibeBarCore

struct NotchCollapsedView: View {
    let summary: GlobalSummary

    private var statusImage: NSImage {
        StatusImageRenderer.render(summary: summary, style: AppSettings.shared.iconStyle)
    }

    var body: some View {
        ZStack {
            NotchRightExtensionShape(cornerRadius: 11)
                .fill(Color.black.opacity(0.98))

            Image(nsImage: statusImage)
                .interpolation(.high)
                .frame(width: 18, height: 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(L10n.shared.string(.accessibilityFmt, summary.total)))
    }
}

private struct NotchRightExtensionShape: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(cornerRadius, rect.width, rect.height)

        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
