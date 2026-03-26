import SwiftUI

enum NotchPanelStyle {
    static let cornerRadius: CGFloat = 11
    static let collapsedJoinRadius: CGFloat = 11
    static let fillColor = Color(red: 0.07, green: 0.07, blue: 0.08)
    static let strokeColor = Color.white.opacity(0.07)
    static let shadowColor = Color.black.opacity(0.38)
    static let topHighlight = LinearGradient(
        colors: [
            Color.white.opacity(0.035),
            Color.white.opacity(0),
        ],
        startPoint: .top,
        endPoint: .bottom
    )
    static let topHighlightHeight: CGFloat = 16
}
