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
                Button(l10n.string(.openSessionsDir)) {
                    model.openSessionsFolder()
                }

                Button(l10n.string(.purgeStale)) {
                    model.purgeStaleNow()
                }

                Spacer(minLength: 0)

                Button(l10n.string(.quit)) {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(12)
        .frame(width: 420)
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
