import SwiftUI
import VibeBarCore

struct MenuContentView: View {
    @ObservedObject var model: MonitorViewModel
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text(l10n.string(.sessionTitle))
                    .font(.subheadline.weight(.semibold))

                if model.sessions.isEmpty {
                    Text(l10n.string(.noSessions))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.sessions.prefix(8)) { session in
                        sessionRow(session)
                    }
                }
            }

            Divider()

            HStack(spacing: 12) {
                Spacer(minLength: 0)

                Button(l10n.string(.quit)) {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(12)
        .frame(width: 420)
    }

    /// Load tool icon from bundle resources
    private func toolIcon(for tool: ToolKind) -> NSImage? {
        // Try multiple strategies to find the resource bundle
        let bundle = toolIconBundle()
        guard let path = bundle?.path(forResource: tool.iconResourceName, ofType: "png") else {
            return nil
        }
        return NSImage(contentsOfFile: path)
    }

    /// Find the resource bundle containing tool icons
    private func toolIconBundle() -> Bundle? {
        // Strategy 1: Try Bundle.module (SPM generated - for development)
        if let path = Bundle.module.path(forResource: "claudeCode", ofType: "png"),
           FileManager.default.fileExists(atPath: path) {
            return Bundle.module
        }

        // Strategy 2: Try main bundle resources (for development builds)
        if let path = Bundle.main.path(forResource: "claudeCode", ofType: "png"),
           FileManager.default.fileExists(atPath: path) {
            return Bundle.main
        }

        // Strategy 3: Look for VibeBar_VibeBarApp.bundle in released app
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

        // Strategy 4: Look for bundle next to executable (alternate location)
        let executableBundleURL = Bundle.main.bundleURL
            .appendingPathComponent("VibeBar_VibeBarApp.bundle")

        if FileManager.default.fileExists(atPath: executableBundleURL.path),
           let bundle = Bundle(url: executableBundleURL),
           let path = bundle.path(forResource: "claudeCode", ofType: "png"),
           FileManager.default.fileExists(atPath: path) {
            return bundle
        }

        // Strategy 5: Development paths (only for local development)
        #if DEBUG
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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("VibeBar")
                .font(.headline)

            HStack {
                Text(l10n.string(.totalSessionsFmt, model.summary.total))
                Spacer()
                Text(l10n.string(.updatedFmt, Self.timeFormatter.string(from: model.summary.updatedAt)))
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(l10n.string(.legendText))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func sessionRow(_ session: SessionSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                // Tool icon
                if let icon = toolIcon(for: session.tool) {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: session.tool.iconName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                }

                // Status indicator
                Circle()
                    .fill(color(for: session.status))
                    .frame(width: 6, height: 6)

                Text("\(session.tool.displayName) • pid \(session.pid)")
                    .font(.caption)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text(session.status.displayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(color(for: session.status))
            }

            Text(displayDirectory(for: session))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.leading, 30) // Align with tool name (16 + 8 + 6)
        }
    }

    private func color(for state: ToolActivityState) -> Color {
        AppSettings.shared.swiftUIColor(for: state, colorScheme: colorScheme)
    }

    private func displayDirectory(for session: SessionSnapshot) -> String {
        guard let cwd = session.cwd, !cwd.isEmpty else {
            return l10n.string(.dirUnknown)
        }
        let abbreviated = (cwd as NSString).abbreviatingWithTildeInPath
        if abbreviated.count <= 70 {
            return abbreviated
        }
        return "…" + abbreviated.suffix(69)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
