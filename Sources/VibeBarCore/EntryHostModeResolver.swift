import Foundation

public enum EntryHostMode: Sendable, Equatable {
    case menuBar
    case notch
}

public enum EntryHostModeResolver {
    public static func resolve(
        preferenceEnabled: Bool,
        primaryDisplaySupportsNotch: Bool,
        temporarilyBlocked: Bool
    ) -> EntryHostMode {
        guard preferenceEnabled, primaryDisplaySupportsNotch, !temporarilyBlocked else {
            return .menuBar
        }

        return .notch
    }
}
