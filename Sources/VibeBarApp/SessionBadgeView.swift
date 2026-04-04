import AppKit
import SwiftUI

enum SessionBadgeTone: String, Sendable {
    case client
    case manager
    case origin
    case neutral
}

struct SessionBadge: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case client
        case manager
        case origin
        case tty
    }

    let kind: Kind
    let text: String
    let tone: SessionBadgeTone

    var id: String {
        "\(kind.rawValue):\(text)"
    }
}

enum SessionBadgeStyle {
    static func fillColor(for tone: SessionBadgeTone) -> Color {
        Color(nsColor: nsFillColor(for: tone))
    }

    static func borderColor(for tone: SessionBadgeTone) -> Color {
        Color(nsColor: nsBorderColor(for: tone))
    }

    static func textColor(for tone: SessionBadgeTone) -> Color {
        Color(nsColor: nsTextColor(for: tone))
    }

    static func nsFillColor(for tone: SessionBadgeTone, highlighted: Bool = false) -> NSColor {
        if highlighted {
            return NSColor.white.withAlphaComponent(0.14)
        }

        switch tone {
        case .client:
            return NSColor.systemBlue.withAlphaComponent(0.14)
        case .manager:
            return NSColor.systemGreen.withAlphaComponent(0.16)
        case .origin:
            return NSColor.systemOrange.withAlphaComponent(0.16)
        case .neutral:
            return NSColor.secondaryLabelColor.withAlphaComponent(0.12)
        }
    }

    static func nsBorderColor(for tone: SessionBadgeTone, highlighted: Bool = false) -> NSColor {
        if highlighted {
            return NSColor.white.withAlphaComponent(0.28)
        }

        switch tone {
        case .client:
            return NSColor.systemBlue.withAlphaComponent(0.28)
        case .manager:
            return NSColor.systemGreen.withAlphaComponent(0.30)
        case .origin:
            return NSColor.systemOrange.withAlphaComponent(0.30)
        case .neutral:
            return NSColor.secondaryLabelColor.withAlphaComponent(0.24)
        }
    }

    static func nsTextColor(for tone: SessionBadgeTone, highlighted: Bool = false) -> NSColor {
        if highlighted {
            return .white
        }

        switch tone {
        case .client:
            return NSColor.systemBlue
        case .manager:
            return NSColor.systemGreen
        case .origin:
            return NSColor.systemOrange
        case .neutral:
            return NSColor.secondaryLabelColor
        }
    }
}

struct SessionBadgeView: View {
    let badge: SessionBadge
    var compact = false

    var body: some View {
        Text(badge.text)
            .font(.system(size: compact ? 9 : 10, weight: .semibold))
            .foregroundStyle(SessionBadgeStyle.textColor(for: badge.tone))
            .lineLimit(1)
            .padding(.horizontal, compact ? 7 : 8)
            .frame(height: compact ? 16 : 18)
            .background(
                Capsule(style: .continuous)
                    .fill(SessionBadgeStyle.fillColor(for: badge.tone))
            )
            .overlay {
                Capsule(style: .continuous)
                    .stroke(SessionBadgeStyle.borderColor(for: badge.tone), lineWidth: 1)
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
