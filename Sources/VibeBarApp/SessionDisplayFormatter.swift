import Foundation
import VibeBarCore

@MainActor
enum SessionDisplayFormatter {
    static func primaryText(for session: SessionSnapshot, isGrouped: Bool) -> String {
        if let title = normalized(session.title) {
            return title
        }

        return processSummary(for: session, isGrouped: isGrouped, includeTool: !isGrouped)
    }

    static func secondaryText(for session: SessionSnapshot, isGrouped: Bool) -> String? {
        guard normalized(session.title) != nil else {
            return nil
        }

        return normalized(processSummary(for: session, isGrouped: isGrouped, includeTool: !isGrouped))
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

        if context.origin != .desktop,
           let tty = normalized(context.tty) {
            badges.append(
                SessionBadge(
                    kind: .tty,
                    text: tty,
                    tone: .neutral
                )
            )
        }

        return badges
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
            return SessionBadge(kind: .origin, text: "Codex Desktop", tone: .origin)
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
