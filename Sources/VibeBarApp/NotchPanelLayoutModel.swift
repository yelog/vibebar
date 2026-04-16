import AppKit

enum NotchPanelPhase: Sendable, Equatable {
    case collapsed
    case expanding
    case expanded
    case collapsing

    var isTransitioning: Bool {
        switch self {
        case .expanding, .collapsing:
            true
        case .collapsed, .expanded:
            false
        }
    }
}

struct NotchPanelLayoutModel: Sendable, Equatable {
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

    var hostingReferenceFrame: NSRect {
        switch phase {
        case .collapsed:
            collapsedFrame
        case .expanded, .expanding, .collapsing:
            expandedFrame
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

    var usesBridgeTopShellPresentation: Bool {
        switch phase {
        case .collapsed:
            false
        case .expanding, .expanded, .collapsing:
            true
        }
    }

    var allowsBodyHitTesting: Bool {
        phase == .expanded
    }

    var bodyOpacity: Double {
        switch phase {
        case .collapsed:
            0
        case .expanding:
            1
        case .expanded:
            1
        case .collapsing:
            0.42
        }
    }

    var bodyOffsetY: CGFloat {
        switch phase {
        case .collapsed:
            -12
        case .expanding:
            0
        case .expanded:
            0
        case .collapsing:
            -8
        }
    }

    var bodyBlurRadius: CGFloat {
        switch phase {
        case .collapsed:
            6
        case .expanding:
            0
        case .expanded:
            0
        case .collapsing:
            4
        }
    }

    var bodyScale: CGFloat {
        switch phase {
        case .collapsed:
            0.985
        case .expanding:
            1
        case .expanded:
            1
        case .collapsing:
            0.988
        }
    }

    var surfaceOpacity: Double {
        switch phase {
        case .collapsed:
            0
        case .expanding:
            1
        case .expanded:
            1
        case .collapsing:
            0.9
        }
    }
}
