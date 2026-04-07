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
        Color(nsColor: resolvedColors(for: badge).fillColor)
    }

    static func borderColor(for badge: SessionBadge) -> Color {
        Color(nsColor: resolvedColors(for: badge).borderColor)
    }

    static func textColor(for badge: SessionBadge) -> Color {
        Color(nsColor: resolvedColors(for: badge).textColor)
    }

    static func nsFillColor(for badge: SessionBadge, highlighted: Bool = false) -> NSColor {
        resolvedColors(for: badge, highlighted: highlighted).fillColor
    }

    static func nsBorderColor(for badge: SessionBadge, highlighted: Bool = false) -> NSColor {
        resolvedColors(for: badge, highlighted: highlighted).borderColor
    }

    static func nsTextColor(for badge: SessionBadge, highlighted: Bool = false) -> NSColor {
        resolvedColors(for: badge, highlighted: highlighted).textColor
    }

    static func resolvedColors(
        for badge: SessionBadge,
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
            let baseColor = accentBaseColor ?? AppSettings.shared.nsColor(for: state)
            return ResolvedColors(
                fillColor: baseColor.withAlphaComponent(0.16),
                borderColor: baseColor.withAlphaComponent(0.32),
                textColor: baseColor
            )
        }

        switch badge.tone {
        case .client:
            return ResolvedColors(
                fillColor: .systemBlue.withAlphaComponent(0.14),
                borderColor: .systemBlue.withAlphaComponent(0.28),
                textColor: .systemBlue
            )
        case .manager:
            return ResolvedColors(
                fillColor: .systemGreen.withAlphaComponent(0.16),
                borderColor: .systemGreen.withAlphaComponent(0.30),
                textColor: .systemGreen
            )
        case .origin:
            return ResolvedColors(
                fillColor: .systemOrange.withAlphaComponent(0.16),
                borderColor: .systemOrange.withAlphaComponent(0.30),
                textColor: .systemOrange
            )
        case .neutral, .status:
            return ResolvedColors(
                fillColor: .secondaryLabelColor.withAlphaComponent(0.12),
                borderColor: .secondaryLabelColor.withAlphaComponent(0.24),
                textColor: .secondaryLabelColor
            )
        }
    }
}

struct SessionBadgeView: View {
    let badge: SessionBadge
    var compact = false

    var body: some View {
        Text(badge.text)
            .font(.system(size: compact ? 9 : 10, weight: .semibold))
            .foregroundStyle(SessionBadgeStyle.textColor(for: badge))
            .lineLimit(1)
            .padding(.horizontal, compact ? 7 : 8)
            .frame(height: compact ? 16 : 18)
            .background(
                Capsule(style: .continuous)
                    .fill(SessionBadgeStyle.fillColor(for: badge))
            )
            .overlay {
                Capsule(style: .continuous)
                    .stroke(SessionBadgeStyle.borderColor(for: badge), lineWidth: 1)
            }
            .fixedSize(horizontal: true, vertical: true)
    }
}

struct SessionBadgeStrip: View {
    let badges: [SessionBadge]
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 5 : 6) {
            ForEach(badges) { badge in
                SessionBadgeView(badge: badge, compact: compact)
            }
        }
        .fixedSize(horizontal: true, vertical: true)
    }
}
