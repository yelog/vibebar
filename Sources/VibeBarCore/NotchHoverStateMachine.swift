import Foundation

public enum NotchHoverTiming {
    public static let expandDelayMilliseconds = 150
    public static let collapseDelayMilliseconds = 240
}

public struct NotchHoverStateMachine: Sendable {
    public enum Event: Sendable {
        case pointerEnteredHotZone
        case pointerExitedAllZones
        case expandTimerFired
        case collapseTimerFired
    }

    public enum State: Sendable {
        case collapsed
        case pendingExpand
        case expanded
        case pendingCollapse
    }

    public enum Effect: Sendable {
        case none
        case scheduleExpand
        case cancelExpand
        case scheduleCollapse
        case cancelCollapse
        case expandNow
        case collapseNow
    }

    public private(set) var state: State

    public init(state: State = .collapsed) {
        self.state = state
    }

    public mutating func reduce(_ event: Event) -> Effect {
        switch (state, event) {
        case (.collapsed, .pointerEnteredHotZone):
            state = .pendingExpand
            return .scheduleExpand

        case (.pendingExpand, .pointerExitedAllZones):
            state = .collapsed
            return .cancelExpand

        case (.pendingExpand, .expandTimerFired):
            state = .expanded
            return .expandNow

        case (.expanded, .pointerExitedAllZones):
            state = .pendingCollapse
            return .scheduleCollapse

        case (.pendingCollapse, .pointerEnteredHotZone):
            state = .expanded
            return .cancelCollapse

        case (.pendingCollapse, .collapseTimerFired):
            state = .collapsed
            return .collapseNow

        case (.collapsed, _),
             (.pendingExpand, .pointerEnteredHotZone),
             (.pendingExpand, .collapseTimerFired),
             (.expanded, .pointerEnteredHotZone),
             (.expanded, .expandTimerFired),
             (.expanded, .collapseTimerFired),
             (.pendingCollapse, .pointerExitedAllZones),
             (.pendingCollapse, .expandTimerFired):
            return .none
        }
    }
}
