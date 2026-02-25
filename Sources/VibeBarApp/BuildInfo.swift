import Foundation

enum BuildInfo {
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    static var buildTime: String {
        guard let url = Bundle.main.url(forResource: "build-timestamp", withExtension: "txt"),
              let content = try? String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty
        else {
            return "source build"
        }
        return content
    }
}
