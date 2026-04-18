import AppKit
import SwiftUI
import VibeBarCore

enum SessionBadgeTone: String, Sendable {
    case client
    case manager
    case origin
    case neutral
    case status
}

struct SessionBadge: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case client
        case tab
        case manager
        case origin
        case tty
        case duration
    }

    let kind: Kind
    let text: String
    let tone: SessionBadgeTone
    let accentState: ToolActivityState?

    init(
        kind: Kind,
        text: String,
        tone: SessionBadgeTone,
        accentState: ToolActivityState? = nil
    ) {
        self.kind = kind
        self.text = text
        self.tone = tone
        self.accentState = accentState
    }

    var id: String {
        "\(kind.rawValue):\(text)"
    }
}

@MainActor
enum SessionBadgeStyle {
    struct ResolvedColors {
        let fillColor: NSColor
        let borderColor: NSColor
        let textColor: NSColor
    }

    static func fillColor(for badge: SessionBadge) -> Color {
        fillColor(for: badge, appearance: .standard)
    }

    static func fillColor(for badge: SessionBadge, appearance: PanelChromeAppearance) -> Color {
        Color(nsColor: resolvedColors(for: badge, appearance: appearance).fillColor)
    }

    static func borderColor(for badge: SessionBadge) -> Color {
        borderColor(for: badge, appearance: .standard)
    }

    static func borderColor(for badge: SessionBadge, appearance: PanelChromeAppearance) -> Color {
        Color(nsColor: resolvedColors(for: badge, appearance: appearance).borderColor)
    }

    static func textColor(for badge: SessionBadge) -> Color {
        textColor(for: badge, appearance: .standard)
    }

    static func textColor(for badge: SessionBadge, appearance: PanelChromeAppearance) -> Color {
        Color(nsColor: resolvedColors(for: badge, appearance: appearance).textColor)
    }

    static func nsFillColor(for badge: SessionBadge, highlighted: Bool = false) -> NSColor {
        nsFillColor(for: badge, appearance: .standard, highlighted: highlighted)
    }

    static func nsFillColor(
        for badge: SessionBadge,
        appearance: PanelChromeAppearance,
        highlighted: Bool = false
    ) -> NSColor {
        resolvedColors(for: badge, appearance: appearance, highlighted: highlighted).fillColor
    }

    static func nsBorderColor(for badge: SessionBadge, highlighted: Bool = false) -> NSColor {
        nsBorderColor(for: badge, appearance: .standard, highlighted: highlighted)
    }

    static func nsBorderColor(
        for badge: SessionBadge,
        appearance: PanelChromeAppearance,
        highlighted: Bool = false
    ) -> NSColor {
        resolvedColors(for: badge, appearance: appearance, highlighted: highlighted).borderColor
    }

    static func nsTextColor(for badge: SessionBadge, highlighted: Bool = false) -> NSColor {
        nsTextColor(for: badge, appearance: .standard, highlighted: highlighted)
    }

    static func nsTextColor(
        for badge: SessionBadge,
        appearance: PanelChromeAppearance,
        highlighted: Bool = false
    ) -> NSColor {
        resolvedColors(for: badge, appearance: appearance, highlighted: highlighted).textColor
    }

    static func resolvedColors(
        for badge: SessionBadge,
        appearance: PanelChromeAppearance = .standard,
        accentBaseColor: NSColor? = nil,
        highlighted: Bool = false
    ) -> ResolvedColors {
        if highlighted {
            return ResolvedColors(
                fillColor: .white.withAlphaComponent(0.14),
                borderColor: .white.withAlphaComponent(0.28),
                textColor: .white
            )
        }

        if let state = badge.accentState {
            let baseColor = accentBaseColor ?? accentColor(for: state, appearance: appearance)
            return ResolvedColors(
                fillColor: baseColor.withAlphaComponent(0.16),
                borderColor: baseColor.withAlphaComponent(0.32),
                textColor: baseColor
            )
        }

        switch badge.tone {
        case .client:
            return appearance == .notch ? notchClientColors : standardClientColors
        case .manager:
            return appearance == .notch ? notchManagerColors : standardManagerColors
        case .origin:
            return appearance == .notch ? notchOriginColors : standardOriginColors
        case .neutral, .status:
            return appearance == .notch ? notchNeutralColors : standardNeutralColors
        }
    }

    private static func accentColor(for state: ToolActivityState, appearance: PanelChromeAppearance) -> NSColor {
        switch appearance {
        case .standard:
            return AppSettings.shared.nsColor(for: state)
        case .notch:
            return NotchPanelStyle.nsColor(for: state)
        }
    }

    private static var standardClientColors: ResolvedColors {
        ResolvedColors(
            fillColor: .systemBlue.withAlphaComponent(0.14),
            borderColor: .systemBlue.withAlphaComponent(0.28),
            textColor: .systemBlue
        )
    }

    private static var standardManagerColors: ResolvedColors {
        ResolvedColors(
            fillColor: .systemGreen.withAlphaComponent(0.16),
            borderColor: .systemGreen.withAlphaComponent(0.30),
            textColor: .systemGreen
        )
    }

    private static var standardOriginColors: ResolvedColors {
        ResolvedColors(
            fillColor: .systemOrange.withAlphaComponent(0.16),
            borderColor: .systemOrange.withAlphaComponent(0.30),
            textColor: .systemOrange
        )
    }

    private static var standardNeutralColors: ResolvedColors {
        ResolvedColors(
            fillColor: .secondaryLabelColor.withAlphaComponent(0.12),
            borderColor: .secondaryLabelColor.withAlphaComponent(0.24),
            textColor: .secondaryLabelColor
        )
    }

    private static var notchClientColors: ResolvedColors {
        let base = NSColor(NotchPanelStyle.neutralAccentColor)
        return ResolvedColors(
            fillColor: base.withAlphaComponent(0.16),
            borderColor: base.withAlphaComponent(0.28),
            textColor: base.withAlphaComponent(0.95)
        )
    }

    private static var notchManagerColors: ResolvedColors {
        let base = NSColor(NotchPanelStyle.neutralAccentColor)
        return ResolvedColors(
            fillColor: base.withAlphaComponent(0.14),
            borderColor: base.withAlphaComponent(0.24),
            textColor: base.withAlphaComponent(0.88)
        )
    }

    private static var notchOriginColors: ResolvedColors {
        let base = NSColor(NotchPanelStyle.neutralAccentColor)
        return ResolvedColors(
            fillColor: base.withAlphaComponent(0.14),
            borderColor: base.withAlphaComponent(0.24),
            textColor: base.withAlphaComponent(0.92)
        )
    }

    private static var notchNeutralColors: ResolvedColors {
        ResolvedColors(
            fillColor: .secondaryLabelColor.withAlphaComponent(0.10),
            borderColor: .secondaryLabelColor.withAlphaComponent(0.20),
            textColor: NSColor(NotchPanelStyle.secondaryTextColor)
        )
    }
}

struct SessionBadgeView: View {
    let badge: SessionBadge
    var compact = false
    var appearance: PanelChromeAppearance = .standard

    var body: some View {
        Text(badge.text)
            .font(.system(size: compact ? compactFontSize : 10, weight: .semibold))
            .foregroundStyle(SessionBadgeStyle.textColor(for: badge, appearance: appearance))
            .lineLimit(1)
            .minimumScaleFactor(compact ? compactMinimumScaleFactor : 1)
            .padding(.horizontal, compact ? compactHorizontalPadding : 8)
            .frame(height: compact ? compactHeight : 18)
            .background(
                Capsule(style: .continuous)
                    .fill(SessionBadgeStyle.fillColor(for: badge, appearance: appearance))
            )
            .overlay {
                Capsule(style: .continuous)
                    .stroke(SessionBadgeStyle.borderColor(for: badge, appearance: appearance), lineWidth: 1)
            }
            .fixedSize(horizontal: appearance == .notch ? false : true, vertical: true)
    }

    private var compactFontSize: CGFloat {
        appearance == .notch ? 8.5 : 9
    }

    private var compactHorizontalPadding: CGFloat {
        appearance == .notch ? 7 : 7
    }

    private var compactHeight: CGFloat {
        appearance == .notch ? 18 : 16
    }

    private var compactMinimumScaleFactor: CGFloat {
        appearance == .notch ? 0.78 : 1
    }
}

struct SessionBadgeStrip: View {
    let badges: [SessionBadge]
    var compact = false
    var appearance: PanelChromeAppearance = .standard

    var body: some View {
        HStack(spacing: compact ? 5 : 6) {
            ForEach(displayedBadges) { badge in
                SessionBadgeView(badge: badge, compact: compact, appearance: appearance)
            }
        }
        .fixedSize(horizontal: appearance == .notch ? false : true, vertical: true)
    }

    private var displayedBadges: [SessionBadge] {
        switch appearance {
        case .standard:
            return badges
        case .notch:
            return Array(badges.prefix(2))
        }
    }
}
