import SwiftUI
import VibeBarCore

struct NotchContentView: View {
    private static let usageCardWidth: CGFloat = 412

    let summary: GlobalSummary
    @ObservedObject var model: MonitorViewModel
    let usageSnapshot: UsageSnapshot?
    let usageEnabled: Bool
    let isUsageRefreshing: Bool
    let contentTopInset: CGFloat
    let topCoverPresentation: NotchCollapsedView.Presentation
    let onRefresh: () -> Void
    let onOpenSettings: () -> Void
    let onOpenSession: (SessionSnapshot) -> Void
    let onQuit: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var settings = AppSettings.shared
    @State private var expandedTools: Set<String> = Set(ToolKind.allCases.map { $0.rawValue })
    @State private var hoveredSessionID: String? = nil

    private var displaySessions: [SessionSnapshot] {
        SessionListPresentation.sortedSessions(model.sessions)
    }

    private var groupedSessions: [SessionListPresentation.Group] {
        SessionListPresentation.groupedSessions(model.sessions)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            panelBackground

            NotchCollapsedView(summary: summary, presentation: topCoverPresentation)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: topCoverHeight, alignment: .topLeading)
                .allowsHitTesting(false)

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
            NotchPanelOutlineShape(bottomCornerRadius: NotchPanelStyle.bottomCornerRadius)
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

                usageSection(snapshot: usageSnapshot)
            }

            Divider()
                .opacity(0.25)

            footer
        }
    }

    private var topCoverHeight: CGFloat {
        switch topCoverPresentation {
        case let .collapsed(_, _, notchHeight):
            return notchHeight
        case let .bridge(_, _, _, visibleHeight):
            return visibleHeight
        }
    }

    private var panelBackground: some View {
        NotchPanelOutlineShape(bottomCornerRadius: NotchPanelStyle.bottomCornerRadius)
            .fill(NotchPanelStyle.fillColor)
            .overlay(alignment: .top) {
                NotchPanelOutlineShape(bottomCornerRadius: NotchPanelStyle.bottomCornerRadius)
                    .fill(NotchPanelStyle.topHighlight)
                    .frame(height: NotchPanelStyle.topHighlightHeight)
                    .clipped()
            }
    }

    private func usageSection(snapshot: UsageSnapshot) -> some View {
        UsageMenuSectionView(
            snapshot: snapshot,
            isRefreshing: isUsageRefreshing,
            action: openUsageSettings,
            cardWidth: Self.usageCardWidth
        )
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
                    ForEach(displaySessions) { session in
                        sessionRow(session)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func toolGroupSection(_ group: SessionListPresentation.Group) -> some View {
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
        let primaryText = SessionDisplayFormatter.primaryText(for: session, isGrouped: isGrouped)
        let secondaryText = SessionDisplayFormatter.secondaryText(for: session, isGrouped: isGrouped)
        let badges = SessionDisplayFormatter.badges(for: session)
        let interaction = model.pendingInteraction(for: session)
        let interactionActions = interaction.map(SessionDisplayFormatter.interactionActions) ?? []
        let contentIndent: CGFloat = isGrouped ? 13 : 29
        let isCondensed = SessionListPresentation.isCondensed(session, now: model.summary.updatedAt)

        VStack(alignment: .leading, spacing: 4) {
            Button {
                onOpenSession(session)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
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

                        Text(primaryText)
                            .font(.system(size: 12))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer(minLength: 8)

                        if !badges.isEmpty {
                            SessionBadgeStrip(badges: badges, compact: true)
                                .layoutPriority(1)
                        }
                    }

                    if !isCondensed {
                        HStack(spacing: 6) {
                            sessionStatusSummary(session)

                            if let secondaryText {
                                Text(secondaryText)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.leading, contentIndent)

                        Text(displayDirectory(for: session))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .padding(.leading, contentIndent)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(NotchSessionButtonStyle(isHovered: hoveredSessionID == session.id))
            .focusable(false)
            .onHover { hovering in
                hoveredSessionID = hovering ? session.id : nil
            }

            if let interaction, !interactionActions.isEmpty {
                interactionButtonStrip(
                    interaction: interaction,
                    actions: interactionActions,
                    leading: contentIndent
                )
            }
        }
    }

    @ViewBuilder
    private func interactionButtonStrip(
        interaction: PendingInteraction,
        actions: [SessionInteractionAction],
        leading: CGFloat
    ) -> some View {
        HStack(spacing: 6) {
            ForEach(actions) { action in
                if action.role == .primary {
                    Button(action.label) {
                        model.resolveInteraction(interaction, decision: action.decision)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else {
                    Button(action.label) {
                        model.resolveInteraction(interaction, decision: action.decision)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(.leading, leading)
    }

    @ViewBuilder
    private func sessionStatusSummary(_ session: SessionSnapshot) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color(for: session.status))
                .frame(width: 6, height: 6)

            Text(session.status.displayName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color(for: session.status))

            Text(sessionDuration(for: session))
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            footerActionButton(
                title: l10n.string(.refresh),
                systemImage: "arrow.clockwise",
                action: onRefresh
            )

            footerActionButton(
                title: l10n.string(.settings),
                systemImage: "gearshape",
                action: onOpenSettings
            )

            Spacer(minLength: 0)

            footerActionButton(
                title: l10n.string(.quit),
                systemImage: "power",
                action: onQuit
            )
        }
        .padding(.top, 2)
    }

    private func footerActionButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .imageScale(.small)
                .padding(.horizontal, 10)
                .frame(height: 27)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(NotchFooterActionButtonStyle())
        .focusable(false)
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
        SessionDisplayFormatter.directoryText(for: session, maxLength: 62)
    }

    private func sessionDuration(for session: SessionSnapshot) -> String {
        SessionDurationFormatter.string(for: session, now: model.summary.updatedAt)
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

private struct NotchSessionButtonStyle: ButtonStyle {
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.14 : (isHovered ? 0.08 : 0)))
            )
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}

private struct NotchFooterActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.1 : 0.05))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        Color.white.opacity(configuration.isPressed ? 0.12 : 0.07),
                        lineWidth: 1
                    )
            }
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
