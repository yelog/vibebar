import Foundation
import Testing
import VibeBarCore
@testable import VibeBarApp

@MainActor
@Test func terminalBadgesIncludeClientAndManagerOnly() {
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

    #expect(SessionDisplayFormatter.badges(for: session).map(\.text) == ["Kitty", "tmux"])
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

@MainActor
@Test func primaryAndSecondaryTextPreferCurrentTaskWhenAvailable() {
    let session = makeSession(
        pid: 42,
        title: "修复 Codex session 检测",
        currentTask: "正在比对 rollout 与 session index"
    )

    #expect(SessionDisplayFormatter.primaryText(for: session, isGrouped: false) == "修复 Codex session 检测")
    #expect(SessionDisplayFormatter.secondaryText(for: session, isGrouped: false) == "正在比对 rollout 与 session index")
}

@MainActor
@Test func primaryTextFallsBackToCurrentTaskWithoutTitle() {
    let session = makeSession(
        pid: 42,
        currentTask: "等待用户确认继续执行"
    )

    #expect(SessionDisplayFormatter.primaryText(for: session, isGrouped: false) == "等待用户确认继续执行")
    #expect(SessionDisplayFormatter.secondaryText(for: session, isGrouped: false) == "Codex · pid 42")
}

@MainActor
@Test func interactionActionsProvideAllowAndDenyForPermission() {
    let interaction = PendingInteraction(
        id: "request-1",
        sessionID: "session-1",
        tool: .claudeCode,
        kind: .permission,
        message: "允许执行吗？",
        requestedAt: Date()
    )

    let labels = SessionDisplayFormatter.interactionActions(for: interaction).map(\.label)
    #expect(labels == ["允许", "拒绝"])
}

private func makeSession(
    pid: Int32 = 123,
    title: String? = nil,
    currentTask: String? = nil,
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
        currentTask: currentTask,
        terminalContext: terminalContext
    )
}
