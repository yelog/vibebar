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

@Test func mergeDetectedDetailsPrefersNewerCodexStatusSinceFromDetector() {
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
    #expect(merged.statusSince == Date(timeIntervalSince1970: 1_700_000_090))
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
