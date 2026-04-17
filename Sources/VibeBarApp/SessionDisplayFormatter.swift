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
    static func primaryText(
        for session: SessionSnapshot,
        context: SessionRowPresentationContext
    ) -> String {
        return sessionName(for: session)
    }

    static func secondaryText(
        for session: SessionSnapshot,
        context: SessionRowPresentationContext
    ) -> String? {
        if let runningSummary = runningSummaryText(for: session) {
            return runningSummary
        }

        guard context != .projectGroup else {
            return nil
        }

        return session.tool.displayName
    }

    static func runningSummaryText(for session: SessionSnapshot) -> String? {
        let sessionName = sessionName(for: session)
        let lastUserMessage = normalized(session.lastUserMessage)

        guard let runningSummary = normalized(session.runningSummary),
              !isSuppressedCodexToolLabel(runningSummary, session: session),
              runningSummary != sessionName,
              runningSummary != lastUserMessage else {
            guard let legacyCurrentTask = normalized(session.currentTask),
                  !isSuppressedCodexToolLabel(legacyCurrentTask, session: session),
                  legacyCurrentTask != sessionName,
                  legacyCurrentTask != lastUserMessage else {
                return nil
            }
            return legacyCurrentTask
        }

        return runningSummary
    }

    static func supplementalLastUserMessageText(for session: SessionSnapshot) -> String? {
        let sessionName = sessionName(for: session)
        guard let lastUserMessage = normalized(session.lastUserMessage),
              lastUserMessage != sessionName else {
            return nil
        }
        return lastUserMessage
    }

    static func sessionName(for session: SessionSnapshot) -> String {
        if let title = normalized(session.title) {
            return title
        }

        if let currentTask = normalized(session.currentTask),
           !isSuppressedCodexToolLabel(currentTask, session: session) {
            return currentTask
        }

        return L10n.shared.string(.unnamedSession)
    }

    private static func isSuppressedCodexToolLabel(_ value: String, session: SessionSnapshot) -> Bool {
        session.tool == .codex && CodexLabelHeuristics.isLowSignalToolLabel(value)
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

    static func directoryText(
        for session: SessionSnapshot,
        context: SessionRowPresentationContext,
        maxLength: Int = 70
    ) -> String? {
        guard context.showsDirectory else {
            return nil
        }
        return directoryText(for: session, maxLength: maxLength)
    }

    static func badges(for session: SessionSnapshot, now: Date = Date()) -> [SessionBadge] {
        guard let context = session.terminalContext else {
            return durationOnlyBadge(session: session, now: now)
        }

        var badges: [SessionBadge] = []

        badges.append(durationBadge(for: session, now: now))

        if let originBadge = originBadge(for: context.origin) {
            badges.append(originBadge)
        }

        if context.origin != .desktop,
           let clientBadge = clientBadge(for: context) {
            badges.append(clientBadge)
        }

        if let tabBadge = clientTabBadge(for: context) {
            badges.append(tabBadge)
        }

        if let managerBadge = sessionManagerBadge(for: context) {
            badges.append(managerBadge)
        }

        return badges
    }

    private static func durationOnlyBadge(session: SessionSnapshot, now: Date) -> [SessionBadge] {
        [durationBadge(for: session, now: now)]
    }

    private static func durationBadge(for session: SessionSnapshot, now: Date) -> SessionBadge {
        let duration = DurationBadgeFormatter.string(for: session, now: now)
        let statusText = session.status.displayName

        return SessionBadge(
            kind: .duration,
            text: "\(statusText) \(duration)",
            tone: .status,
            accentState: session.status
        )
    }

    static func interactionActions(for interaction: PendingInteraction) -> [SessionInteractionAction] {
        let displayOptions = interaction.displayOptions
        if !displayOptions.isEmpty {
            return displayOptions.map { option in
                SessionInteractionAction(
                    id: "\(interaction.id)-\(option.id)",
                    label: option.label,
                    role: option.id == "reject" ? .secondary : .primary,
                    decision: InteractionDecision(
                        behavior: .select,
                        optionID: option.id,
                        text: option.label
                    )
                )
            }
        }

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

    static func requiresStructuredInput(for interaction: PendingInteraction) -> Bool {
        if interaction.kind == .planReview {
            return interaction.prompts.contains(where: \.allowsFreeText) || interaction.allowsFreeText
        }

        if interaction.prompts.count > 1 {
            return true
        }

        if interaction.prompts.contains(where: { $0.allowsFreeText || $0.allowsMultipleSelection }) {
            return true
        }

        if interaction.allowsFreeText {
            return true
        }

        return false
    }

    private static func clientBadge(for context: TerminalContext) -> SessionBadge? {
        switch context.clientKind {
        case .kitty:
            if let index = context.clientTabIndex {
                return SessionBadge(kind: .client, text: "Kitty #\(index)", tone: .client)
            }
            return SessionBadge(kind: .client, text: "Kitty", tone: .client)
        case .ghostty:
            if let index = context.clientTabIndex {
                return SessionBadge(kind: .client, text: "Ghostty #\(index)", tone: .client)
            }
            return SessionBadge(kind: .client, text: "Ghostty", tone: .client)
        case .wezterm:
            if let index = context.clientTabIndex {
                return SessionBadge(kind: .client, text: "WezTerm #\(index)", tone: .client)
            }
            return SessionBadge(kind: .client, text: "WezTerm", tone: .client)
        case .iterm:
            if let index = context.clientTabIndex {
                return SessionBadge(kind: .client, text: "iTerm #\(index)", tone: .client)
            }
            return SessionBadge(kind: .client, text: "iTerm", tone: .client)
        case .warp:
            return SessionBadge(kind: .client, text: "Warp", tone: .client)
        case .terminal:
            return SessionBadge(kind: .client, text: "Terminal", tone: .client)
        case .unknown:
            return nil
        }
    }

    private static func sessionManagerBadge(for context: TerminalContext) -> SessionBadge? {
        switch context.sessionManagerKind {
        case .tmux:
            if let index = context.sessionManagerTabIndex {
                return SessionBadge(kind: .manager, text: "tmux #\(index)", tone: .manager)
            }
            return SessionBadge(kind: .manager, text: "tmux", tone: .manager)
        case .zellij:
            if let index = context.sessionManagerTabIndex {
                return SessionBadge(kind: .manager, text: "zellij #\(index)", tone: .manager)
            }
            return SessionBadge(kind: .manager, text: "zellij", tone: .manager)
        case .none, .unknown:
            return nil
        }
    }

    private static func clientTabBadge(for context: TerminalContext) -> SessionBadge? {
        return nil
    }

    private static func originBadge(for origin: SessionOriginKind) -> SessionBadge? {
        switch origin {
        case .desktop:
            return SessionBadge(kind: .origin, text: "Codex App", tone: .client)
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
