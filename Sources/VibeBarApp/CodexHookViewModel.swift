import Foundation
import VibeBarCore

@MainActor
enum CodexHookUIStatus: Equatable {
    case checking
    case cliNotFound
    case notInstalled
    case installed
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
final class CodexHookViewModel: ObservableObject {
    static let shared = CodexHookViewModel()

    @Published private(set) var status: CodexHookUIStatus = .checking

    private let installer = CodexHookInstaller()
    private let checkTTL: TimeInterval = 300
    private var lastCheckAt: Date = .distantPast
    private var hasLoaded = false
    private var isChecking = false

    private init() {}

    func refreshIfNeeded() {
        refreshNow(force: false)
    }

    func refreshNow(force: Bool = true) {
        guard !status.isBusy else { return }
        guard !isChecking else { return }
        if !force {
            guard !hasLoaded || Date().timeIntervalSince(lastCheckAt) > checkTTL else { return }
        }
        if !hasLoaded {
            status = .checking
        }

        let installer = installer
        isChecking = true
        Task {
            defer { isChecking = false }
            let detection = await Task.detached { installer.detect() }.value
            guard !status.isBusy else { return }
            applyDetection(detection)
            hasLoaded = true
            lastCheckAt = Date()
        }
    }

    func installHook() {
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

            let detection = await Task.detached { installer.detect() }.value
            applyDetection(detection)
            hasLoaded = true
            lastCheckAt = Date()
            MonitorViewModel.shared.refreshNow()
        }
    }

    func uninstallHook() {
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

            let detection = await Task.detached { installer.detect() }.value
            applyDetection(detection)
            hasLoaded = true
            lastCheckAt = Date()
            MonitorViewModel.shared.refreshNow()
        }
    }

    private func applyDetection(_ detection: CodexHookInstallStatus) {
        switch detection {
        case .cliNotFound:
            status = .cliNotFound
        case .installed:
            status = .installed
        case .notInstalled:
            status = .notInstalled
        }
    }
}
