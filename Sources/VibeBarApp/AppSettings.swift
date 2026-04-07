import AppKit
import Foundation
import ServiceManagement
import SwiftUI
import VibeBarCore

// MARK: - Update Channel

public enum UpdateChannel: String, CaseIterable, Identifiable, Sendable {
    case stable = "stable"
    case beta = "beta"

    public var id: String { rawValue }

    @MainActor public var displayName: String {
        switch self {
        case .stable: return L10n.shared.string(.updateChannelStable)
        case .beta:   return L10n.shared.string(.updateChannelBeta)
        }
    }
}



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
    case custom = "custom"

    var id: String { rawValue }

    @MainActor var displayName: String {
        switch self {
        case .default: return L10n.shared.string(.themeDefault)
        case .cyberpunk: return L10n.shared.string(.themeCyberpunk)
        case .ocean: return L10n.shared.string(.themeOcean)
        case .pastel: return L10n.shared.string(.themePastel)
        case .monochrome: return L10n.shared.string(.themeMonochrome)
        case .custom: return L10n.shared.string(.themeCustom)
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
        case .custom:
            // Fallback; actual custom colors are read from AppSettings properties
            return ColorTheme.default.colors
        }
    }
}

// MARK: - Icon Style

enum IconStyle: String, CaseIterable, Identifiable {
    case ring = "ring"
    case particles = "particles"
    case energyBar = "energyBar"
    case iceGrid = "iceGrid"

    var id: String { rawValue }

    @MainActor var displayName: String {
        switch self {
        case .ring: return L10n.shared.string(.iconRing)
        case .particles: return L10n.shared.string(.iconParticles)
        case .energyBar: return L10n.shared.string(.iconEnergyBar)
        case .iceGrid: return L10n.shared.string(.iconIceGrid)
        }
    }
}

enum SessionGroupingMode: String, CaseIterable, Identifiable, Sendable {
    case none = "none"
    case tool = "tool"
    case project = "project"

    var id: String { rawValue }

    @MainActor var displayName: String {
        switch self {
        case .none:
            return L10n.shared.string(.sessionGroupingNone)
        case .tool:
            return L10n.shared.string(.sessionGroupingTool)
        case .project:
            return L10n.shared.string(.sessionGroupingProject)
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

    @Published var notchDisplayEnabled: Bool {
        didSet {
            UserDefaults.standard.set(notchDisplayEnabled, forKey: "notchDisplayEnabled")
        }
    }

    @Published var autoCheckUpdates: Bool {
        didSet {
            UserDefaults.standard.set(autoCheckUpdates, forKey: "autoCheckUpdates")
        }
    }

    @Published var updateChannel: UpdateChannel {
        didSet {
            UserDefaults.standard.set(updateChannel.rawValue, forKey: "updateChannel")
            UpdateChecker.shared.updateFeedURL()
        }
    }


    @Published var notificationConfig: NotificationConfig {
        didSet {
            if let data = try? JSONEncoder().encode(notificationConfig) {
                UserDefaults.standard.set(data, forKey: "notificationConfig")
            }
        }
    }

    // Legacy property for backward compatibility
    @Published var notifyAwaitingInput: Bool {
        didSet {
            // Sync with notificationConfig
            var newConfig = notificationConfig
            newConfig.isEnabled = notifyAwaitingInput
            if notifyAwaitingInput {
                if !newConfig.enabledTransitions.contains(.runningToAwaiting) {
                    newConfig.enabledTransitions.append(.runningToAwaiting)
                }
            }
            notificationConfig = newConfig
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

    @Published var sessionGroupingMode: SessionGroupingMode {
        didSet {
            UserDefaults.standard.set(sessionGroupingMode.rawValue, forKey: "sessionGroupingMode")
        }
    }

    @Published var usageSources: [UsageSource] {
        didSet {
            UserDefaults.standard.set(usageSources.map(\.rawValue), forKey: "usageSources")
        }
    }

    @Published var usageRefreshCadence: UsageRefreshCadence {
        didSet {
            UserDefaults.standard.set(usageRefreshCadence.rawValue, forKey: "usageRefreshCadence")
        }
    }

    @Published var usageVisualizationStyle: UsageVisualizationStyle {
        didSet {
            UserDefaults.standard.set(usageVisualizationStyle.rawValue, forKey: "usageVisualizationStyle")
        }
    }

    @Published var usageMetric: UsageMetric {
        didSet {
            UserDefaults.standard.set(usageMetric.rawValue, forKey: "usageMetric")
        }
    }

    @Published var usageGranularity: UsageGranularity {
        didSet {
            UserDefaults.standard.set(usageGranularity.rawValue, forKey: "usageGranularity")
        }
    }

    @Published var usageSeriesGrouping: UsageSeriesGrouping {
        didSet {
            UserDefaults.standard.set(usageSeriesGrouping.rawValue, forKey: "usageSeriesGrouping")
        }
    }

    @Published var usageEnabled: Bool {
        didSet {
            UserDefaults.standard.set(usageEnabled, forKey: "usageEnabled")
        }
    }

    @Published var usageFullRefreshInterval: UsageFullRefreshInterval {
        didSet {
            UserDefaults.standard.set(usageFullRefreshInterval.rawValue, forKey: "usageFullRefreshInterval")
        }
    }

    @Published var customRunningColor: Color {
        didSet { persistCustomColor(customRunningColor, forKey: "customRunningHex") }
    }

    @Published var customAwaitingColor: Color {
        didSet { persistCustomColor(customAwaitingColor, forKey: "customAwaitingHex") }
    }

    @Published var customIdleColor: Color {
        didSet { persistCustomColor(customIdleColor, forKey: "customIdleHex") }
    }

    private init() {
        UserDefaults.standard.register(defaults: [
            "autoCheckUpdates": true,
            "groupSessionsByTool": true,
            "notchDisplayEnabled": false,
            "usageEnabled": false,
            "usageSources": UsageSource.allCases.map(\.rawValue),
            "usageRefreshCadence": UsageRefreshCadence.fiveMinutes.rawValue,
            "usageVisualizationStyle": UsageVisualizationStyle.githubHeatmap.rawValue,
            "usageMetric": UsageMetric.tokens.rawValue,
            "usageGranularity": UsageGranularity.day.rawValue,
            "usageSeriesGrouping": UsageSeriesGrouping.total.rawValue,
            "usageFullRefreshInterval": UsageFullRefreshInterval.twentyFourHours.rawValue,
        ])
        launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
        notchDisplayEnabled = UserDefaults.standard.bool(forKey: "notchDisplayEnabled")
        autoCheckUpdates = UserDefaults.standard.bool(forKey: "autoCheckUpdates")
        sessionGroupingMode = Self.loadSessionGroupingModeWithMigration()
        usageEnabled = UserDefaults.standard.bool(forKey: "usageEnabled")
        usageSources = Self.loadUsageSources()
        usageRefreshCadence = UsageRefreshCadence(
            rawValue: UserDefaults.standard.integer(forKey: "usageRefreshCadence")
        ) ?? .fiveMinutes
        usageVisualizationStyle = UsageVisualizationStyle(
            rawValue: UserDefaults.standard.string(forKey: "usageVisualizationStyle") ?? ""
        ) ?? .githubHeatmap
        usageMetric = UsageMetric(
            rawValue: UserDefaults.standard.string(forKey: "usageMetric") ?? ""
        ) ?? .tokens
        usageGranularity = UsageGranularity(
            rawValue: UserDefaults.standard.string(forKey: "usageGranularity") ?? ""
        ) ?? .day
        usageSeriesGrouping = UsageSeriesGrouping(
            rawValue: UserDefaults.standard.string(forKey: "usageSeriesGrouping") ?? ""
        ) ?? .total
        usageFullRefreshInterval = UsageFullRefreshInterval(
            rawValue: UserDefaults.standard.integer(forKey: "usageFullRefreshInterval")
        ) ?? .twentyFourHours
        let raw = UserDefaults.standard.string(forKey: "iconStyle") ?? ""
        iconStyle = IconStyle(rawValue: raw) ?? .ring
        let themeRaw = UserDefaults.standard.string(forKey: "colorTheme") ?? ""

        colorTheme = ColorTheme(rawValue: themeRaw) ?? .default
        let channelRaw = UserDefaults.standard.string(forKey: "updateChannel")
        if let channelRaw {
            updateChannel = UpdateChannel(rawValue: channelRaw) ?? .stable
        } else {
            // Auto-detect: if running a beta version, default to beta channel
            let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
            updateChannel = appVersion.contains("beta") || appVersion.contains("alpha") || appVersion.contains("rc") ? .beta : .stable
        }


        let defaultColors = ColorTheme.default.colors
        customRunningColor = Self.loadColor(
            forKey: "customRunningHex",
            fallback: defaultColors.runningDark
        )
        customAwaitingColor = Self.loadColor(
            forKey: "customAwaitingHex",
            fallback: defaultColors.awaitingDark
        )
        customIdleColor = Self.loadColor(
            forKey: "customIdleHex",
            fallback: defaultColors.idleDark
        )

        // Load notification config with migration
        (notificationConfig, notifyAwaitingInput) = Self.loadNotificationConfigWithMigration()
    }

    private static func loadNotificationConfigWithMigration() -> (NotificationConfig, Bool) {
        // Check if new config exists
        if let data = UserDefaults.standard.data(forKey: "notificationConfig"),
           let config = try? JSONDecoder().decode(NotificationConfig.self, from: data) {
            return (config, config.isEnabled)
        }

        // Migrate from old setting
        let oldValue = UserDefaults.standard.bool(forKey: "notifyAwaitingInput")
        var config = NotificationConfig.default
        config.isEnabled = oldValue
        if oldValue {
            config.enabledTransitions = [.runningToAwaiting]
        } else {
            config.enabledTransitions = []
        }
        // Clean up old key
        UserDefaults.standard.removeObject(forKey: "notifyAwaitingInput")
        // Save new config
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: "notificationConfig")
        }
        return (config, oldValue)
    }

    private static func loadSessionGroupingModeWithMigration() -> SessionGroupingMode {
        if let rawValue = UserDefaults.standard.string(forKey: "sessionGroupingMode"),
           let mode = SessionGroupingMode(rawValue: rawValue) {
            return mode
        }

        let legacyValue = UserDefaults.standard.bool(forKey: "groupSessionsByTool")
        let mode: SessionGroupingMode = legacyValue ? .tool : .none
        UserDefaults.standard.set(mode.rawValue, forKey: "sessionGroupingMode")
        UserDefaults.standard.removeObject(forKey: "groupSessionsByTool")
        return mode
    }

    var usageConfiguration: UsageDisplayConfiguration {
        UsageDisplayConfiguration(
            sources: usageSources,
            refreshCadence: usageRefreshCadence,
            visualizationStyle: usageVisualizationStyle,
            metric: usageMetric,
            granularity: usageGranularity,
            seriesGrouping: usageSeriesGrouping
        )
    }

    // MARK: - Unified color access

    /// NSColor for AppKit consumers (StatusItemController).
    func nsColor(for state: ToolActivityState) -> NSColor {
        if state == .unknown {
            return NSColor.secondaryLabelColor
        }
        if colorTheme == .custom {
            return NSColor(customSwiftUIColor(for: state))
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
        if colorTheme == .custom {
            return customSwiftUIColor(for: state)
        }
        let c = colorTheme.colors
        let (dark, light) = rgb(for: state, colors: c)
        let t = colorScheme == .dark ? dark : light
        return Color(red: t.r, green: t.g, blue: t.b)
    }

    private func customSwiftUIColor(for state: ToolActivityState) -> Color {
        switch state {
        case .running:       return customRunningColor
        case .awaitingInput: return customAwaitingColor
        case .idle:          return customIdleColor
        case .unknown:       return .secondary
        }
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

    // MARK: - Custom color helpers

    /// Copy a preset theme's dark-mode colors into the custom color properties.
    func applyPresetToCustomColors(_ theme: ColorTheme) {
        guard theme != .custom else { return }
        let c = theme.colors
        customRunningColor = Color(red: c.runningDark.r, green: c.runningDark.g, blue: c.runningDark.b)
        customAwaitingColor = Color(red: c.awaitingDark.r, green: c.awaitingDark.g, blue: c.awaitingDark.b)
        customIdleColor = Color(red: c.idleDark.r, green: c.idleDark.g, blue: c.idleDark.b)
    }

    private func persistCustomColor(_ color: Color, forKey key: String) {
        UserDefaults.standard.set(color.hexString, forKey: key)
    }

    private static func loadColor(
        forKey key: String,
        fallback rgb: (r: Double, g: Double, b: Double)
    ) -> Color {
        if let hex = UserDefaults.standard.string(forKey: key) {
            return Color(hex: hex) ?? Color(red: rgb.r, green: rgb.g, blue: rgb.b)
        }
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    private static func loadUsageSources() -> [UsageSource] {
        let rawValues = UserDefaults.standard.stringArray(forKey: "usageSources") ?? UsageSource.allCases.map(\.rawValue)
        let parsed = rawValues.compactMap(UsageSource.init(rawValue:))
        let resolved = parsed.isEmpty ? UsageSource.allCases : parsed
        let unique = Set(resolved)
        return UsageSource.allCases.filter { unique.contains($0) }
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

    var primaryDisplaySupportsNotch: Bool {
        guard let mainScreen = Self.primaryScreen() else {
            return false
        }
        if #available(macOS 12.0, *),
           mainScreen.auxiliaryTopLeftArea != nil,
           mainScreen.auxiliaryTopRightArea != nil {
            return true
        }
        return mainScreen.safeAreaInsets.top > 0
    }

    private static func primaryScreen() -> NSScreen? {
        let mainDisplayID = CGMainDisplayID()
        return NSScreen.screens.first { screen in
            let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            return screenNumber?.uint32Value == mainDisplayID
        }
    }
}

// MARK: - Color ↔ Hex helpers

extension Color {
    /// Returns a hex string like "#1AE84D".
    var hexString: String {
        let nsColor = NSColor(self).usingColorSpace(.sRGB)
            ?? NSColor(self).usingColorSpace(.deviceRGB)
            ?? NSColor(red: 0, green: 0, blue: 0, alpha: 1)
        let r = Int(round(nsColor.redComponent * 255))
        let g = Int(round(nsColor.greenComponent * 255))
        let b = Int(round(nsColor.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// Creates a Color from a hex string like "#1AE84D" or "1AE84D".
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexSanitized.hasPrefix("#") { hexSanitized.removeFirst() }
        guard hexSanitized.count == 6, let intVal = UInt64(hexSanitized, radix: 16) else {
            return nil
        }
        let r = Double((intVal >> 16) & 0xFF) / 255.0
        let g = Double((intVal >> 8) & 0xFF) / 255.0
        let b = Double(intVal & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
