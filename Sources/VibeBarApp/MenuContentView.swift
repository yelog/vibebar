import SwiftUI
import VibeBarCore

struct MenuContentView: View {
    @ObservedObject var model: MonitorViewModel
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.colorScheme) private var colorScheme

    @State private var collapsedGroupIDs: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            Divider()

            sessionsSection

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
        ToolIconLoader.icon(for: tool)
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Sessions Section

    @ViewBuilder
    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(l10n.string(.sessionTitle))
                .font(.subheadline.weight(.semibold))

            if model.sessions.isEmpty {
                Text(l10n.string(.noSessions))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if settings.sessionGroupingMode != .none {
                groupedSessionsView
            } else {
                flatSessionsView
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Flat Sessions View (Original)

    private var flatSessionsView: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(displaySessions) { session in
                sessionRow(session)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Grouped Sessions View

    private var groupedSessionsView: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(groupedSessions) { group in
                groupSection(group)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var displaySessions: [SessionSnapshot] {
        SessionListPresentation.sortedSessions(model.sessions)
    }

    private var groupedSessions: [SessionListPresentation.Group] {
        SessionListPresentation.groupedSessions(model.sessions, mode: settings.sessionGroupingMode)
    }

    @ViewBuilder
    private func groupSection(_ group: SessionListPresentation.Group) -> some View {
        let isExpanded = !collapsedGroupIDs.contains(group.id)
        let title = SessionListPresentation.title(for: group)
        let detail = SessionListPresentation.detail(for: group)

        VStack(alignment: .leading, spacing: 4) {
            // Group header button
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isExpanded {
                        collapsedGroupIDs.insert(group.id)
                    } else {
                        collapsedGroupIDs.remove(group.id)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    // Expand/collapse indicator
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)

                    switch group.kind {
                    case .tool(let tool):
                        if let icon = toolIcon(for: tool) {
                            Image(nsImage: icon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: tool.iconName)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 14, height: 14)
                        }
                    case .project:
                        Image(systemName: "folder.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 14, height: 14)
                    }

                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)

                    if let detail {
                        Text("· \(detail)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Text("(\(group.sessions.count))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)

                    // Status indicators (compact)
                    HStack(spacing: 4) {
                        ForEach(ToolActivityState.allCases.filter { state in
                            group.sessions.contains { $0.status == state }
                        }, id: \.self) { state in
                            Circle()
                                .fill(color(for: state))
                                .frame(width: 5, height: 5)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(group.sessions) { session in
                        sessionRow(session, context: group.kind.rowContext)
                    }
                }
                .padding(.leading, 24)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Session Row

    @ViewBuilder
    private func sessionRow(
        _ session: SessionSnapshot,
        context: SessionRowPresentationContext = .flat
    ) -> some View {
        let primaryText = SessionDisplayFormatter.primaryText(for: session, context: context)
        let secondaryText = SessionDisplayFormatter.secondaryText(for: session, context: context)
        let directoryText = SessionDisplayFormatter.directoryText(for: session, context: context, maxLength: 70)
        let badges = SessionDisplayFormatter.badges(for: session, now: model.summary.updatedAt)
        let isCondensed = SessionListPresentation.isCondensed(session, now: model.summary.updatedAt)

        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                if context.showsToolIcon {
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
                }

                Text(primaryText)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)

                if !badges.isEmpty {
                    SessionBadgeStrip(badges: badges, compact: true)
                        .layoutPriority(1)
                }
            }

            if !isCondensed {
                if let secondaryText {
                    HStack(spacing: 6) {
                        Text(secondaryText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer(minLength: 0)
                    }
                    .padding(.leading, context.contentIndent)
                }

                if let directoryText {
                    Text(directoryText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.leading, context.contentIndent)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private func sessionDuration(for session: SessionSnapshot) -> String {
        SessionDurationFormatter.string(for: session, now: model.summary.updatedAt)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
