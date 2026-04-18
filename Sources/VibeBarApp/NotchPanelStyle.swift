import AppKit
import SwiftUI

import VibeBarCore

enum NotchPanelStyle {
    static let cornerRadius: CGFloat = 14
    static let bottomCornerRadius: CGFloat = 14
    static let collapsedJoinRadius: CGFloat = 12
    static let bodySideInset: CGFloat = 4
    static let horizontalPadding: CGFloat = 14
    static let iconButtonSize: CGFloat = 28
    static let smallButtonCornerRadius: CGFloat = 9
    static let topCornerStraightDepth: CGFloat = 0
    static let topShoulderDepth: CGFloat = 8
    static let topShoulderInset: CGFloat = 3
    static let fillColor = Color(red: 0.027, green: 0.035, blue: 0.043)
    static let surfaceElevated = Color(red: 0.047, green: 0.063, blue: 0.078)
    static let surfaceCard = Color(red: 0.067, green: 0.086, blue: 0.106)
    static let strokeColor = Color.white.opacity(0.08)
    static let strongStrokeColor = Color.white.opacity(0.14)
    static let dividerColor = Color.white.opacity(0.07)
    static let hoverFillColor = Color.white.opacity(0.05)
    static let pressedFillColor = Color.white.opacity(0.10)
    static let primaryTextColor = Color(red: 0.953, green: 0.965, blue: 0.980)
    static let secondaryTextColor = Color(red: 0.651, green: 0.686, blue: 0.729)
    static let tertiaryTextColor = Color(red: 0.435, green: 0.471, blue: 0.514)
    static let accentColor = Color(red: 0.337, green: 0.761, blue: 1.000)
    static let neutralAccentColor = Color(red: 0.494, green: 0.580, blue: 0.667)
    static let warningColor = Color(red: 0.957, green: 0.718, blue: 0.251)
    static let shadowColor = Color.black.opacity(0.42)
    static let topHighlight = LinearGradient(
        colors: [
            Color(red: 0.72, green: 0.84, blue: 1.00).opacity(0.10),
            Color.clear,
        ],
        startPoint: .top,
        endPoint: .bottom
    )
    static let topHighlightHeight: CGFloat = 14

    static func color(for state: ToolActivityState) -> Color {
        switch state {
        case .running:
            return accentColor
        case .awaitingInput:
            return warningColor
        case .idle:
            return neutralAccentColor
        case .unknown:
            return secondaryTextColor
        }
    }

    static func nsColor(for state: ToolActivityState) -> NSColor {
        NSColor(color(for: state))
    }
}
