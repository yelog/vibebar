import SwiftUI
import VibeBarCore

struct NotchContentView: View {
    private static let visibleSessionLimit = 8

    @ObservedObject var model: MonitorViewModel
    let usageSnapshot: UsageSnapshot?
    let usageEnabled: Bool
    let isUsageRefreshing: Bool
    let contentTopInset: CGFloat
    let onRefresh: () -> Void
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var settings = AppSettings.shared
    @State private var expandedTools: Set<String> = Set(ToolKind.allCases.map { $0.rawValue })

    private struct ToolSessionGroup: Identifiable {
        let tool: ToolKind
        let sessions: [SessionSnapshot]
        var id: String { tool.rawValue }
    }

    private var groupedSessions: [ToolSessionGroup] {
        let visibleSessions = Array(model.sessions.prefix(Self.visibleSessionLimit))

        var groups: [ToolKind: [SessionSnapshot]] = [:]
        for session in visibleSessions {
            groups[session.tool, default: []].append(session)
        }

        return ToolKind.allCases.compactMap { tool in
            guard let sessions = groups[tool], !sessions.isEmpty else { return nil }
            return ToolSessionGroup(tool: tool, sessions: sessions)
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            panelBackground

            VStack(alignment: .leading, spacing: 0) {
                Color.clear
                    .frame(height: max(contentTopInset, 0))

                contentLayer
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
                    .padding(.bottom, 14)
            }
        }
        .frame(width: 440, alignment: .leading)
        .overlay(
            NotchExpandedPanelShape(cornerRadius: NotchPanelStyle.cornerRadius)
                .stroke(NotchPanelStyle.strokeColor, lineWidth: 1)
        )
        .shadow(color: NotchPanelStyle.shadowColor, radius: 20, x: 0, y: 12)
    }

    private var contentLayer: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Divider()
                .opacity(0.25)

            sessionsSection

            if usageEnabled, let usageSnapshot {
                Divider()
                    .opacity(0.25)

                UsageMenuSectionView(
                    snapshot: usageSnapshot,
                    isRefreshing: isUsageRefreshing,
                    action: openUsageSettings,
                    enableFooterTooltip: false
                )
            }

            Divider()
                .opacity(0.25)

            footer
        }
    }

    private var panelBackground: some View {
        NotchExpandedPanelShape(cornerRadius: NotchPanelStyle.cornerRadius)
            .fill(NotchPanelStyle.fillColor)
            .overlay(alignment: .top) {
                NotchExpandedPanelShape(cornerRadius: NotchPanelStyle.cornerRadius)
                    .fill(NotchPanelStyle.topHighlight)
                    .frame(height: NotchPanelStyle.topHighlightHeight)
                    .clipped()
            }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text("VibeBar")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                Text(l10n.string(.totalSessionsFmt, model.summary.total))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Text(l10n.string(.updatedFmt, Self.timeFormatter.string(from: model.summary.updatedAt)))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Text(l10n.string(.legendText))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(l10n.string(.sessionTitle))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                if settings.groupSessionsByTool {
                    Text(l10n.string(.groupSessionsByTool))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            if model.sessions.isEmpty {
                Text(l10n.string(.noSessions))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else if settings.groupSessionsByTool {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(groupedSessions, id: \.tool) { group in
                        toolGroupSection(group)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.sessions.prefix(Self.visibleSessionLimit)) { session in
                        sessionRow(session)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func toolGroupSection(_ group: ToolSessionGroup) -> some View {
        let isExpanded = expandedTools.contains(group.tool.rawValue)

        VStack(alignment: .leading, spacing: 5) {
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
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)

                    if let icon = ToolIconLoader.icon(for: group.tool) {
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
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text("(\(group.sessions.count))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)

                    HStack(spacing: 4) {
                        ForEach(orderedStates(for: group.sessions), id: \.self) { state in
                            Circle()
                                .fill(color(for: state))
                                .frame(width: 5, height: 5)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)

            if isExpanded {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(group.sessions) { session in
                        sessionRow(session, isGrouped: true)
                    }
                }
                .padding(.leading, 20)
            }
        }
    }

    @ViewBuilder
    private func sessionRow(_ session: SessionSnapshot, isGrouped: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                if !isGrouped {
                    if let icon = ToolIconLoader.icon(for: session.tool) {
                        Image(nsImage: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 15, height: 15)
                    } else {
                        Image(systemName: session.tool.iconName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 15, height: 15)
                    }
                }

                Circle()
                    .fill(color(for: session.status))
                    .frame(width: 6, height: 6)

                if !isGrouped {
                    Text("\(session.tool.displayName) • pid \(session.pid)")
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                } else {
                    Text("pid \(session.pid)")
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                HStack(spacing: 4) {
                    Text(session.status.displayName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(color(for: session.status))

                    Text(sessionDuration(for: session))
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            Text(displayDirectory(for: session))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.leading, isGrouped ? 13 : 29)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                onRefresh()
            } label: {
                Label(l10n.string(.refresh), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                onOpenSettings()
            } label: {
                Label(l10n.string(.settings), systemImage: "gearshape")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer(minLength: 0)

            Button(role: .destructive) {
                onQuit()
            } label: {
                Label(l10n.string(.quit), systemImage: "power")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func color(for state: ToolActivityState) -> Color {
        AppSettings.shared.swiftUIColor(for: state, colorScheme: colorScheme)
    }

    private func orderedStates(for sessions: [SessionSnapshot]) -> [ToolActivityState] {
        let priority: [ToolActivityState] = [.running, .awaitingInput, .idle, .unknown]
        return priority.filter { state in
            sessions.contains { $0.status == state }
        }.prefix(3).map { $0 }
    }

    private func displayDirectory(for session: SessionSnapshot) -> String {
        guard let cwd = session.cwd, !cwd.isEmpty else {
            return l10n.string(.dirUnknown)
        }
        let abbreviated = (cwd as NSString).abbreviatingWithTildeInPath
        if abbreviated.count <= 62 {
            return abbreviated
        }
        return "…" + abbreviated.suffix(61)
    }

    private func sessionDuration(for session: SessionSnapshot) -> String {
        SessionDurationFormatter.string(startedAt: session.startedAt, now: model.summary.updatedAt)
    }

    private func openUsageSettings() {
        SettingsWindowController.shared.showSettings(tab: .usage)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

private struct NotchExpandedPanelShape: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(cornerRadius, rect.width / 2, rect.height / 2)

        path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + radius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + radius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.closeSubpath()

        return path
    }
}
