import Foundation
import Testing
import VibeBarCore
@testable import VibeBarApp

@MainActor
@Test func durationBadgeCarriesSessionStatusAccent() throws {
    let now = Date(timeIntervalSince1970: 10_000)
    let session = makeSession(
        status: .awaitingInput,
        statusSince: now.addingTimeInterval(-90)
    )

    let badge = try #require(SessionDisplayFormatter.badges(for: session, now: now).first)

    #expect(badge.kind == .duration)
    #expect(badge.text == "\(session.status.displayName) 1m")
    #expect(badge.tone == .status)
    #expect(badge.accentState == .awaitingInput)
}

@MainActor
@Test func durationBadgePreservesUnknownAccentState() throws {
    let now = Date(timeIntervalSince1970: 10_000)
    let session = makeSession(
        status: .unknown,
        statusSince: now.addingTimeInterval(-30),
        terminalContext: nil
    )

    let badge = try #require(SessionDisplayFormatter.badges(for: session, now: now).first)

    #expect(badge.text == "\(session.status.displayName) 30s")
    #expect(badge.accentState == .unknown)
}

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
@Test func openCodeRunningSessionKeepsSessionNameAsPrimaryAndExposesUserMessageAndRunningSummarySeparately() {
    let session = makeSession(
        tool: .opencode,
        status: .running,
        title: "分析页面并编写 Claude Code hello 接口 curl 测试",
        currentTask: "处理中",
        lastUserMessage: "请分析如下页面，并给出 curl 测试 anthropic 的 claude code 的测试 hello 的接口",
        runningSummary: "我再看一下前端脚本里有没有示例请求或认证头说明，避免只凭 OpenAI 兼容经验猜测。"
    )

    #expect(
        SessionDisplayFormatter.primaryText(for: session, context: .flat) ==
        "分析页面并编写 Claude Code hello 接口 curl 测试"
    )
    #expect(
        SessionDisplayFormatter.secondaryText(for: session, context: .flat) ==
        "我再看一下前端脚本里有没有示例请求或认证头说明，避免只凭 OpenAI 兼容经验猜测。"
    )
    #expect(
        SessionDisplayFormatter.supplementalLastUserMessageText(for: session) ==
        "请分析如下页面，并给出 curl 测试 anthropic 的 claude code 的测试 hello 的接口"
    )
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

@MainActor
@Test func planReviewKeepsContinueAndDenyActions() {
    let interaction = PendingInteraction(
        id: "codex-plan",
        sessionID: "plugin-codex-hook-sess-1",
        tool: .codex,
        kind: .planReview,
        title: "计划审查",
        message: "是否继续按这个计划执行？",
        prompts: [
            InteractionPrompt(
                id: "review",
                title: "补充意见",
                allowsFreeText: true
            )
        ],
        allowsFreeText: true,
        requestedAt: Date()
    )

    let actions = SessionDisplayFormatter.interactionActions(for: interaction)
    #expect(actions.map { $0.label } == ["继续", "拒绝"])
    #expect(actions.map { $0.decision.behavior } == [.allow, .deny])
}

@MainActor
@Test func codexStructuredQuestionRequiresStructuredInput() {
    let interaction = PendingInteraction(
        id: "codex-question",
        sessionID: "plugin-codex-hook-sess-2",
        tool: .codex,
        kind: .question,
        message: "请回答以下问题",
        prompts: [
            InteractionPrompt(
                id: "工作模式",
                title: "你希望我接下来以哪种方式协作？",
                options: [
                    InteractionOption(id: "direct", label: "直接执行"),
                    InteractionOption(id: "plan", label: "先给方案"),
                ]
            ),
            InteractionPrompt(
                id: "补充要求",
                title: "是否补充额外约束？",
                allowsFreeText: true
            ),
        ],
        requestedAt: Date()
    )

    #expect(SessionDisplayFormatter.requiresStructuredInput(for: interaction))
}

@MainActor
@Test func freeTextQuestionRequiresStructuredInput() {
    let interaction = PendingInteraction(
        id: "codex-free-text",
        sessionID: "plugin-codex-hook-sess-3",
        tool: .codex,
        kind: .question,
        message: "请输入你的回答",
        allowsFreeText: true,
        requestedAt: Date()
    )

    #expect(SessionDisplayFormatter.requiresStructuredInput(for: interaction))
}

private func makeSession(
    pid: Int32 = 123,
    tool: ToolKind = .codex,
    status: ToolActivityState = .running,
    statusSince: Date? = nil,
    idleSince: Date? = nil,
    title: String? = nil,
    currentTask: String? = nil,
    lastUserMessage: String? = nil,
    runningSummary: String? = nil,
    cwd: String? = "/tmp/project",
    terminalContext: TerminalContext? = nil
) -> SessionSnapshot {
    SessionSnapshot(
        id: "codex-session",
        tool: tool,
        pid: pid,
        status: status,
        source: .sessionFile,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_030),
        statusSince: statusSince,
        idleSince: idleSince,
        cwd: cwd,
        command: [tool.executable],
        title: title,
        currentTask: currentTask,
        lastUserMessage: lastUserMessage,
        runningSummary: runningSummary,
        terminalContext: terminalContext
    )
}
