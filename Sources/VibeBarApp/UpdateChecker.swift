import AppKit
import Foundation
import VibeBarCore

@MainActor
final class UpdateChecker {
    static let shared = UpdateChecker()

    private let repoOwner = "yelog"
    private let repoName = "VibeBar"
    private let checkInterval: TimeInterval = 24 * 60 * 60
    private let requestTimeout: TimeInterval = 15
    private var autoCheckTimer: Timer?
    private var isChecking = false
    private var apiRateLimitResetAt: Date?

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
        guard !isChecking else { return }
        isChecking = true
        Task { [weak self] in
            await self?.performCheck(silent: silent)
        }
    }

    private func performCheck(silent: Bool) async {
        defer { isChecking = false }

        if let resetAt = apiRateLimitResetAt, resetAt > Date() {
            let fallbackResult = await fetchLatestReleaseViaRedirect()
            switch fallbackResult {
            case .success(let release):
                handleRelease(release, silent: silent)
            case .failure:
                if !silent {
                    showAlert(
                        title: L10n.shared.string(.updateCheckFailed),
                        message: composeRateLimitedMessage(resetAt: resetAt, detail: nil)
                    )
                }
            }
            return
        }

        let apiResult = await fetchLatestReleaseFromAPI()
        switch apiResult {
        case .success(let release):
            apiRateLimitResetAt = nil
            handleRelease(release, silent: silent)
        case .failure(let failure):
            if case .rateLimited(let resetAt, _) = failure {
                apiRateLimitResetAt = resetAt
            } else {
                apiRateLimitResetAt = nil
            }

            let fallbackResult = await fetchLatestReleaseViaRedirect()
            if case .success(let release) = fallbackResult {
                handleRelease(release, silent: silent)
                return
            }

            if !silent {
                showFailureAlert(for: failure)
            }
        }
    }

    private func handleRelease(_ release: ReleaseInfo, silent: Bool) {
        let currentVersion = BuildInfo.version

        if isNewer(remote: release.version, current: currentVersion) {
            showUpdateAvailable(version: release.version, notes: release.notes, releaseURL: release.releaseURL)
        } else if !silent {
            showAlert(
                title: L10n.shared.string(.updateAlreadyLatest),
                message: L10n.shared.string(.updateAlreadyLatestFmt, currentVersion)
            )
        }
    }

    private func fetchLatestReleaseFromAPI() async -> FetchResult {
        guard let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest") else {
            return .failure(.parse)
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("VibeBar/\(BuildInfo.version)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = requestTimeout

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.parse)
            }

            let serviceMessage = extractServiceMessage(from: data)
            if isRateLimited(statusCode: http.statusCode, response: http, serviceMessage: serviceMessage) {
                let resetAt = parseRateLimitReset(from: http)
                return .failure(.rateLimited(resetAt: resetAt, detail: serviceMessage))
            }

            guard (200..<300).contains(http.statusCode) else {
                return .failure(.http(statusCode: http.statusCode, detail: serviceMessage))
            }

            guard let payload = try? JSONDecoder().decode(GitHubLatestRelease.self, from: data) else {
                return .failure(.parse)
            }

            let release = ReleaseInfo(
                version: normalizeVersion(payload.tagName),
                notes: payload.body ?? "",
                releaseURL: payload.htmlURL ?? "https://github.com/\(repoOwner)/\(repoName)/releases/latest"
            )
            return .success(release)
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    private func fetchLatestReleaseViaRedirect() async -> FetchResult {
        guard let latestURL = URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases/latest") else {
            return .failure(.parse)
        }

        var headRequest = URLRequest(url: latestURL)
        headRequest.httpMethod = "HEAD"
        headRequest.setValue("VibeBar/\(BuildInfo.version)", forHTTPHeaderField: "User-Agent")
        headRequest.timeoutInterval = requestTimeout

        if let release = await fetchReleaseViaRedirect(request: headRequest, latestURL: latestURL) {
            return .success(release)
        }

        var getRequest = URLRequest(url: latestURL)
        getRequest.httpMethod = "GET"
        getRequest.setValue("text/html", forHTTPHeaderField: "Accept")
        getRequest.setValue("VibeBar/\(BuildInfo.version)", forHTTPHeaderField: "User-Agent")
        getRequest.timeoutInterval = requestTimeout

        if let release = await fetchReleaseViaRedirect(request: getRequest, latestURL: latestURL) {
            return .success(release)
        }

        return .failure(.parse)
    }

    private func fetchReleaseViaRedirect(request: URLRequest, latestURL: URL) async -> ReleaseInfo? {
        do {
            let (_, response) = try await URLSession.shared.data(for: request)

            if let release = releaseInfo(from: response.url) {
                return release
            }

            guard let http = response as? HTTPURLResponse,
                  let locationValue = http.value(forHTTPHeaderField: "Location"),
                  let locationURL = URL(string: locationValue, relativeTo: latestURL)
            else {
                return nil
            }
            return releaseInfo(from: locationURL.absoluteURL)
        } catch {
            return nil
        }
    }

    private func showFailureAlert(for failure: FetchFailure) {
        let l10n = L10n.shared
        let message: String
        switch failure {
        case .network(let detail):
            message = l10n.string(.updateConnectErrorFmt, detail)
        case .parse:
            message = l10n.string(.updateParseError)
        case .http(let statusCode, let detail):
            var text = l10n.string(.updateHTTPStatusFmt, statusCode)
            if let detail, !detail.isEmpty {
                text += "\n\(detail)"
            }
            message = text
        case .rateLimited(let resetAt, let detail):
            message = composeRateLimitedMessage(resetAt: resetAt, detail: detail)
        }
        showAlert(title: l10n.string(.updateCheckFailed), message: message)
    }

    private func composeRateLimitedMessage(resetAt: Date?, detail: String?) -> String {
        let l10n = L10n.shared
        var text: String
        if let resetAt {
            text = l10n.string(.updateRateLimitedWithResetFmt, Self.rateLimitTimeFormatter.string(from: resetAt))
        } else {
            text = l10n.string(.updateRateLimited)
        }
        if let detail, !detail.isEmpty {
            text += "\n\(detail)"
        }
        return text
    }

    private func releaseInfo(from url: URL?) -> ReleaseInfo? {
        guard let url, let tag = extractTag(from: url) else { return nil }
        let releaseURL = "https://github.com/\(repoOwner)/\(repoName)/releases/tag/\(tag)"
        return ReleaseInfo(version: normalizeVersion(tag), notes: "", releaseURL: releaseURL)
    }

    private func extractTag(from url: URL) -> String? {
        let components = url.pathComponents
        guard let index = components.firstIndex(of: "tag"), components.indices.contains(index + 1) else {
            return nil
        }
        let rawTag = components[index + 1]
        guard !rawTag.isEmpty else { return nil }
        let decodedTag = rawTag.removingPercentEncoding ?? rawTag
        return decodedTag.lowercased() == "latest" ? nil : decodedTag
    }

    private func normalizeVersion(_ tag: String) -> String {
        tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }

    private func isRateLimited(statusCode: Int, response: HTTPURLResponse, serviceMessage: String?) -> Bool {
        if statusCode == 429 { return true }
        guard statusCode == 403 else { return false }

        if response.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0" {
            return true
        }
        guard let message = serviceMessage?.lowercased() else { return false }
        return message.contains("rate limit")
    }

    private func parseRateLimitReset(from response: HTTPURLResponse) -> Date? {
        guard let raw = response.value(forHTTPHeaderField: "x-ratelimit-reset"),
              let timestamp = TimeInterval(raw),
              timestamp > 0
        else {
            return nil
        }
        return Date(timeIntervalSince1970: timestamp)
    }

    private func extractServiceMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json["message"] as? String
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

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.shared.string(.ok))

        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private static let rateLimitTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()
}

private struct GitHubLatestRelease: Decodable {
    let tagName: String
    let body: String?
    let htmlURL: String?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case body
        case htmlURL = "html_url"
    }
}

private struct ReleaseInfo {
    let version: String
    let notes: String
    let releaseURL: String
}

private enum FetchResult {
    case success(ReleaseInfo)
    case failure(FetchFailure)
}

private enum FetchFailure {
    case network(String)
    case parse
    case http(statusCode: Int, detail: String?)
    case rateLimited(resetAt: Date?, detail: String?)
}
