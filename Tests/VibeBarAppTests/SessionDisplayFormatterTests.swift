import Foundation
import Testing
import VibeBarCore
@testable import VibeBarApp

@MainActor
@Test func terminalBadgesIncludeClientManagerAndTTY() {
    let session = makeSession(
        terminalContext: TerminalContext(
            clientKind: .kitty,
            bundleIdentifier: "net.kovidgoyal.kitty",
            tty: "ttys014",
            sessionManagerKind: .tmux,
            sessionManagerSessionID: "/tmp/tmux-501/default,123,0",
            sessionManagerPaneID: "%11",
            origin: .cli
        )
    )

    #expect(SessionDisplayFormatter.badges(for: session).map(\.text) == ["Kitty", "tmux", "ttys014"])
}

@MainActor
@Test func terminalBadgesPreferDesktopOriginBadge() {
    let session = makeSession(
        terminalContext: TerminalContext(
            clientKind: .unknown,
            bundleIdentifier: "com.openai.codex",
            sessionManagerKind: .unknown,
            origin: .desktop
        )
    )

    #expect(SessionDisplayFormatter.badges(for: session).map(\.text) == ["Codex Desktop"])
}

@MainActor
@Test func secondaryTextDoesNotDuplicateTerminalSummary() {
    let session = makeSession(
        pid: 42,
        title: "修复 Codex session 检测",
        terminalContext: TerminalContext(
            clientKind: .ghostty,
            tty: "ttys006",
            sessionManagerKind: .zellij,
            sessionManagerSessionID: "dev",
            sessionManagerPaneID: "3",
            origin: .cli
        )
    )

    #expect(SessionDisplayFormatter.secondaryText(for: session, isGrouped: false) == "Codex · pid 42")
}

private func makeSession(
    pid: Int32 = 123,
    title: String? = nil,
    terminalContext: TerminalContext? = nil
) -> SessionSnapshot {
    SessionSnapshot(
        id: "codex-session",
        tool: .codex,
        pid: pid,
        status: .running,
        source: .sessionFile,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_030),
        cwd: "/tmp/project",
        command: ["codex"],
        title: title,
        terminalContext: terminalContext
    )
}
