import SwiftUI

enum NotchPanelStyle {
    static let cornerRadius: CGFloat = 11
    static let bottomCornerRadius: CGFloat = 11
    static let collapsedJoinRadius: CGFloat = 11
    static let bodySideInset: CGFloat = 4
    static let topCornerStraightDepth: CGFloat = 0
    static let topShoulderDepth: CGFloat = 8
    static let topShoulderInset: CGFloat = 3
    static let fillColor = Color.black
    static let strokeColor = Color.white.opacity(0.06)
    static let shadowColor = Color.clear
    static let topHighlight = LinearGradient(
        colors: [
            Color.white.opacity(0.08),
            Color.clear,
        ],
        startPoint: .top,
        endPoint: .bottom
    )
    static let topHighlightHeight: CGFloat = 16
}
