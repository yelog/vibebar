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
    static let strokeColor = Color.clear
    static let shadowColor = Color.clear
    static let topHighlight = LinearGradient(
        colors: [
            Color.clear,
            Color.clear,
        ],
        startPoint: .top,
        endPoint: .bottom
    )
    static let topHighlightHeight: CGFloat = 16
}
