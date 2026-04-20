import Foundation
import Testing
import VibeBarCore
@testable import VibeBarApp

@MainActor
@Test func compactDetailLinesSeparateLastUserMessageAndRunningTask() {
    let session = makeSession(
        title: "修复 Codex session 名称",
        lastUserMessage: "提交代码",
        runningSummary: "整理 commit message",
        cwd: "/tmp/vibebar"
    )

    let lines = SessionCompactDetailLineBuilder.build(
        for: session,
        context: .flat,
        maxDirectoryLength: 70
    )

    #expect(lines.row2?.text == "提交代码")
    #expect(lines.row2?.prefix == .userInput)
    #expect(lines.row2?.tone == .secondary)
    #expect(lines.row3?.text == "整理 commit message")
    #expect(lines.row3?.prefix == .runningTask)
    #expect(lines.row3?.tone == .tertiary)
}

@MainActor
@Test func compactDetailLinesPromoteRunningTaskWhenUserMessageIsMissing() {
    let session = makeSession(
        title: "修复 Codex session 名称",
        runningSummary: "正在读取 session_index",
        cwd: "/tmp/vibebar"
    )

    let lines = SessionCompactDetailLineBuilder.build(
        for: session,
        context: .flat,
        maxDirectoryLength: 70
    )

    #expect(lines.row2?.text == "正在读取 session_index")
    #expect(lines.row2?.prefix == .runningTask)
    #expect(lines.row2?.tone == .secondary)
    #expect(lines.row3?.text == "/tmp/vibebar")
    #expect(lines.row3?.prefix == nil)
    #expect(lines.row3?.tone == .tertiary)
}

@MainActor
@Test func compactDetailLinesKeepDirectoryPlainWhenRunningTaskIsMissing() {
    let session = makeSession(
        title: "修复 Codex session 名称",
        lastUserMessage: "提交代码",
        runningSummary: nil,
        cwd: "/tmp/vibebar"
    )

    let lines = SessionCompactDetailLineBuilder.build(
        for: session,
        context: .flat,
        maxDirectoryLength: 70
    )

    #expect(lines.row2?.text == "提交代码")
    #expect(lines.row2?.prefix == .userInput)
    #expect(lines.row3?.text == "/tmp/vibebar")
    #expect(lines.row3?.prefix == nil)
    #expect(lines.row3?.tone == .tertiary)
}

@MainActor
@Test func compactDetailLinesSuppressDuplicateCurrentTaskWhenItMatchesUserMessage() {
    let session = makeSession(
        tool: .claudeCode,
        title: "测试重命名",
        currentTask: "hello",
        lastUserMessage: "hello",
        runningSummary: nil,
        cwd: "/tmp/vibebar"
    )

    let lines = SessionCompactDetailLineBuilder.build(
        for: session,
        context: .flat,
        maxDirectoryLength: 70
    )

    #expect(lines.row2?.text == "hello")
    #expect(lines.row2?.prefix == .userInput)
    #expect(lines.row3?.text == "/tmp/vibebar")
    #expect(lines.row3?.prefix == nil)
    #expect(lines.row3?.tone == .tertiary)
}

private func makeSession(
    pid: Int32 = 123,
    tool: ToolKind = .codex,
    status: ToolActivityState = .running,
    title: String? = nil,
    currentTask: String? = nil,
    lastUserMessage: String? = nil,
    runningSummary: String? = nil,
    cwd: String? = "/tmp/project"
) -> SessionSnapshot {
    SessionSnapshot(
        id: "codex-session",
        tool: tool,
        pid: pid,
        status: status,
        source: .sessionFile,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_030),
        cwd: cwd,
        command: [tool.executable],
        title: title,
        currentTask: currentTask,
        lastUserMessage: lastUserMessage,
        runningSummary: runningSummary
    )
}
