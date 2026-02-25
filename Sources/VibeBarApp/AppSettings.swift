import AppKit
import Foundation
import ServiceManagement
import SwiftUI
import VibeBarCore

// MARK: - Color Theme

struct StateColorSet {
    let runningDark: (r: Double, g: Double, b: Double)
    let runningLight: (r: Double, g: Double, b: Double)
    let awaitingDark: (r: Double, g: Double, b: Double)
    let awaitingLight: (r: Double, g: Double, b: Double)
    let idleDark: (r: Double, g: Double, b: Double)
    let idleLight: (r: Double, g: Double, b: Double)
}

enum ColorTheme: String, CaseIterable, Identifiable {
    case `default` = "default"
    case cyberpunk = "cyberpunk"
    case ocean = "ocean"
    case pastel = "pastel"
    case monochrome = "monochrome"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .default: return "默认"
        case .cyberpunk: return "赛博朋克"
        case .ocean: return "海洋"
        case .pastel: return "柔和"
        case .monochrome: return "单色"
        }
    }

    var colors: StateColorSet {
        switch self {
        case .default:
            return StateColorSet(
                runningDark:  (0.10, 0.82, 0.30), runningLight:  (0.08, 0.66, 0.24),
                awaitingDark: (1.00, 0.70, 0.00), awaitingLight: (0.90, 0.58, 0.00),
                idleDark:     (0.10, 0.57, 1.00), idleLight:     (0.00, 0.48, 1.00)
            )
        case .cyberpunk:
            // Neon cyan #00FFCC, Magenta #FF00AA, Violet #AA55FF
            return StateColorSet(
                runningDark:  (0.00, 1.00, 0.80), runningLight:  (0.00, 0.80, 0.64),
                awaitingDark: (1.00, 0.00, 0.67), awaitingLight: (0.85, 0.00, 0.56),
                idleDark:     (0.67, 0.33, 1.00), idleLight:     (0.53, 0.20, 0.87)
            )
        case .ocean:
            // Sea green #20B2AA, Coral #FF7F50, Royal blue #4169E1
            return StateColorSet(
                runningDark:  (0.13, 0.70, 0.67), runningLight:  (0.10, 0.58, 0.55),
                awaitingDark: (1.00, 0.50, 0.31), awaitingLight: (0.88, 0.40, 0.22),
                idleDark:     (0.25, 0.41, 0.88), idleLight:     (0.20, 0.33, 0.75)
            )
        case .pastel:
            // Mint #77DD77, Apricot #FFAA5C, Light blue #89CFF0
            return StateColorSet(
                runningDark:  (0.47, 0.87, 0.47), runningLight:  (0.35, 0.72, 0.35),
                awaitingDark: (1.00, 0.67, 0.36), awaitingLight: (0.88, 0.55, 0.25),
                idleDark:     (0.54, 0.81, 0.94), idleLight:     (0.40, 0.65, 0.82)
            )
        case .monochrome:
            // Bright white, Medium gray, Dark gray
            return StateColorSet(
                runningDark:  (0.95, 0.95, 0.95), runningLight:  (0.15, 0.15, 0.15),
                awaitingDark: (0.60, 0.60, 0.60), awaitingLight: (0.45, 0.45, 0.45),
                idleDark:     (0.35, 0.35, 0.35), idleLight:     (0.70, 0.70, 0.70)
            )
        }
    }
}

// MARK: - Icon Style

enum IconStyle: String, CaseIterable, Identifiable {
    case ring = "ring"
    case particles = "particles"
    case energyBar = "energyBar"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ring: return "环形"
        case .particles: return "粒子轨道"
        case .energyBar: return "能量条"
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
            updateLoginItem()
        }
    }

    @Published var autoCheckUpdates: Bool {
        didSet {
            UserDefaults.standard.set(autoCheckUpdates, forKey: "autoCheckUpdates")
        }
    }

    @Published var iconStyle: IconStyle {
        didSet {
            UserDefaults.standard.set(iconStyle.rawValue, forKey: "iconStyle")
        }
    }

    @Published var colorTheme: ColorTheme {
        didSet {
            UserDefaults.standard.set(colorTheme.rawValue, forKey: "colorTheme")
        }
    }

    private init() {
        launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
        autoCheckUpdates = UserDefaults.standard.bool(forKey: "autoCheckUpdates")
        let raw = UserDefaults.standard.string(forKey: "iconStyle") ?? ""
        iconStyle = IconStyle(rawValue: raw) ?? .ring
        let themeRaw = UserDefaults.standard.string(forKey: "colorTheme") ?? ""
        colorTheme = ColorTheme(rawValue: themeRaw) ?? .default
    }

    // MARK: - Unified color access

    /// NSColor for AppKit consumers (StatusItemController).
    func nsColor(for state: ToolActivityState) -> NSColor {
        if state == .unknown {
            return NSColor.secondaryLabelColor
        }
        let c = colorTheme.colors
        let (dark, light) = rgb(for: state, colors: c)
        return NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let t = isDark ? dark : light
            return NSColor(calibratedRed: t.r, green: t.g, blue: t.b, alpha: 1)
        }
    }

    /// SwiftUI Color for view consumers (MenuContentView / StatusGlyph).
    func swiftUIColor(for state: ToolActivityState, colorScheme: ColorScheme) -> Color {
        if state == .unknown {
            return .secondary
        }
        let c = colorTheme.colors
        let (dark, light) = rgb(for: state, colors: c)
        let t = colorScheme == .dark ? dark : light
        return Color(red: t.r, green: t.g, blue: t.b)
    }

    private func rgb(
        for state: ToolActivityState,
        colors c: StateColorSet
    ) -> (dark: (r: Double, g: Double, b: Double), light: (r: Double, g: Double, b: Double)) {
        switch state {
        case .running:      return (c.runningDark,  c.runningLight)
        case .awaitingInput: return (c.awaitingDark, c.awaitingLight)
        case .idle:          return (c.idleDark,     c.idleLight)
        case .unknown:       return ((0, 0, 0), (0, 0, 0)) // unreachable
        }
    }

    private func updateLoginItem() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Registration may fail in source/debug builds — silently ignore.
        }
    }
}
