import Foundation
import VibeBarCore

@MainActor
enum WrapperCommandUIStatus: Equatable {
    case checking
    case notInstalled
    case installedManaged(path: String)
    case installedExternal(path: String)
    case installing
    case uninstalling
    case installFailed(String)
    case uninstallFailed(String)

    var isBusy: Bool {
        switch self {
        case .installing, .uninstalling:
            return true
        default:
            return false
        }
    }
}

@MainActor
final class WrapperCommandViewModel: ObservableObject {
    static let shared = WrapperCommandViewModel()

    @Published private(set) var status: WrapperCommandUIStatus = .checking

    private let installer = WrapperCommandInstaller()
    private let checkTTL: TimeInterval = 10
    private var lastCheckAt: Date = .distantPast
    private var hasLoaded = false

    private init() {}

    func refreshIfNeeded() {
        guard !hasLoaded || Date().timeIntervalSince(lastCheckAt) > checkTTL else { return }
        refreshNow()
    }

    func refreshNow() {
        guard !status.isBusy else { return }
        status = .checking

        let installer = installer
        Task {
            let presence = await Task.detached { installer.detect() }.value
            applyPresence(presence)
            hasLoaded = true
            lastCheckAt = Date()
        }
    }

    func installCommand() {
        guard !status.isBusy else { return }
        status = .installing

        let installer = installer
        Task {
            do {
                try await Task.detached { try installer.install() }.value
            } catch {
                status = .installFailed(error.localizedDescription)
                return
            }

            let presence = await Task.detached { installer.detect() }.value
            applyPresence(presence)
            hasLoaded = true
            lastCheckAt = Date()
        }
    }

    func uninstallCommand() {
        guard !status.isBusy else { return }
        status = .uninstalling

        let installer = installer
        Task {
            do {
                try await Task.detached { try installer.uninstall() }.value
            } catch {
                status = .uninstallFailed(error.localizedDescription)
                return
            }

            let presence = await Task.detached { installer.detect() }.value
            applyPresence(presence)
            hasLoaded = true
            lastCheckAt = Date()
        }
    }

    private func applyPresence(_ presence: WrapperCommandPresence) {
        switch presence {
        case .notInstalled:
            status = .notInstalled
        case .installedManaged(let path):
            status = .installedManaged(path: path)
        case .installedExternal(let path):
            status = .installedExternal(path: path)
        }
    }
}
