import AppKit

enum NotchPanelPhase: Sendable {
    case collapsed
    case expanding
    case expanded
    case collapsing
}

struct NotchPanelLayoutModel: Sendable {
    var phase: NotchPanelPhase
    var collapsedFrame: NSRect = .zero
    var expandedFrame: NSRect = .zero

    var targetFrame: NSRect {
        switch phase {
        case .collapsed, .collapsing:
            collapsedFrame
        case .expanded, .expanding:
            expandedFrame
        }
    }

    var hostingSize: NSSize {
        switch phase {
        case .collapsed:
            collapsedFrame.size
        case .expanded, .expanding, .collapsing:
            expandedFrame.size
        }
    }

    var showsTopShell: Bool {
        true
    }

    var showsExpandedBody: Bool {
        phase != .collapsed
    }

    var showsPanelBackground: Bool {
        phase != .collapsed
    }

    var usesExpandedHitFrame: Bool {
        phase == .expanding || phase == .expanded
    }

    var allowsBodyHitTesting: Bool {
        phase == .expanded
    }

    var bodyOpacity: Double {
        switch phase {
        case .collapsed:
            0
        case .expanding, .expanded:
            1
        case .collapsing:
            0.92
        }
    }
}
