import Foundation
import VibeBarCore

struct SessionInteractionAction: Identifiable, Sendable, Equatable {
    enum Role: Sendable, Equatable {
        case primary
        case secondary
    }

    var id: String
    var label: String
    var role: Role
    var decision: InteractionDecision
}

@MainActor
enum SessionDisplayFormatter {
    static func primaryText(for session: SessionSnapshot, isGrouped: Bool) -> String {
        if let title = normalized(session.title) {
            return title
        }

        if let currentTask = normalized(session.currentTask) {
            return currentTask
        }

        return processSummary(for: session, isGrouped: isGrouped, includeTool: !isGrouped)
    }

    static func secondaryText(for session: SessionSnapshot, isGrouped: Bool) -> String? {
        let title = normalized(session.title)
        let currentTask = normalized(session.currentTask)
        let summary = normalized(processSummary(for: session, isGrouped: isGrouped, includeTool: !isGrouped))

        if let title {
            if let currentTask, currentTask != title {
                return currentTask
            }
            return summary
        }

        if currentTask != nil {
            return summary
        }

        return nil
    }

    static func directoryText(for session: SessionSnapshot, maxLength: Int = 70) -> String {
        guard let cwd = normalized(session.cwd) else {
            return L10n.shared.string(.dirUnknown)
        }

        let abbreviated = (cwd as NSString).abbreviatingWithTildeInPath
        if abbreviated.count <= maxLength {
            return abbreviated
        }
        return "…" + abbreviated.suffix(maxLength - 1)
    }

    static func badges(for session: SessionSnapshot) -> [SessionBadge] {
        guard let context = session.terminalContext else { return [] }

        var badges: [SessionBadge] = []

        if let originBadge = originBadge(for: context.origin) {
            badges.append(originBadge)
        }

        if context.origin != .desktop,
           let clientBadge = clientBadge(for: context.clientKind) {
            badges.append(clientBadge)
        }

        if let managerBadge = sessionManagerBadge(for: context.sessionManagerKind) {
            badges.append(managerBadge)
        }

        return badges
    }

    static func interactionActions(for interaction: PendingInteraction) -> [SessionInteractionAction] {
        switch interaction.kind {
        case .permission:
            return [
                SessionInteractionAction(
                    id: "\(interaction.id)-allow",
                    label: "允许",
                    role: .primary,
                    decision: InteractionDecision(behavior: .allow)
                ),
                SessionInteractionAction(
                    id: "\(interaction.id)-deny",
                    label: "拒绝",
                    role: .secondary,
                    decision: InteractionDecision(behavior: .deny)
                ),
            ]
        case .question:
            return interaction.options.map { option in
                SessionInteractionAction(
                    id: "\(interaction.id)-\(option.id)",
                    label: option.label,
                    role: .primary,
                    decision: InteractionDecision(
                        behavior: .select,
                        optionID: option.id,
                        text: option.label
                    )
                )
            }
        case .planReview:
            return [
                SessionInteractionAction(
                    id: "\(interaction.id)-continue",
                    label: "继续",
                    role: .primary,
                    decision: InteractionDecision(behavior: .allow)
                ),
                SessionInteractionAction(
                    id: "\(interaction.id)-deny",
                    label: "拒绝",
                    role: .secondary,
                    decision: InteractionDecision(behavior: .deny)
                ),
            ]
        }
    }

    private static func processSummary(
        for session: SessionSnapshot,
        isGrouped: Bool,
        includeTool: Bool
    ) -> String {
        var parts: [String] = []

        if includeTool {
            parts.append(session.tool.displayName)
        }

        if session.pid > 0 {
            parts.append("pid \(session.pid)")
        } else {
            parts.append(session.tool.displayName)
        }

        if isGrouped && session.pid <= 0 {
            return session.tool.displayName
        }

        return normalized(parts.joined(separator: " · ")) ?? session.tool.displayName
    }

    private static func clientBadge(for kind: TerminalClientKind) -> SessionBadge? {
        switch kind {
        case .kitty:
            return SessionBadge(kind: .client, text: "Kitty", tone: .client)
        case .ghostty:
            return SessionBadge(kind: .client, text: "Ghostty", tone: .client)
        case .iterm:
            return SessionBadge(kind: .client, text: "iTerm", tone: .client)
        case .warp:
            return SessionBadge(kind: .client, text: "Warp", tone: .client)
        case .terminal:
            return SessionBadge(kind: .client, text: "Terminal", tone: .client)
        case .unknown:
            return nil
        }
    }

    private static func sessionManagerBadge(for kind: SessionManagerKind) -> SessionBadge? {
        switch kind {
        case .tmux:
            return SessionBadge(kind: .manager, text: "tmux", tone: .manager)
        case .zellij:
            return SessionBadge(kind: .manager, text: "zellij", tone: .manager)
        case .none, .unknown:
            return nil
        }
    }

    private static func originBadge(for origin: SessionOriginKind) -> SessionBadge? {
        switch origin {
        case .desktop:
            return SessionBadge(kind: .origin, text: "Codex App", tone: .origin)
        case .cli, .unknown:
            return nil
        }
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
