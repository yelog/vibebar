import SwiftUI
import VibeBarCore

struct NotchExpandedBodyView: View {
    private static let usageCardWidth: CGFloat = 412

    @ObservedObject var model: MonitorViewModel
    let usageSnapshot: UsageSnapshot?
    let usageEnabled: Bool
    let isUsageRefreshing: Bool
    let onRefresh: () -> Void
    let onOpenSettings: () -> Void
    let onOpenSession: (SessionSnapshot) -> Void
    let onQuit: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var settings = AppSettings.shared
    @State private var collapsedGroupIDs: Set<String> = []
    @State private var hoveredSessionID: String? = nil

    private var displaySessions: [SessionSnapshot] {
        SessionListPresentation.sortedSessions(model.sessions)
    }

    private var groupedSessions: [SessionListPresentation.Group] {
        SessionListPresentation.groupedSessions(model.sessions, mode: settings.sessionGroupingMode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sessionsSection

            if usageEnabled, let usageSnapshot {
                Divider()
                    .opacity(0.25)

                usageSection(snapshot: usageSnapshot)
            }
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

    @ViewBuilder
    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SessionSectionHeaderView(
                title: l10n.string(.sessionTitle),
                selection: $settings.sessionGroupingMode,
                compact: true
            )

            if model.sessions.isEmpty {
                Text(l10n.string(.noSessions))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else if settings.sessionGroupingMode != .none {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(groupedSessions) { group in
                        groupSection(group)
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
    private func groupSection(_ group: SessionListPresentation.Group) -> some View {
        let isExpanded = !collapsedGroupIDs.contains(group.id)
        let title = SessionListPresentation.title(for: group)
        let detail = SessionListPresentation.detail(for: group)

        VStack(alignment: .leading, spacing: 5) {
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
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)

                    switch group.kind {
                    case .tool(let tool):
                        if let icon = ToolIconLoader.icon(for: tool) {
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
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)

                    if let detail {
                        Text("· \(detail)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

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
                        sessionRow(session, context: group.kind.rowContext)
                    }
                }
                .padding(.leading, 20)
            }
        }
    }

    @ViewBuilder
    private func sessionRow(
        _ session: SessionSnapshot,
        context: SessionRowPresentationContext = .flat
    ) -> some View {
        let primaryText = SessionDisplayFormatter.primaryText(for: session, context: context)
        let lastUserMessage = SessionDisplayFormatter.supplementalLastUserMessageText(for: session)
        let secondaryText = lastUserMessage == nil
            ? SessionDisplayFormatter.secondaryText(for: session, context: context)
            : nil
        let runningSummary = SessionDisplayFormatter.runningSummaryText(for: session)
        let directoryText = SessionDisplayFormatter.directoryText(for: session, context: context, maxLength: 62)
        let badges = SessionDisplayFormatter.badges(for: session, now: model.summary.updatedAt)
        let interaction = model.pendingInteraction(for: session)
        let interactionActions = interaction.map(SessionDisplayFormatter.interactionActions) ?? []
        let contentIndent = context.contentIndent
        let isCondensed = SessionListPresentation.isCondensed(session, now: model.summary.updatedAt)

        VStack(alignment: .leading, spacing: 4) {
            Button {
                onOpenSession(session)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        if context.showsToolIcon {
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

                        MorphText(text: primaryText, font: .system(size: 12), color: .primary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer(minLength: 8)

                        if !badges.isEmpty {
                            SessionBadgeStrip(badges: badges, compact: true)
                                .layoutPriority(1)
                        }
                    }

                    if !isCondensed {
                        if let lastUserMessage {
                            HStack(spacing: 6) {
                                MorphText(text: "$ \(lastUserMessage)", font: .system(size: 10), color: .secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)

                                Spacer(minLength: 0)
                            }
                            .padding(.leading, contentIndent)
                        } else if let secondaryText {
                            HStack(spacing: 6) {
                                MorphText(text: secondaryText, font: .system(size: 10), color: .secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)

                                Spacer(minLength: 0)
                            }
                            .padding(.leading, contentIndent)
                        }

                        if let row3Text = lastUserMessage != nil ? (runningSummary ?? directoryText) : directoryText {
                            MorphText(text: row3Text, font: .system(size: 10), color: .secondary)
                                .lineLimit(1)
                                .padding(.leading, contentIndent)
                        }
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

    private func color(for state: ToolActivityState) -> Color {
        AppSettings.shared.swiftUIColor(for: state, colorScheme: colorScheme)
    }

    private func orderedStates(for sessions: [SessionSnapshot]) -> [ToolActivityState] {
        let priority: [ToolActivityState] = [.running, .awaitingInput, .idle, .unknown]
        return priority.filter { state in
            sessions.contains { $0.status == state }
        }.prefix(3).map { $0 }
    }

    private func openUsageSettings() {
        SettingsWindowController.shared.showSettings(tab: .usage)
    }
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
