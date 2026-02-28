import AppKit
import Foundation
import Sparkle
import VibeBarCore

/// Sparkle-based auto updater for VibeBar
@MainActor
final class UpdateChecker: NSObject, SPUUpdaterDelegate {
    static let shared = UpdateChecker()

    private var updaterController: SPUStandardUpdaterController?
    private let checkInterval: TimeInterval = 24 * 60 * 60
    private var autoCheckTimer: Timer?

    private override init() {
        super.init()
    }

    /// Initialize Sparkle updater
    func initialize() {
        guard updaterController == nil else { return }

        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )

        // Configure updater settings
        if let updater = updaterController?.updater {
            updater.automaticallyChecksForUpdates = AppSettings.shared.autoCheckUpdates
            updater.updateCheckInterval = checkInterval
        }
    }

    /// Update feed URL based on current update channel
    /// Note: The feed URL is determined dynamically by the delegate method feedURLStringForUpdater
    func updateFeedURL() {
        // The feed URL is determined dynamically by the delegate method
        // Changing channels will take effect on the next update check
    }

    /// Start automatic update checking
    func startAutoCheckIfNeeded() {
        guard AppSettings.shared.autoCheckUpdates else { return }

        // Delay initial check to avoid blocking launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.checkForUpdates(silent: true)
        }

        // Schedule periodic checks
        autoCheckTimer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard AppSettings.shared.autoCheckUpdates else { return }
                self?.checkForUpdates(silent: true)
            }
        }
    }

    /// Check for updates
    func checkForUpdates(silent: Bool = false) {
        guard let controller = updaterController else {
            // Fallback to manual check if Sparkle not initialized
            if !silent {
                showManualUpdateAlert()
            }
            return
        }

        if silent {
            // Background check - Sparkle handles this automatically
            controller.updater.checkForUpdatesInBackground()
        } else {
            // Show update UI
            controller.checkForUpdates(nil)
        }
    }

    /// Check for updates with UI (for menu action)
    func checkForUpdatesWithUI() {
        updaterController?.checkForUpdates(nil)
    }

    // MARK: - SPUUpdaterDelegate

    /// Returns the feed URL string based on the current update channel
    func feedURLString(for updater: SPUUpdater) -> String? {
        let channel = AppSettings.shared.updateChannel
        switch channel {
        case .stable:
            return "https://vibebar.yelog.org/appcast.xml"
        case .beta:
            return "https://vibebar.yelog.org/appcast-beta.xml"
        }
    }

    func updater(
        _ updater: SPUUpdater,
        didFindValidUpdate item: SUAppcastItem
    ) {
        // Update found - Sparkle will show UI automatically
        // We can log this or perform additional actions
    }

    func updater(
        _ updater: SPUUpdater,
        didNotFindUpdate error: Error
    ) {
        // No update found or error
        // Sparkle handles error UI, but we can log if needed
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        // App will restart - save any necessary state
    }

    // MARK: - Manual Fallback

    private func showManualUpdateAlert() {
        let alert = NSAlert()
        alert.messageText = L10n.shared.string(.updateCheckFailed)
        alert.informativeText = "Auto-updater is not available. Please visit GitHub to download the latest version."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Go to GitHub")
        alert.addButton(withTitle: L10n.shared.string(.ok))

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "https://github.com/yelog/VibeBar/releases/latest") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

// MARK: - Legacy Update Check (for compatibility)

extension UpdateChecker {
    /// Legacy check for users who haven't updated to Sparkle-enabled version yet
    func legacyCheckForUpdates(silent: Bool = false) {
        Task {
            await performLegacyCheck(silent: silent)
        }
    }

    private func performLegacyCheck(silent: Bool) async {
        // This can be removed once all users are on Sparkle-enabled versions
        // For now, just open GitHub if Sparkle isn't available
        if !silent {
            await MainActor.run {
                showManualUpdateAlert()
            }
        }
    }
}
