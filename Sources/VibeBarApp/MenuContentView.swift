import SwiftUI
import VibeBarCore

struct MenuContentView: View {
    @ObservedObject var model: MonitorViewModel
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.colorScheme) private var colorScheme

    // Track expanded state for each tool group
    @State private var expandedTools: Set<String> = Set(ToolKind.allCases.map { $0.rawValue })

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
            } else if settings.groupSessionsByTool {
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
            ForEach(model.sessions.prefix(8)) { session in
                sessionRow(session)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Grouped Sessions View

    private var groupedSessionsView: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(groupedSessions, id: \.tool) { group in
                toolGroupSection(group)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private struct ToolSessionGroup: Identifiable {
        let tool: ToolKind
        let sessions: [SessionSnapshot]
        var id: String { tool.rawValue }
    }

    private var groupedSessions: [ToolSessionGroup] {
        // Group sessions by tool
        var groups: [ToolKind: [SessionSnapshot]] = [:]
        for session in model.sessions {
            groups[session.tool, default: []].append(session)
        }

        // Sort by tool display order (matching ToolKind.allCases)
        return ToolKind.allCases.compactMap { tool in
            guard let sessions = groups[tool], !sessions.isEmpty else { return nil }
            return ToolSessionGroup(tool: tool, sessions: sessions)
        }
    }

    @ViewBuilder
    private func toolGroupSection(_ group: ToolSessionGroup) -> some View {
        let isExpanded = expandedTools.contains(group.tool.rawValue)

        VStack(alignment: .leading, spacing: 4) {
            // Group header button
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isExpanded {
                        expandedTools.remove(group.tool.rawValue)
                    } else {
                        expandedTools.insert(group.tool.rawValue)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    // Expand/collapse indicator
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)

                    // Tool icon
                    if let icon = toolIcon(for: group.tool) {
                        Image(nsImage: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: group.tool.iconName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 14, height: 14)
                    }

                    Text(group.tool.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)

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
                    ForEach(group.sessions.prefix(5)) { session in
                        sessionRow(session, isGrouped: true)
                    }
                }
                .padding(.leading, 24)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Session Row

    @ViewBuilder
    private func sessionRow(_ session: SessionSnapshot, isGrouped: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                // Tool icon (only show in flat mode)
                if !isGrouped {
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

                // Status indicator
                Circle()
                    .fill(color(for: session.status))
                    .frame(width: 6, height: 6)

                // Tool name and PID (only in flat mode)
                if !isGrouped {
                    Text("\(session.tool.displayName) • pid \(session.pid)")
                        .font(.caption)
                        .lineLimit(1)
                } else {
                    // In grouped mode, just show PID
                    Text("pid \(session.pid)")
                        .font(.caption)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                HStack(spacing: 4) {
                    Text(session.status.displayName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(color(for: session.status))

                    Text(sessionDuration(for: session))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Text(displayDirectory(for: session))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.leading, isGrouped ? 14 : 30) // Align with content
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
        SessionDurationFormatter.string(startedAt: session.startedAt, now: model.summary.updatedAt)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
