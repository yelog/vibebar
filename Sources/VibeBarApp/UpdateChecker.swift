import AppKit
import Foundation
import Sparkle
import VibeBarCore

/// Sparkle-based auto updater for VibeBar
@MainActor
final class UpdateChecker: NSObject, SPUUpdaterDelegate {
    static let shared = UpdateChecker()
    
    /// Flag to prevent agent restart during update process
    static var isUpdating: Bool = false

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
    func updateFeedURL() {
        // Force Sparkle to clear any cached feed URL and use the delegate method
        updaterController?.updater.clearFeedURLFromUserDefaults()
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
        let url: String
        switch channel {
        case .stable:
            url = "https://vibebar.yelog.org/appcast.xml"
        case .beta:
            url = "https://vibebar.yelog.org/appcast-beta.xml"
        }
        print("[UpdateChecker] Using feed URL for channel '\(channel)': \(url)")
        return url
    }

    func updater(
        _ updater: SPUUpdater,
        didFindValidUpdate item: SUAppcastItem
    ) {
        // Update found - set flag to prevent agent restart during update
        Self.isUpdating = true
        print("[UpdateChecker] Update found, setting isUpdating flag to prevent agent restart")
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        // No update found - reset flag
        Self.isUpdating = false
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        // App will restart - terminate agent process to avoid file lock during update
        print("[UpdateChecker] Preparing for app relaunch - terminating vibebar-agent")
        terminateAgentProcess()
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        // Update failed - reset flag and show manual download option
        Self.isUpdating = false
        print("[UpdateChecker] Update aborted with error: \(error.localizedDescription)")

        // Don't show alert for specific non-failure errors
        let nsError = error as NSError
        if nsError.domain == SUSparkleErrorDomain {
            switch nsError.code {
            case 1001: // SUNoUpdateError: Already up to date
                print("[UpdateChecker] Already up to date")
                return
            case 4007: // SUInstallationCanceledError: User canceled
                print("[UpdateChecker] Update was canceled by user")
                return
            default:
                break
            }
        }
        
        // Show alert with option to download manually from GitHub
        DispatchQueue.main.async {
            self.showUpdateFailedAlert(error: error)
        }
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        // Reset update flag when update cycle finishes
        if error != nil {
            Self.isUpdating = false
        }
    }

    // MARK: - Agent Process Management

    private func terminateAgentProcess() {
        let maxRetries = 3
        var attempt = 0

        while attempt < maxRetries {
            attempt += 1
            print("[UpdateChecker] Attempt \(attempt)/\(maxRetries) to terminate vibebar-agent")

            if !isAgentRunning() {
                print("[UpdateChecker] vibebar-agent is not running, skip termination")
                return
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")

            // Use -9 (SIGKILL) for forceful termination on final attempt
            let signalFlag = attempt == maxRetries ? "-9" : "-TERM"
            process.arguments = [signalFlag, "-f", "vibebar-agent"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice

            do {
                try process.run()
                process.waitUntilExit()

                let exitCode = process.terminationStatus
                if exitCode == 0 {
                    print("[UpdateChecker] Successfully terminated vibebar-agent with \(signalFlag)")
                    // Brief pause to ensure process cleanup
                    Thread.sleep(forTimeInterval: 0.5)

                    if !isAgentRunning() {
                        print("[UpdateChecker] Confirmed vibebar-agent is terminated")
                        return
                    } else {
                        print("[UpdateChecker] vibebar-agent still running after termination")
                    }
                } else {
                    print("[UpdateChecker] pkill exited with code \(exitCode)")
                }
            } catch {
                print("[UpdateChecker] Failed to run pkill: \(error)")
            }

            // Wait before retry (except on final attempt)
            if attempt < maxRetries {
                print("[UpdateChecker] Waiting before retry...")
                Thread.sleep(forTimeInterval: 0.3)
            }
        }

        print("[UpdateChecker] Warning: Could not terminate vibebar-agent after \(maxRetries) attempts")
    }

    private func isAgentRunning() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-f", "vibebar-agent"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    // MARK: - Manual Fallback

    private func showUpdateFailedAlert(error: Error) {
        let alert = NSAlert()
        alert.messageText = L10n.shared.string(.updateCheckFailed)
        alert.informativeText = "自动更新失败，您可以从 GitHub 手动下载最新版本。\n\n错误: \(error.localizedDescription)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "前往 GitHub 下载")
        alert.addButton(withTitle: L10n.shared.string(.ok))

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "https://github.com/yelog/VibeBar/releases/latest") {
                NSWorkspace.shared.open(url)
            }
        }
    }

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
