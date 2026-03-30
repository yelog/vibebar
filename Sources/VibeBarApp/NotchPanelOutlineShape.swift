import SwiftUI

struct NotchPanelOutlineShape: Shape {
    let bottomCornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let bodySideInset = min(NotchPanelStyle.bodySideInset, rect.width / 2)
        let topShoulderDepth = min(
            max(NotchPanelStyle.topShoulderDepth, NotchPanelStyle.topCornerStraightDepth),
            rect.height
        )
        let topCornerStraightDepth = min(NotchPanelStyle.topCornerStraightDepth, topShoulderDepth)
        let bodyMinX = rect.minX + bodySideInset
        let bodyMaxX = rect.maxX - bodySideInset
        let bodyWidth = max(bodyMaxX - bodyMinX, 0)
        let bottomRadius = min(
            bottomCornerRadius,
            bodyWidth / 2,
            max(rect.height - topShoulderDepth, 0)
        )
        let shoulderSpan = max(topShoulderDepth - topCornerStraightDepth, 0)
        let shoulderCurveDepth = max(shoulderSpan * 0.55, 1)
        let shoulderCurveEndY = rect.minY + topCornerStraightDepth + shoulderCurveDepth
        let shoulderUpperControlY = max(shoulderSpan * 0.18, 0.5)
        let shoulderLowerControlY = max(shoulderSpan * 0.22, 0.75)
        let shoulderLeadInset = min(NotchPanelStyle.topShoulderInset, bodySideInset)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))

        if shoulderSpan > 0, bodySideInset > 0 {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + topCornerStraightDepth))
            path.addCurve(
                to: CGPoint(x: bodyMaxX, y: shoulderCurveEndY),
                control1: CGPoint(x: rect.maxX - shoulderLeadInset, y: rect.minY + topCornerStraightDepth + shoulderUpperControlY),
                control2: CGPoint(x: bodyMaxX, y: shoulderCurveEndY - shoulderLowerControlY)
            )
            path.addLine(to: CGPoint(x: bodyMaxX, y: rect.minY + topShoulderDepth))
        } else {
            path.addLine(to: CGPoint(x: bodyMaxX, y: rect.minY + topShoulderDepth))
        }

        if bottomRadius > 0 {
            path.addLine(to: CGPoint(x: bodyMaxX, y: rect.maxY - bottomRadius))
            path.addQuadCurve(
                to: CGPoint(x: bodyMaxX - bottomRadius, y: rect.maxY),
                control: CGPoint(x: bodyMaxX, y: rect.maxY)
            )
            path.addLine(to: CGPoint(x: bodyMinX + bottomRadius, y: rect.maxY))
            path.addQuadCurve(
                to: CGPoint(x: bodyMinX, y: rect.maxY - bottomRadius),
                control: CGPoint(x: bodyMinX, y: rect.maxY)
            )
        } else {
            path.addLine(to: CGPoint(x: bodyMaxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: bodyMinX, y: rect.maxY))
        }

        if shoulderSpan > 0, bodySideInset > 0 {
            path.addLine(to: CGPoint(x: bodyMinX, y: rect.minY + topShoulderDepth))
            path.addLine(to: CGPoint(x: bodyMinX, y: shoulderCurveEndY))
            path.addCurve(
                to: CGPoint(x: rect.minX, y: rect.minY + topCornerStraightDepth),
                control1: CGPoint(x: bodyMinX, y: shoulderCurveEndY - shoulderLowerControlY),
                control2: CGPoint(x: rect.minX + shoulderLeadInset, y: rect.minY + topCornerStraightDepth + shoulderUpperControlY)
            )
        } else {
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topShoulderDepth))
        }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
