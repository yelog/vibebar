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
            clientTabTitle: "NVIM:Redis",
            clientTabIndex: 2,
            sessionManagerKind: .tmux,
            sessionManagerSessionID: "/tmp/tmux-501/default,123,0",
            sessionManagerPaneID: "%11",
            origin: .cli
        )
    )

    let badges = SessionDisplayFormatter.badges(for: session)
    #expect(Array(badges.dropFirst().map(\.text)) == ["Kitty #2", "tmux"])
}

@MainActor
@Test func kittyTabBadgeFallsBackToTabIndex() {
    let session = makeSession(
        terminalContext: TerminalContext(
            clientKind: .kitty,
            bundleIdentifier: "net.kovidgoyal.kitty",
            clientTabIndex: 3,
            origin: .cli
        )
    )

    let badges = SessionDisplayFormatter.badges(for: session)
    #expect(Array(badges.dropFirst().map(\.text)) == ["Kitty #3"])
}

@MainActor
@Test func tmuxBadgeIncludesWindowIndexWhenAvailable() {
    let session = makeSession(
        terminalContext: TerminalContext(
            clientKind: .ghostty,
            bundleIdentifier: "com.mitchellh.ghostty",
            sessionManagerKind: .tmux,
            sessionManagerSessionID: "/tmp/tmux-501/default,123,0",
            sessionManagerPaneID: "%3",
            sessionManagerTabIndex: 2,
            origin: .cli
        )
    )

    let badges = SessionDisplayFormatter.badges(for: session)
    #expect(Array(badges.dropFirst().map(\.text)) == ["Ghostty", "tmux #2"])
}

@MainActor
@Test func weztermBadgeIncludesTabIndexWhenAvailable() {
    let session = makeSession(
        terminalContext: TerminalContext(
            clientKind: .wezterm,
            bundleIdentifier: "com.github.wez.wezterm",
            clientSessionID: "42",
            clientTabIndex: 4,
            origin: .cli
        )
    )

    let badges = SessionDisplayFormatter.badges(for: session)
    #expect(Array(badges.dropFirst().map(\.text)) == ["WezTerm #4"])
}

@MainActor
@Test func iTermBadgeIncludesTabIndexWhenAvailable() {
    let session = makeSession(
        terminalContext: TerminalContext(
            clientKind: .iterm,
            bundleIdentifier: "com.googlecode.iterm2",
            clientSessionID: "w0t0p0",
            clientTabIndex: 2,
            origin: .cli
        )
    )

    let badges = SessionDisplayFormatter.badges(for: session)
    #expect(Array(badges.dropFirst().map(\.text)) == ["iTerm #2"])
}

@MainActor
@Test func zellijBadgeIncludesTabIndexWhenAvailable() {
    let session = makeSession(
        terminalContext: TerminalContext(
            clientKind: .ghostty,
            bundleIdentifier: "com.mitchellh.ghostty",
            sessionManagerKind: .zellij,
            sessionManagerSessionID: "workspace",
            sessionManagerPaneID: "7",
            sessionManagerTabIndex: 1,
            origin: .cli
        )
    )

    let badges = SessionDisplayFormatter.badges(for: session)
    #expect(Array(badges.dropFirst().map(\.text)) == ["Ghostty", "zellij #1"])
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

    let badges = SessionDisplayFormatter.badges(for: session)
    #expect(Array(badges.dropFirst().map(\.text)) == ["Codex App"])
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

    #expect(SessionDisplayFormatter.secondaryText(for: session, context: .flat) == "Codex")
}

@MainActor
@Test func primaryAndSecondaryTextPreferCurrentTaskWhenAvailable() {
    let session = makeSession(
        pid: 42,
        title: "修复 Codex session 检测",
        currentTask: "正在比对 rollout 与 session index"
    )

    #expect(SessionDisplayFormatter.primaryText(for: session, context: .flat) == "修复 Codex session 检测")
    #expect(SessionDisplayFormatter.secondaryText(for: session, context: .flat) == "正在比对 rollout 与 session index")
}

@MainActor
@Test func primaryTextFallsBackToCurrentTaskWithoutTitle() {
    let session = makeSession(
        pid: 42,
        currentTask: "等待用户确认继续执行"
    )

    #expect(SessionDisplayFormatter.primaryText(for: session, context: .flat) == "等待用户确认继续执行")
    #expect(SessionDisplayFormatter.secondaryText(for: session, context: .flat) == "Codex")
}

@MainActor
@Test func primaryTextFallsBackToUnnamedSessionWithoutTitleOrTask() {
    let session = makeSession(pid: 42, cwd: nil)

    #expect(SessionDisplayFormatter.primaryText(for: session, context: .flat) == L10n.shared.string(.unnamedSession))
    #expect(SessionDisplayFormatter.secondaryText(for: session, context: .flat) == "Codex")
}

@MainActor
@Test func projectGroupSuppressesDirectoryAndToolNameFallback() {
    let session = makeSession(pid: 42, title: "修复项目分组")

    #expect(SessionDisplayFormatter.secondaryText(for: session, context: .projectGroup) == nil)
    #expect(SessionDisplayFormatter.directoryText(for: session, context: .projectGroup) == nil)
    #expect(SessionDisplayFormatter.directoryText(for: session, context: .toolGroup) == "/tmp/project")
}

@MainActor
@Test func interactionActionsPreserveOriginalPermissionOptions() {
    let interaction = PendingInteraction(
        id: "request-1",
        sessionID: "session-1",
        tool: .opencode,
        kind: .permission,
        message: "Access external directory",
        options: [
            InteractionOption(id: "once", label: "Allow once"),
            InteractionOption(id: "always", label: "Allow always"),
            InteractionOption(id: "reject", label: "Reject"),
        ],
        requestedAt: Date()
    )

    let actions = SessionDisplayFormatter.interactionActions(for: interaction)

    #expect(actions.map(\.label) == ["Allow once", "Allow always", "Reject"])
    #expect(actions.map(\.role) == [.primary, .primary, .secondary])
    #expect(actions.map(\.decision.optionID) == ["once", "always", "reject"])
}

@MainActor
@Test func interactionActionsSynthesizeOriginalOptionsForLegacyOpenCodePermission() {
    let interaction = PendingInteraction(
        id: "request-legacy",
        sessionID: "session-1",
        tool: .opencode,
        kind: .permission,
        message: "允许访问目录",
        requestedAt: Date(),
        transportContext: [
            "source": "opencode-plugin",
            "request_kind": "permission",
            "opencode_request_id": "per_123",
        ]
    )

    let actions = SessionDisplayFormatter.interactionActions(for: interaction)

    #expect(actions.map(\.label) == ["Allow once", "Allow always", "Reject"])
    #expect(actions.map(\.decision.optionID) == ["once", "always", "reject"])
}

@MainActor
@Test func interactionActionsFallbackToAllowAndDenyForLegacyPermission() {
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
    cwd: String? = "/tmp/project",
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
        cwd: cwd,
        command: ["codex"],
        title: title,
        currentTask: currentTask,
        terminalContext: terminalContext
    )
}
