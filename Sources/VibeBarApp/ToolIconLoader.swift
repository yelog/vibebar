import AppKit
import VibeBarCore

/// Shared utility for loading tool icons with caching
@MainActor
enum ToolIconLoader {
    /// Cached resource bundle (lazy loaded once)
    private static let cachedBundle: Bundle? = {
        // Strategy 1: Bundle.module (SPM development)
        if let path = Bundle.module.path(forResource: "claudeCode", ofType: "png"),
           FileManager.default.fileExists(atPath: path) {
            return Bundle.module
        }

        // Strategy 2: Bundle.main (development builds)
        if let path = Bundle.main.path(forResource: "claudeCode", ofType: "png"),
           FileManager.default.fileExists(atPath: path) {
            return Bundle.main
        }

        // Strategy 3: Release bundle location
        // In released app: VibeBar.app/Contents/Resources/VibeBar_VibeBarApp.bundle
        let releaseBundleURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Resources")
            .appendingPathComponent("VibeBar_VibeBarApp.bundle")

        if FileManager.default.fileExists(atPath: releaseBundleURL.path),
           let bundle = Bundle(url: releaseBundleURL),
           let path = bundle.path(forResource: "claudeCode", ofType: "png"),
           FileManager.default.fileExists(atPath: path) {
            return bundle
        }

        // Strategy 4: Bundle next to executable
        let executableBundleURL = Bundle.main.bundleURL
            .appendingPathComponent("VibeBar_VibeBarApp.bundle")

        if FileManager.default.fileExists(atPath: executableBundleURL.path),
           let bundle = Bundle(url: executableBundleURL),
           let path = bundle.path(forResource: "claudeCode", ofType: "png"),
           FileManager.default.fileExists(atPath: path) {
            return bundle
        }

        #if DEBUG
        // Strategy 5: Development paths
        let devPaths = [
            URL(fileURLWithPath: "/Users/yelog/workspace/swift/VibeBar/.build/debug/VibeBar_VibeBarApp.bundle"),
            URL(fileURLWithPath: "/Users/yelog/workspace/swift/VibeBar/.build/arm64-apple-macosx/debug/VibeBar_VibeBarApp.bundle"),
        ]

        for url in devPaths {
            if FileManager.default.fileExists(atPath: url.path),
               let bundle = Bundle(url: url),
               let path = bundle.path(forResource: "claudeCode", ofType: "png"),
               FileManager.default.fileExists(atPath: path) {
                return bundle
            }
        }
        #endif

        return nil
    }()

    /// Cached tool icons
    private static var iconCache: [ToolKind: NSImage] = [:]

    /// Load tool icon with caching
    static func icon(for tool: ToolKind) -> NSImage? {
        if let cached = iconCache[tool] {
            return cached
        }

        guard let bundle = cachedBundle,
              let path = bundle.path(forResource: tool.iconResourceName, ofType: "png"),
              let image = NSImage(contentsOfFile: path) else {
            return nil
        }

        iconCache[tool] = image
        return image
    }

    /// Get the resource bundle (for external access if needed)
    static var bundle: Bundle? { cachedBundle }
}