import Foundation
import ServiceManagement

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

    private init() {
        launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
        autoCheckUpdates = UserDefaults.standard.bool(forKey: "autoCheckUpdates")
        let raw = UserDefaults.standard.string(forKey: "iconStyle") ?? ""
        iconStyle = IconStyle(rawValue: raw) ?? .ring
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
