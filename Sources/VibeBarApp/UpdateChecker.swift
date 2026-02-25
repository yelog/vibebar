import AppKit
import Foundation
import VibeBarCore

@MainActor
final class UpdateChecker {
    static let shared = UpdateChecker()

    private let repoOwner = "yelog"
    private let repoName = "VibeBar"
    private let checkInterval: TimeInterval = 24 * 60 * 60
    private var autoCheckTimer: Timer?

    private init() {}

    func startAutoCheckIfNeeded() {
        guard AppSettings.shared.autoCheckUpdates else { return }
        // Check after a short delay to avoid blocking launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.checkForUpdates(silent: true)
        }
        autoCheckTimer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard AppSettings.shared.autoCheckUpdates else { return }
                self?.checkForUpdates(silent: true)
            }
        }
    }

    func checkForUpdates(silent: Bool = false) {
        let urlString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.handleResponse(data: data, response: response, error: error, silent: silent)
            }
        }.resume()
    }

    private func handleResponse(data: Data?, response: URLResponse?, error: Error?, silent: Bool) {
        let l10n = L10n.shared
        if let error {
            if !silent {
                showAlert(
                    title: l10n.string(.updateCheckFailed),
                    message: l10n.string(.updateConnectErrorFmt, error.localizedDescription),
                    showDownload: false
                )
            }
            return
        }

        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tagName = json["tag_name"] as? String
        else {
            if !silent {
                showAlert(title: l10n.string(.updateCheckFailed), message: l10n.string(.updateParseError), showDownload: false)
            }
            return
        }

        let remoteVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
        let currentVersion = BuildInfo.version

        if isNewer(remote: remoteVersion, current: currentVersion) {
            let body = json["body"] as? String ?? ""
            let htmlURL = json["html_url"] as? String ?? "https://github.com/\(repoOwner)/\(repoName)/releases/latest"
            showUpdateAvailable(version: remoteVersion, notes: body, releaseURL: htmlURL)
        } else if !silent {
            showAlert(title: l10n.string(.updateAlreadyLatest), message: l10n.string(.updateAlreadyLatestFmt, currentVersion), showDownload: false)
        }
    }

    private func isNewer(remote: String, current: String) -> Bool {
        if current == "dev" { return false }
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }
        let currentParts = current.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(remoteParts.count, currentParts.count) {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let c = i < currentParts.count ? currentParts[i] : 0
            if r > c { return true }
            if r < c { return false }
        }
        return false
    }

    private func showUpdateAvailable(version: String, notes: String, releaseURL: String) {
        let l10n = L10n.shared
        let alert = NSAlert()
        alert.messageText = l10n.string(.updateNewVersionFmt, version)
        let trimmedNotes = notes.count > 500 ? String(notes.prefix(500)) + "…" : notes
        alert.informativeText = l10n.string(.updateCurrentInfoFmt, BuildInfo.version, trimmedNotes)
        alert.alertStyle = .informational
        alert.addButton(withTitle: l10n.string(.updateGoDownload))
        alert.addButton(withTitle: l10n.string(.updateRemindLater))

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn, let url = URL(string: releaseURL) {
            NSWorkspace.shared.open(url)
        }
    }

    private func showAlert(title: String, message: String, showDownload: Bool) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.shared.string(.ok))

        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
