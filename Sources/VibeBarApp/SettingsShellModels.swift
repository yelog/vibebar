import SwiftUI
import VibeBarCore

enum SettingsPage: String, CaseIterable, Identifiable, Sendable {
    case general
    case cli
    case appearance
    case usage
    case hooks
    case about

    var id: String { rawValue }

    var titleKey: L10nKey {
        switch self {
        case .general:
            return .tabGeneral
        case .cli:
            return .tabCLI
        case .appearance:
            return .tabAppearance
        case .usage:
            return .tabUsage
        case .hooks:
            return .tabHooks
        case .about:
            return .tabAbout
        }
    }

    var iconName: String {
        switch self {
        case .general:
            return "gearshape.fill"
        case .cli:
            return "terminal.fill"
        case .appearance:
            return "paintpalette.fill"
        case .usage:
            return "chart.xyaxis.line"
        case .hooks:
            return "bolt.fill"
        case .about:
            return "info.circle.fill"
        }
    }

    var shortcutKey: String {
        switch self {
        case .general:
            return "1"
        case .cli:
            return "2"
        case .appearance:
            return "3"
        case .usage:
            return "4"
        case .hooks:
            return "5"
        case .about:
            return "6"
        }
    }

    var shortcutEquivalent: KeyEquivalent {
        KeyEquivalent(Character(shortcutKey))
    }

    var presentation: SettingsPagePresentation {
        switch self {
        case .cli:
            return .fullBleed
        default:
            return .standardScrollable
        }
    }
}

enum SettingsPagePresentation: Sendable {
    case standardScrollable
    case fullBleed
}

struct SettingsWindowPolicy: Sendable {
    let defaultContentSize: CGSize
    let minContentSize: CGSize
    let maxContentSize: CGSize
    let resizesPerPage: Bool

    static let `default` = SettingsWindowPolicy(
        defaultContentSize: CGSize(width: 780, height: 700),
        minContentSize: CGSize(width: 720, height: 620),
        maxContentSize: CGSize(width: 1100, height: 900),
        resizesPerPage: false
    )
}
