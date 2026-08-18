import Foundation
import Testing
import VibeBarCore
@testable import VibeBarApp

@Test func mergeDetectedDetailsBackfillsSessionNameWithoutOverwritingPluginState() {
    let pluginSession = SessionSnapshot(
        id: "plugin-codex-60558",
        tool: .codex,
        pid: 60558,
        parentPID: 17237,
        status: .idle,
        source: .plugin,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_120),
        cwd: "/Users/yelog/workspace/rust/rust-redis-desktop",
        command: ["codex"],
        notes: "codex-hook:heartbeat"
    )

    let detectedSession = SessionSnapshot(
        id: "codex-session-019d5bd2",
        tool: .codex,
        pid: 60558,
        parentPID: 17237,
        status: .running,
        source: .sessionFile,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_090),
        lastOutputAt: Date(timeIntervalSince1970: 1_700_000_090),
        cwd: "/Users/yelog/workspace/rust/rust-redis-desktop",
        command: ["codex"],
        notes: "codex-session-file",
        title: "改为显示 Session 名称和分析实施",
        currentTask: "分析并修改 Session 第一行展示",
        terminalContext: TerminalContext(
            clientKind: .kitty,
            bundleIdentifier: "net.kovidgoyal.kitty",
            tty: "ttys011",
            sessionManagerKind: .none,
            origin: .cli
        )
    )

    let merged = MonitorViewModel.mergeDetectedDetails(
        into: pluginSession,
        from: detectedSession
    )

    #expect(merged.id == pluginSession.id)
    #expect(merged.status == .idle)
    #expect(merged.source == .plugin)
    #expect(merged.updatedAt == pluginSession.updatedAt)
    #expect(merged.title == "改为显示 Session 名称和分析实施")
    #expect(merged.currentTask == "分析并修改 Session 第一行展示")
    #expect(merged.terminalContext?.clientKind == .kitty)
}

@Test func shouldPreferFileSessionPrefersPluginCodexSessionOverNewerWrapper() {
    let pluginSession = SessionSnapshot(
        id: "plugin-codex-42",
        tool: .codex,
        pid: 42,
        status: .running,
        source: .plugin,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
        cwd: "/tmp/project",
        command: ["codex"]
    )

    let wrapperSession = SessionSnapshot(
        id: "wrapper-codex-42",
        tool: .codex,
        pid: 42,
        status: .running,
        source: .wrapper,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_200),
        cwd: "/tmp/project",
        command: ["codex"]
    )

    #expect(MonitorViewModel.shouldPreferFileSession(pluginSession, over: wrapperSession) == true)
    #expect(MonitorViewModel.shouldPreferFileSession(wrapperSession, over: pluginSession) == false)
}

@Test func shouldPreferFileSessionPrefersWrapperOverSessionFileForSamePID() {
    let wrapperSession = SessionSnapshot(
        id: "wrapper-codex-42",
        tool: .codex,
        pid: 42,
        status: .running,
        source: .wrapper,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_090),
        cwd: "/tmp/project",
        command: ["codex"]
    )

    let sessionFileSession = SessionSnapshot(
        id: "codex-session-42",
        tool: .codex,
        pid: 42,
        status: .idle,
        source: .sessionFile,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_150),
        cwd: "/tmp/project",
        command: ["codex"]
    )

    #expect(MonitorViewModel.shouldPreferFileSession(wrapperSession, over: sessionFileSession) == true)
    #expect(MonitorViewModel.shouldPreferFileSession(sessionFileSession, over: wrapperSession) == false)
}

@Test func mergePrefersCodexSessionIDWhenPluginAndSessionFilePIDsDoNotMatch() {
    let pluginSession = SessionSnapshot(
        id: "plugin-codex-hook-019d98fe-a301-7bb3-9b41-547555bce9ed",
        tool: .codex,
        pid: 0,
        status: .running,
        source: .plugin,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_120),
        cwd: "/Users/yelog/workspace/swift/VibeBar",
        command: ["codex"],
        title: "请仔细分析一下",
        titleSource: .derived
    )

    let detectedSession = SessionSnapshot(
        id: "codex-session-019d98fe-a301-7bb3-9b41-547555bce9ed",
        tool: .codex,
        pid: 60558,
        status: .running,
        source: .sessionFile,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_150),
        statusSince: Date(timeIntervalSince1970: 1_700_000_090),
        cwd: "/Users/yelog/workspace/swift/VibeBar",
        command: ["codex"],
        title: "测试自定义名称",
        titleSource: .explicit,
        currentTask: "请仔细分析一下",
        terminalContext: TerminalContext(
            clientKind: .kitty,
            bundleIdentifier: "net.kovidgoyal.kitty",
            clientWindowID: "86",
            sessionManagerKind: .none,
            origin: .cli
        )
    )

    let merged = MonitorViewModel.merge(
        fileSessions: [pluginSession],
        processSessions: [detectedSession],
        now: Date(timeIntervalSince1970: 1_700_000_150),
        store: SessionFileStore()
    )

    #expect(merged.count == 1)
    #expect(merged[0].id == pluginSession.id)
    #expect(merged[0].title == "测试自定义名称")
    #expect(merged[0].titleSource == .explicit)
    #expect(merged[0].terminalContext?.clientKind == .kitty)
}

@Test func mergeDetectedDetailsKeepsExistingSessionNameWhenAlreadyPresent() {
    let pluginSession = SessionSnapshot(
        id: "plugin-opencode-25022",
        tool: .opencode,
        pid: 25022,
        status: .running,
        source: .plugin,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_120),
        cwd: "/Users/yelog/workspace/swift/VibeBar",
        command: ["opencode"],
        title: "当前调试会话",
        currentTask: "继续修复合并逻辑"
    )

    let detectedSession = SessionSnapshot(
        id: "opencode-http-ses_abc",
        tool: .opencode,
        pid: 25022,
        status: .idle,
        source: .processScan,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_090),
        cwd: "/Users/yelog/workspace/swift/VibeBar",
        command: ["opencode"],
        title: "HTTP API 标题",
        currentTask: "HTTP API 当前任务"
    )

    let merged = MonitorViewModel.mergeDetectedDetails(
        into: pluginSession,
        from: detectedSession
    )

    #expect(merged.title == "当前调试会话")
    #expect(merged.currentTask == "继续修复合并逻辑")
}

@Test func mergeSuppressesLowSignalIdleOpenCodeSessionWithoutVisibleMetadata() {
    let session = SessionSnapshot(
        id: "plugin-opencode-ghost-session",
        tool: .opencode,
        pid: 0,
        status: .idle,
        source: .plugin,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_020),
        statusSince: Date(timeIntervalSince1970: 1_700_000_020),
        idleSince: Date(timeIntervalSince1970: 1_700_000_020),
        cwd: nil,
        command: ["opencode"]
    )

    let merged = MonitorViewModel.merge(
        fileSessions: [session],
        processSessions: [],
        now: Date(timeIntervalSince1970: 1_700_000_030),
        store: SessionFileStore()
    )

    #expect(merged.isEmpty)
}

@Test func mergeDetectedDetailsReplacesLowSignalOpenCodeRunningSummary() {
    let pluginSession = SessionSnapshot(
        id: "plugin-opencode-25022",
        tool: .opencode,
        pid: 25022,
        status: .running,
        source: .plugin,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_120),
        cwd: "/Users/yelog/workspace/swift/VibeBar",
        command: ["opencode"],
        title: "分析页面并编写 Claude Code hello 接口 curl 测试",
        currentTask: "处理中",
        lastUserMessage: "请分析如下页面，并给出 curl 测试 anthropic 的 claude code 的测试 hello 的接口",
        runningSummary: "处理中"
    )

    let detectedSession = SessionSnapshot(
        id: "opencode-http-ses_abc",
        tool: .opencode,
        pid: 25022,
        status: .running,
        source: .processScan,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_090),
        cwd: "/Users/yelog/workspace/swift/VibeBar",
        command: ["opencode"],
        title: "分析页面并编写 Claude Code hello 接口 curl 测试",
        currentTask: "处理中",
        lastUserMessage: "请分析如下页面，并给出 curl 测试 anthropic 的 claude code 的测试 hello 的接口",
        runningSummary: "我再看一下前端脚本里有没有示例请求或认证头说明，避免只凭 OpenAI 兼容经验猜测。"
    )

    let merged = MonitorViewModel.mergeDetectedDetails(
        into: pluginSession,
        from: detectedSession
    )

    #expect(merged.runningSummary == "我再看一下前端脚本里有没有示例请求或认证头说明，避免只凭 OpenAI 兼容经验猜测。")
}

@Test func mergeDetectedDetailsReplacesLowSignalOpenCodeLastUserMessage() {
    let pluginSession = SessionSnapshot(
        id: "plugin-opencode-25022",
        tool: .opencode,
        pid: 25022,
        status: .running,
        source: .plugin,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_120),
        cwd: "/Users/yelog/workspace/swift/VibeBar",
        command: ["opencode"],
        title: "分析当前默认主题",
        currentTask: "处理中",
        lastUserMessage: "要",
        runningSummary: "处理中"
    )

    let detectedSession = SessionSnapshot(
        id: "opencode-http-ses_abc",
        tool: .opencode,
        pid: 25022,
        status: .running,
        source: .processScan,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_090),
        cwd: "/Users/yelog/workspace/swift/VibeBar",
        command: ["opencode"],
        title: "分析当前默认主题",
        currentTask: "处理中",
        lastUserMessage: "请结合代码分析当前 readme 的质量，有哪些缺失",
        runningSummary: "处理中"
    )

    let merged = MonitorViewModel.mergeDetectedDetails(
        into: pluginSession,
        from: detectedSession
    )

    #expect(merged.lastUserMessage == "请结合代码分析当前 readme 的质量，有哪些缺失")
}

@Test func mergeDetectedDetailsClearsStaleOpenCodeWaitingAfterDetectedProgress() {
    let requestedAt = Date(timeIntervalSince1970: 1_700_000_100)
    let pluginSession = SessionSnapshot(
        id: "plugin-opencode-plugin-opencode-60803",
        tool: .opencode,
        pid: 60803,
        status: .awaitingInput,
        source: .plugin,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: requestedAt,
        statusSince: requestedAt,
        lastInputAt: requestedAt,
        cwd: "/Users/yelog/workspace/swift/calendar-pro",
        command: ["opencode"],
        currentTask: "序号计算范围",
        pendingInteractionID: "opencode-que_123"
    )

    let detectedSession = SessionSnapshot(
        id: "opencode-http-ses_abc",
        tool: .opencode,
        pid: 60803,
        status: .running,
        source: .sessionFile,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_160),
        statusSince: Date(timeIntervalSince1970: 1_700_000_160),
        cwd: "/Users/yelog/workspace/swift/calendar-pro",
        command: ["opencode"],
        runningSummary: "继续处理日程排序"
    )

    let merged = MonitorViewModel.mergeDetectedDetails(
        into: pluginSession,
        from: detectedSession
    )
    let interaction = PendingInteraction(
        id: "opencode-que_123",
        sessionID: pluginSession.id,
        tool: .opencode,
        kind: .question,
        message: "请选择范围",
        requestedAt: requestedAt,
        transportContext: ["source": "opencode-plugin"]
    )
    let activeInteractions = MonitorViewModel.activeInteractionsBySession(
        [pluginSession.id: interaction],
        sessions: [merged]
    )

    #expect(merged.status == .running)
    #expect(merged.pendingInteractionID == nil)
    #expect(activeInteractions.isEmpty)
}

@Test func mergeDetectedDetailsKeepsRecentOpenCodeWaitingWithoutDetectedProgress() {
    let requestedAt = Date(timeIntervalSince1970: 1_700_000_100)
    let pluginSession = SessionSnapshot(
        id: "plugin-opencode-plugin-opencode-60803",
        tool: .opencode,
        pid: 60803,
        status: .awaitingInput,
        source: .plugin,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: requestedAt,
        statusSince: requestedAt,
        lastInputAt: requestedAt,
        cwd: "/Users/yelog/workspace/swift/calendar-pro",
        command: ["opencode"],
        currentTask: "序号计算范围",
        pendingInteractionID: "opencode-que_123"
    )

    let detectedSession = SessionSnapshot(
        id: "opencode-http-ses_abc",
        tool: .opencode,
        pid: 60803,
        status: .running,
        source: .sessionFile,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_101),
        statusSince: Date(timeIntervalSince1970: 1_700_000_101),
        cwd: "/Users/yelog/workspace/swift/calendar-pro",
        command: ["opencode"]
    )

    let merged = MonitorViewModel.mergeDetectedDetails(
        into: pluginSession,
        from: detectedSession
    )

    #expect(merged.status == .awaitingInput)
    #expect(merged.pendingInteractionID == "opencode-que_123")
}

@Test func mergeDetectedDetailsPrefersExplicitSessionNameOverDerivedName() {
    let pluginSession = SessionSnapshot(
        id: "plugin-codex-60558",
        tool: .codex,
        pid: 60558,
        status: .running,
        source: .plugin,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_120),
        cwd: "/Users/yelog/workspace/rust/rust-redis-desktop",
        command: ["codex"],
        title: "修复 Session 列表第一行展示",
        titleSource: .derived,
        currentTask: "现在开始实现"
    )

    let detectedSession = SessionSnapshot(
        id: "codex-session-019d5bd2",
        tool: .codex,
        pid: 60558,
        status: .idle,
        source: .sessionFile,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_150),
        cwd: "/Users/yelog/workspace/rust/rust-redis-desktop",
        command: ["codex"],
        title: "显示各 Agent Client 的 Session 名称",
        titleSource: .explicit,
        currentTask: "等待验证"
    )

    let merged = MonitorViewModel.mergeDetectedDetails(
        into: pluginSession,
        from: detectedSession
    )

    #expect(merged.title == "显示各 Agent Client 的 Session 名称")
    #expect(merged.titleSource == .explicit)
    #expect(merged.status == .running)
}

@Test func mergeDetectedDetailsReplacesLowSignalCodexTaskAndSummary() {
    let pluginSession = SessionSnapshot(
        id: "plugin-codex-hook-019d9906-3752-7860-b1ca-26d51a9fae99",
        tool: .codex,
        pid: 0,
        status: .running,
        source: .plugin,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_120),
        cwd: "/Users/yelog/workspace/swift/VibeBar",
        command: ["codex"],
        title: "请仔细分析一下",
        titleSource: .derived,
        currentTask: "Bash",
        runningSummary: "Bash"
    )

    let detectedSession = SessionSnapshot(
        id: "codex-session-019d9906-3752-7860-b1ca-26d51a9fae99",
        tool: .codex,
        pid: 97103,
        status: .running,
        source: .sessionFile,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_150),
        cwd: "/Users/yelog/workspace/swift/VibeBar",
        command: ["codex"],
        title: "排查 CodeX Session Name 误识别",
        titleSource: .explicit,
        currentTask: "请分析一下：为什么在 CodeX 中新建的 Session 会显示为 bash？",
        lastUserMessage: "请分析一下：为什么在 CodeX 中新建的 Session 会显示为 bash？"
    )

    let merged = MonitorViewModel.mergeDetectedDetails(
        into: pluginSession,
        from: detectedSession
    )

    #expect(merged.title == "排查 CodeX Session Name 误识别")
    #expect(merged.currentTask == "请分析一下：为什么在 CodeX 中新建的 Session 会显示为 bash？")
    #expect(merged.runningSummary == nil)
}

@Test func mergeDetectedDetailsBackfillsIdleSinceOnlyForIdleSessions() {
    let pluginSession = SessionSnapshot(
        id: "plugin-codex-60558",
        tool: .codex,
        pid: 60558,
        status: .idle,
        source: .plugin,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_120),
        cwd: "/tmp/project",
        command: ["codex"]
    )

    let detectedIdleSession = SessionSnapshot(
        id: "codex-session-019d5bd2",
        tool: .codex,
        pid: 60558,
        status: .idle,
        source: .sessionFile,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_090),
        idleSince: Date(timeIntervalSince1970: 1_700_000_060),
        cwd: "/tmp/project",
        command: ["codex"]
    )

    let mergedIdle = MonitorViewModel.mergeDetectedDetails(
        into: pluginSession,
        from: detectedIdleSession
    )

    #expect(mergedIdle.status == .idle)
    #expect(mergedIdle.idleSince == Date(timeIntervalSince1970: 1_700_000_060))

    let runningPluginSession = SessionSnapshot(
        id: "plugin-codex-60558",
        tool: .codex,
        pid: 60558,
        status: .running,
        source: .plugin,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_120),
        idleSince: Date(timeIntervalSince1970: 1_700_000_050),
        cwd: "/tmp/project",
        command: ["codex"]
    )

    let mergedRunning = MonitorViewModel.mergeDetectedDetails(
        into: runningPluginSession,
        from: detectedIdleSession
    )

    #expect(mergedRunning.status == .running)
    #expect(mergedRunning.idleSince == nil)
}

@Test func mergeDetectedDetailsBackfillsStatusSinceForMatchingStatus() {
    let pluginSession = SessionSnapshot(
        id: "plugin-codex-60558",
        tool: .codex,
        pid: 60558,
        status: .idle,
        source: .plugin,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_120),
        cwd: "/tmp/project",
        command: ["codex"]
    )

    let detectedIdleSession = SessionSnapshot(
        id: "codex-session-019d5bd2",
        tool: .codex,
        pid: 60558,
        status: .idle,
        source: .sessionFile,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_090),
        statusSince: Date(timeIntervalSince1970: 1_700_000_060),
        idleSince: Date(timeIntervalSince1970: 1_700_000_060),
        cwd: "/tmp/project",
        command: ["codex"]
    )

    let merged = MonitorViewModel.mergeDetectedDetails(
        into: pluginSession,
        from: detectedIdleSession
    )

    #expect(merged.status == .idle)
    #expect(merged.statusSince == Date(timeIntervalSince1970: 1_700_000_060))
}

@Test func mergeDetectedDetailsKeepsPluginRunningStatusSinceOverSessionFileActivityAnchor() {
    let pluginSession = SessionSnapshot(
        id: "plugin-codex-60558",
        tool: .codex,
        pid: 60558,
        status: .running,
        source: .plugin,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_120),
        statusSince: Date(timeIntervalSince1970: 1_700_000_000),
        cwd: "/tmp/project",
        command: ["codex"]
    )

    let detectedRunningSession = SessionSnapshot(
        id: "codex-session-019d5bd2",
        tool: .codex,
        pid: 60558,
        status: .running,
        source: .sessionFile,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_110),
        statusSince: Date(timeIntervalSince1970: 1_700_000_090),
        cwd: "/tmp/project",
        command: ["codex"]
    )

    let merged = MonitorViewModel.mergeDetectedDetails(
        into: pluginSession,
        from: detectedRunningSession
    )

    #expect(merged.status == .running)
    #expect(merged.statusSince == Date(timeIntervalSince1970: 1_700_000_000))
}

@Test func mergeDetectedDetailsDoesNotOverrideNonCodexStatusSince() {
    let pluginSession = SessionSnapshot(
        id: "plugin-opencode-25022",
        tool: .opencode,
        pid: 25022,
        status: .running,
        source: .plugin,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_120),
        statusSince: Date(timeIntervalSince1970: 1_700_000_080),
        cwd: "/tmp/project",
        command: ["opencode"]
    )

    let detectedRunningSession = SessionSnapshot(
        id: "opencode-http-ses_abc",
        tool: .opencode,
        pid: 25022,
        status: .running,
        source: .processScan,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_110),
        statusSince: Date(timeIntervalSince1970: 1_700_000_090),
        cwd: "/tmp/project",
        command: ["opencode"]
    )

    let merged = MonitorViewModel.mergeDetectedDetails(
        into: pluginSession,
        from: detectedRunningSession
    )

    #expect(merged.status == .running)
    #expect(merged.statusSince == Date(timeIntervalSince1970: 1_700_000_080))
}

@Test func mergeDetectedDetailsKeepsClaudePluginStatusAnchorsWhileBackfillingTranscriptMetadata() {
    let pluginSession = SessionSnapshot(
        id: "plugin-claude-code-session-42",
        tool: .claudeCode,
        pid: 42,
        status: .idle,
        source: .plugin,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_120),
        statusSince: Date(timeIntervalSince1970: 1_700_000_120),
        cwd: "/tmp/project",
        command: ["claude"]
    )

    let detectedSession = SessionSnapshot(
        id: "claude-transcript-42",
        tool: .claudeCode,
        pid: 42,
        parentPID: 7,
        status: .idle,
        source: .transcriptFile,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_090),
        statusSince: Date(timeIntervalSince1970: 1_700_000_060),
        idleSince: Date(timeIntervalSince1970: 1_700_000_060),
        lastOutputAt: Date(timeIntervalSince1970: 1_700_000_060),
        lastInputAt: Date(timeIntervalSince1970: 1_700_000_050),
        cwd: "/tmp/project",
        command: ["claude"],
        title: "修复 Claude 状态抖动",
        titleSource: .explicit,
        currentTask: "重试中",
        lastUserMessage: "请分析为什么状态会抖动",
        runningSummary: "2s 后重试",
        terminalContext: TerminalContext(
            clientKind: .kitty,
            bundleIdentifier: "net.kovidgoyal.kitty",
            tty: "ttys009",
            sessionManagerKind: .none,
            origin: .cli
        )
    )

    let merged = MonitorViewModel.mergeDetectedDetails(
        into: pluginSession,
        from: detectedSession
    )

    #expect(merged.status == .idle)
    #expect(merged.statusSince == Date(timeIntervalSince1970: 1_700_000_120))
    #expect(merged.idleSince == nil)
    #expect(merged.lastOutputAt == nil)
    #expect(merged.lastInputAt == nil)
    #expect(merged.title == "修复 Claude 状态抖动")
    #expect(merged.lastUserMessage == "请分析为什么状态会抖动")
    #expect(merged.runningSummary == "2s 后重试")
    #expect(merged.terminalContext?.clientKind == .kitty)
}

@Test func semanticRefreshResultIgnoresExecutionTimeInUpdatedAt() {
    let base = makeSemanticSession(id: "a")
    var refreshed = base
    refreshed.updatedAt = base.updatedAt.addingTimeInterval(60)

    #expect(MonitorViewModel.sessionsAreSemanticallyEqual([base], [refreshed]))
}

@Test func semanticRefreshResultDetectsSessionCountChange() {
    let base = makeSemanticSession(id: "a")
    #expect(MonitorViewModel.sessionsAreSemanticallyEqual([base], []) == false)
}

@Test func semanticRefreshResultDetectsStatusChange() {
    let base = makeSemanticSession(id: "a", status: .running)
    var changed = base
    changed.status = .idle
    #expect(MonitorViewModel.sessionsAreSemanticallyEqual([base], [changed]) == false)
}

@Test func semanticRefreshResultDetectsTitleChange() {
    let base = makeSemanticSession(id: "a")
    var changed = base
    changed.title = "新标题"
    #expect(MonitorViewModel.sessionsAreSemanticallyEqual([base], [changed]) == false)
}

@Test func semanticRefreshResultDetectsTaskChange() {
    let base = makeSemanticSession(id: "a")
    var changed = base
    changed.currentTask = "新任务"
    #expect(MonitorViewModel.sessionsAreSemanticallyEqual([base], [changed]) == false)
}

@Test func semanticRefreshResultDetectsTerminalContextChange() {
    let base = makeSemanticSession(id: "a")
    var changed = base
    changed.terminalContext = TerminalContext(
        clientKind: .kitty,
        bundleIdentifier: "net.kovidgoyal.kitty",
        tty: "ttys001",
        sessionManagerKind: .none,
        origin: .cli
    )
    #expect(MonitorViewModel.sessionsAreSemanticallyEqual([base], [changed]) == false)
}

@Test func semanticRefreshResultKeepsDurationTimestampsMeaningful() {
    let base = makeSemanticSession(id: "a")
    var changedStarted = base
    changedStarted.startedAt = base.startedAt.addingTimeInterval(120)
    #expect(MonitorViewModel.sessionsAreSemanticallyEqual([base], [changedStarted]) == false)

    var changedIdleSince = base
    changedIdleSince.idleSince = base.idleSince?.addingTimeInterval(60)
    #expect(MonitorViewModel.sessionsAreSemanticallyEqual([base], [changedIdleSince]) == false)
}

@Test func semanticRefreshResultDetectsInteractionChange() {
    let lhs: [String: PendingInteraction] = [
        "s1": PendingInteraction(
            id: "q1",
            sessionID: "s1",
            tool: .opencode,
            kind: .question,
            message: "选择",
            requestedAt: Date(timeIntervalSince1970: 1_700_000_000)
        ),
    ]
    let rhs: [String: PendingInteraction] = [
        "s1": PendingInteraction(
            id: "q2",
            sessionID: "s1",
            tool: .opencode,
            kind: .question,
            message: "选择",
            requestedAt: Date(timeIntervalSince1970: 1_700_000_000)
        ),
    ]
    #expect(MonitorViewModel.interactionsAreSemanticallyEqual(lhs, rhs) == false)
    #expect(MonitorViewModel.interactionsAreSemanticallyEqual(lhs, lhs))
}

@Test func semanticRefreshResultSummaryIgnoresUpdatedAtButDetectsContentChange() {
    let lhs = GlobalSummary(
        total: 1,
        counts: [.running: 1],
        byTool: [.opencode: ToolSummary(tool: .opencode, total: 1, counts: [.running: 1], overall: .running)],
        updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    var rhs = lhs
    rhs.updatedAt = Date(timeIntervalSince1970: 1_700_000_060)
    #expect(MonitorViewModel.summaryIsSemanticallyEqual(lhs, rhs))

    var changedTotal = rhs
    changedTotal.total = 2
    #expect(MonitorViewModel.summaryIsSemanticallyEqual(lhs, changedTotal) == false)
}

private func makeSemanticSession(id: String, status: ToolActivityState = .running) -> SessionSnapshot {
    SessionSnapshot(
        id: id,
        tool: .opencode,
        pid: 100,
        status: status,
        source: .plugin,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
        idleSince: Date(timeIntervalSince1970: 1_700_000_050),
        cwd: "/tmp/project",
        command: ["opencode"],
        title: "标题",
        currentTask: "任务"
    )
}

@Test func mergeCorrelatesPiPluginSessionWithProcessScanByPID() {
    let livePID = ProcessInfo.processInfo.processIdentifier
    let now = Date(timeIntervalSince1970: 1_700_000_150)

    let pluginSession = SessionSnapshot(
        id: "plugin-pi-extension-abc123",
        tool: .pi,
        pid: livePID,
        status: .running,
        source: .plugin,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_120),
        cwd: "/work/project",
        command: ["pi"],
        title: "Refactor auth",
        titleSource: .derived,
        lastUserMessage: "fix login",
        runningSummary: "editing auth.swift"
    )

    let processSession = SessionSnapshot(
        id: "ps-\(livePID)",
        tool: .pi,
        pid: livePID,
        status: .running,
        source: .processScan,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
        cwd: "/work/project",
        command: ["pi"],
        notes: "cpu=3.0%",
        terminalContext: TerminalContext(
            clientKind: .kitty,
            bundleIdentifier: "net.kovidgoyal.kitty",
            tty: "ttys012",
            sessionManagerKind: .none,
            origin: .cli
        )
    )

    let merged = MonitorViewModel.merge(
        fileSessions: [pluginSession],
        processSessions: [processSession],
        now: now,
        store: SessionFileStore()
    )

    #expect(merged.count == 1)
    #expect(merged[0].id == pluginSession.id)
    #expect(merged[0].title == "Refactor auth")
    #expect(merged[0].lastUserMessage == "fix login")
    #expect(merged[0].runningSummary == "editing auth.swift")
    #expect(merged[0].status == .running)
    #expect(merged[0].terminalContext?.clientKind == .kitty)
}

@Test func mergeCorrelatesPiSessionByStableIDAcrossPIDChange() {
    let now = Date(timeIntervalSince1970: 1_700_000_150)

    let pluginSession = SessionSnapshot(
        id: "plugin-pi-extension-2d2a1c90-a1b2-4c3d-8e4f-5a6b7c8d9e0f",
        tool: .pi,
        pid: 0,
        status: .running,
        source: .plugin,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_120),
        cwd: "/work/project",
        command: ["pi"],
        title: "Continue refactor",
        titleSource: .derived
    )

    let processSession = SessionSnapshot(
        id: "ps-6002",
        tool: .pi,
        pid: 6002,
        status: .running,
        source: .processScan,
        startedAt: Date(timeIntervalSince1970: 1_700_000_100),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_140),
        cwd: "/work/project",
        command: ["pi", "2d2a1c90-a1b2-4c3d-8e4f-5a6b7c8d9e0f"],
        notes: "cpu=1.5%"
    )

    let merged = MonitorViewModel.merge(
        fileSessions: [pluginSession],
        processSessions: [processSession],
        now: now,
        store: SessionFileStore()
    )

    #expect(merged.count == 1)
    #expect(merged[0].id == pluginSession.id)
    #expect(merged[0].pid == 6002)
}

@Test func mergeKeepsEqualRawPiAndOmpSessionIDsSeparate() {
    let now = Date(timeIntervalSince1970: 1_700_000_150)
    let rawSessionID = "9f8e7d6c-5b4a-4a3b-2c1d-1e2f3a4b5c6d"

    let piPluginSession = SessionSnapshot(
        id: "plugin-pi-extension-\(rawSessionID)",
        tool: .pi,
        pid: 0,
        status: .running,
        source: .plugin,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_120),
        command: ["pi"]
    )

    let ompPluginSession = SessionSnapshot(
        id: "plugin-oh-my-pi-extension-\(rawSessionID)",
        tool: .ohMyPi,
        pid: 0,
        status: .running,
        source: .plugin,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_120),
        command: ["omp"]
    )

    let piProcessSession = SessionSnapshot(
        id: "ps-7001",
        tool: .pi,
        pid: 7001,
        status: .running,
        source: .processScan,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
        command: ["pi", rawSessionID]
    )

    let merged = MonitorViewModel.merge(
        fileSessions: [piPluginSession, ompPluginSession],
        processSessions: [piProcessSession],
        now: now,
        store: SessionFileStore()
    )

    #expect(merged.count == 2)
    let tools = Set(merged.map(\.tool))
    #expect(tools == [.pi, .ohMyPi])
    let piMerged = merged.first { $0.tool == .pi }
    #expect(piMerged?.id == piPluginSession.id)
    #expect(piMerged?.pid == 7001)
}

@Test func mergeKeepsUnrelatedPiSessionsWithoutSafeCorrelationSeparate() {
    let now = Date(timeIntervalSince1970: 1_700_000_150)

    let pluginSession = SessionSnapshot(
        id: "plugin-pi-extension-11111111-2222-3333-4444-555555555555",
        tool: .pi,
        pid: 0,
        status: .running,
        source: .plugin,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_120),
        command: ["pi"],
        title: "Uncorrelated",
        titleSource: .derived
    )

    let processSession = SessionSnapshot(
        id: "ps-8003",
        tool: .pi,
        pid: 8003,
        status: .running,
        source: .processScan,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
        command: ["pi"],
        notes: "cpu=0.8%"
    )

    let merged = MonitorViewModel.merge(
        fileSessions: [pluginSession],
        processSessions: [processSession],
        now: now,
        store: SessionFileStore()
    )

    #expect(merged.count == 2)
}

@Test func mergePrefersOmpPluginMetadataOverProcessHeuristics() {
    let now = Date(timeIntervalSince1970: 1_700_000_150)
    let rawSessionID = "a1b2c3d4-e5f6-4a5b-8c9d-0e1f2a3b4c5d"

    let pluginSession = SessionSnapshot(
        id: "plugin-oh-my-pi-extension-\(rawSessionID)",
        tool: .ohMyPi,
        pid: 0,
        status: .idle,
        source: .plugin,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_120),
        cwd: "/work/project",
        command: ["omp"],
        title: "Fix CI",
        titleSource: .explicit,
        lastUserMessage: "fix the pipeline",
        runningSummary: "updated workflow"
    )

    let processSession = SessionSnapshot(
        id: "ps-9001",
        tool: .ohMyPi,
        pid: 9001,
        status: .running,
        source: .processScan,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_140),
        cwd: "/work/project",
        command: ["omp", rawSessionID],
        notes: "cpu=5.0%"
    )

    let merged = MonitorViewModel.merge(
        fileSessions: [pluginSession],
        processSessions: [processSession],
        now: now,
        store: SessionFileStore()
    )

    #expect(merged.count == 1)
    #expect(merged[0].status == .idle)
    #expect(merged[0].title == "Fix CI")
    #expect(merged[0].lastUserMessage == "fix the pipeline")
    #expect(merged[0].runningSummary == "updated workflow")
    #expect(merged[0].updatedAt == pluginSession.updatedAt)
    #expect(merged[0].pid == 9001)
}

@Test func mergeCorrectsStaleOpenCodePluginRunningWithNewerDetectedIdle() {
    let now = Date(timeIntervalSince1970: 1_700_000_500)
    let pid = getpid()

    let pluginSession = SessionSnapshot(
        id: "plugin-opencode-plugin-opencode-\(pid)",
        tool: .opencode,
        pid: pid,
        status: .running,
        source: .plugin,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_440),
        cwd: "/Users/yelog/workspace/lenovo/opencode/moss-base",
        command: ["opencode"],
        title: "邮件管理模板 list 循环支持分析",
        titleSource: .explicit,
        currentTask: "apply_patch",
        lastUserMessage: "按照你的建议，列出实施计划并实施",
        runningSummary: "apply_patch"
    )

    let detectedSession = SessionSnapshot(
        id: "opencode-http-ses_010372e74ffe2yV4YAUt27Hu6c",
        tool: .opencode,
        pid: pid,
        status: .idle,
        source: .sessionFile,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_490),
        statusSince: Date(timeIntervalSince1970: 1_700_000_460),
        idleSince: Date(timeIntervalSince1970: 1_700_000_460),
        cwd: "/Users/yelog/workspace/lenovo/opencode/moss-base",
        command: ["opencode"]
    )

    let merged = MonitorViewModel.merge(
        fileSessions: [pluginSession],
        processSessions: [detectedSession],
        now: now,
        store: SessionFileStore()
    )

    #expect(merged.count == 1)
    #expect(merged[0].status == .idle)
    #expect(merged[0].statusSince == Date(timeIntervalSince1970: 1_700_000_460))
    #expect(merged[0].idleSince == Date(timeIntervalSince1970: 1_700_000_460))
    #expect(merged[0].title == "邮件管理模板 list 循环支持分析")
    #expect(merged[0].currentTask == "apply_patch")
    #expect(merged[0].runningSummary == "apply_patch")
}

@Test func mergeKeepsFreshOpenCodePluginRunningDespiteDetectedIdle() {
    let now = Date(timeIntervalSince1970: 1_700_000_500)
    let pid = getpid()

    let pluginSession = SessionSnapshot(
        id: "plugin-opencode-plugin-opencode-\(pid)",
        tool: .opencode,
        pid: pid,
        status: .running,
        source: .plugin,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_490),
        cwd: "/work/project",
        command: ["opencode"]
    )

    let detectedSession = SessionSnapshot(
        id: "opencode-http-ses_x",
        tool: .opencode,
        pid: pid,
        status: .idle,
        source: .sessionFile,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_480),
        statusSince: Date(timeIntervalSince1970: 1_700_000_460),
        idleSince: Date(timeIntervalSince1970: 1_700_000_460),
        cwd: "/work/project",
        command: ["opencode"]
    )

    let merged = MonitorViewModel.merge(
        fileSessions: [pluginSession],
        processSessions: [detectedSession],
        now: now,
        store: SessionFileStore()
    )

    #expect(merged.count == 1)
    #expect(merged[0].status == .running)
}

@Test func mergeKeepsStaleOpenCodePluginRunningWhenDetectedEvidenceIsOlder() {
    let now = Date(timeIntervalSince1970: 1_700_000_500)
    let pid = getpid()

    let pluginSession = SessionSnapshot(
        id: "plugin-opencode-plugin-opencode-\(pid)",
        tool: .opencode,
        pid: pid,
        status: .running,
        source: .plugin,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_440),
        cwd: "/work/project",
        command: ["opencode"]
    )

    let detectedSession = SessionSnapshot(
        id: "opencode-http-ses_x",
        tool: .opencode,
        pid: pid,
        status: .idle,
        source: .sessionFile,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_430),
        statusSince: Date(timeIntervalSince1970: 1_700_000_420),
        idleSince: Date(timeIntervalSince1970: 1_700_000_420),
        cwd: "/work/project",
        command: ["opencode"]
    )

    let merged = MonitorViewModel.merge(
        fileSessions: [pluginSession],
        processSessions: [detectedSession],
        now: now,
        store: SessionFileStore()
    )

    #expect(merged.count == 1)
    #expect(merged[0].status == .running)
}

@Test func mergeDoesNotCorrectStaleClaudePluginRunningWithDetectedIdle() {
    let now = Date(timeIntervalSince1970: 1_700_000_500)
    let pid = getpid()

    let pluginSession = SessionSnapshot(
        id: "plugin-claude-\(pid)",
        tool: .claudeCode,
        pid: pid,
        status: .running,
        source: .plugin,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_440),
        cwd: "/work/project",
        command: ["claude"]
    )

    let detectedSession = SessionSnapshot(
        id: "claude-session-x",
        tool: .claudeCode,
        pid: pid,
        status: .idle,
        source: .sessionFile,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_490),
        cwd: "/work/project",
        command: ["claude"]
    )

    let merged = MonitorViewModel.merge(
        fileSessions: [pluginSession],
        processSessions: [detectedSession],
        now: now,
        store: SessionFileStore()
    )

    #expect(merged.count == 1)
    #expect(merged[0].status == .running)
}

@Test func mergeDoesNotCorrectOpenCodeAwaitingInputWithDetectedIdle() {
    let now = Date(timeIntervalSince1970: 1_700_000_500)
    let pid = getpid()

    let pluginSession = SessionSnapshot(
        id: "plugin-opencode-plugin-opencode-\(pid)",
        tool: .opencode,
        pid: pid,
        status: .awaitingInput,
        source: .plugin,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_450),
        statusSince: Date(timeIntervalSince1970: 1_700_000_450),
        lastInputAt: Date(timeIntervalSince1970: 1_700_000_450),
        cwd: "/work/project",
        command: ["opencode"],
        pendingInteractionID: "opencode-que_test"
    )

    let detectedSession = SessionSnapshot(
        id: "opencode-http-ses_x",
        tool: .opencode,
        pid: pid,
        status: .idle,
        source: .sessionFile,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_451),
        statusSince: Date(timeIntervalSince1970: 1_700_000_451),
        idleSince: Date(timeIntervalSince1970: 1_700_000_451),
        cwd: "/work/project",
        command: ["opencode"]
    )

    let merged = MonitorViewModel.merge(
        fileSessions: [pluginSession],
        processSessions: [detectedSession],
        now: now,
        store: SessionFileStore()
    )

    #expect(merged.count == 1)
    #expect(merged[0].status == .awaitingInput)
}
