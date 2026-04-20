import Foundation
import SQLite3
import Testing
@testable import VibeBarCore

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

@Test func codexSessionDetectorParsesRecentSessionIndexAndRollout() async throws {
    let fixture = try makeCodexFixture()
    defer { try? FileManager.default.removeItem(at: fixture.baseURL) }

    let sessionID = "019d5000-1111-7111-8111-111111111111"
    try fixture.writeSessionIndex(
        """
        {"id":"\(sessionID)","thread_name":"修复 Codex 状态识别","updated_at":"2026-04-04T12:00:04Z"}
        """
    )
    try fixture.writeRollout(
        id: sessionID,
        content: """
        {"timestamp":"2026-04-04T12:00:00Z","type":"session_meta","payload":{"id":"\(sessionID)","timestamp":"2026-04-04T12:00:00Z","cwd":"/tmp/project","originator":"codex_cli_rs","source":"cli"}}
        {"timestamp":"2026-04-04T12:00:01Z","type":"event_msg","payload":{"type":"user_message","message":"修复状态检测"}}
        {"timestamp":"2026-04-04T12:00:02Z","type":"event_msg","payload":{"type":"agent_reasoning","text":"Inspecting files"}}
        {"timestamp":"2026-04-04T12:00:03Z","type":"response_item","payload":{"type":"function_call","name":"shell_command","arguments":"{\\"command\\":\\"pwd\\"}"}}
        """
    )

    let detector = CodexSessionDetector(baseDirectory: fixture.baseURL)
    let now = try #require(DetectorSupport.parseISO8601("2026-04-04T12:00:05Z"))
    let sessions = await detector.detectSessions(
        context: DetectorSupport.DetectionContext(processes: []),
        now: now
    )

    #expect(sessions.count == 1)
    #expect(sessions[0].id == "codex-session-\(sessionID)")
    #expect(sessions[0].title == "修复 Codex 状态识别")
    #expect(sessions[0].currentTask == "修复状态检测")
    #expect(sessions[0].cwd == "/tmp/project")
    #expect(sessions[0].status == .running)
    #expect(sessions[0].source == .sessionFile)
}

@Test func codexSessionDetectorKeepsUnnamedSessionWhenNoExplicitThreadName() async throws {
    let fixture = try makeCodexFixture()
    defer { try? FileManager.default.removeItem(at: fixture.baseURL) }

    let sessionID = "019d5000-1111-7111-8111-999999999999"
    try fixture.writeSessionIndex(
        """
        {"id":"\(sessionID)","updated_at":"2026-04-04T12:00:04Z"}
        """
    )
    try fixture.writeRollout(
        id: sessionID,
        content: """
        {"timestamp":"2026-04-04T12:00:00Z","type":"session_meta","payload":{"id":"\(sessionID)","timestamp":"2026-04-04T12:00:00Z","cwd":"/tmp/project","originator":"codex_cli_rs","source":"cli"}}
        {"timestamp":"2026-04-04T12:00:01Z","type":"event_msg","payload":{"type":"user_message","message":"先分析当前 session 列表命名问题"}}
        {"timestamp":"2026-04-04T12:00:02Z","type":"event_msg","payload":{"type":"agent_reasoning","text":"Inspecting files"}}
        {"timestamp":"2026-04-04T12:00:03Z","type":"event_msg","payload":{"type":"user_message","message":"顺便把 UI 的 pid 去掉"}}
        """
    )

    let detector = CodexSessionDetector(baseDirectory: fixture.baseURL)
    let now = try #require(DetectorSupport.parseISO8601("2026-04-04T12:00:05Z"))
    let sessions = await detector.detectSessions(
        context: DetectorSupport.DetectionContext(processes: []),
        now: now
    )

    let session = try #require(sessions.first)
    #expect(session.title == nil)
    #expect(session.titleSource == nil)
    #expect(session.currentTask == "顺便把 UI 的 pid 去掉")
    #expect(session.lastUserMessage == "顺便把 UI 的 pid 去掉")
}

@Test func codexSessionDetectorFallsBackToSQLiteTitleWhenSessionIndexOmitsThreadName() async throws {
    let fixture = try makeCodexFixture()
    defer { try? FileManager.default.removeItem(at: fixture.baseURL) }

    let sessionID = "019d5000-1111-7111-8111-121212121212"
    try fixture.writeSessionIndex(
        """
        {"id":"\(sessionID)","updated_at":"2026-04-04T12:00:04Z"}
        """
    )
    let rolloutURL = try fixture.writeRolloutReturningURL(
        id: sessionID,
        content: """
        {"timestamp":"2026-04-04T12:00:00Z","type":"session_meta","payload":{"id":"\(sessionID)","timestamp":"2026-04-04T12:00:00Z","cwd":"/tmp/project","originator":"Codex Desktop","source":"vscode"}}
        {"timestamp":"2026-04-04T12:00:03Z","type":"event_msg","payload":{"type":"agent_reasoning","text":"Inspecting files"}}
        """
    )
    try fixture.writeStateDatabase(
        sessionID: sessionID,
        rolloutPath: rolloutURL.path,
        title: "修复 Codex 会话标题显示",
        firstUserMessage: "请修复 Codex App session 标题",
        cwd: "/tmp/project",
        source: "vscode"
    )

    let detector = CodexSessionDetector(baseDirectory: fixture.baseURL)
    let now = try #require(DetectorSupport.parseISO8601("2026-04-04T12:00:05Z"))
    let sessions = await detector.detectSessions(
        context: DetectorSupport.DetectionContext(processes: []),
        now: now
    )

    let session = try #require(sessions.first)
    #expect(session.title == "修复 Codex 会话标题显示")
    #expect(session.titleSource == .explicit)
    #expect(session.currentTask == "请修复 Codex App session 标题")
    #expect(session.lastUserMessage == "请修复 Codex App session 标题")
}

@Test func codexSessionDetectorKeepsRunningDuringLongInFlightToolCall() async throws {
    let fixture = try makeCodexFixture()
    defer { try? FileManager.default.removeItem(at: fixture.baseURL) }

    let sessionID = "019d5000-eeee-7eee-8eee-eeeeeeeeeeee"
    let cwd = "/tmp/project"
    try fixture.writeSessionIndex(
        """
        {"id":"\(sessionID)","thread_name":"长命令执行中","updated_at":"2026-04-04T12:00:02Z"}
        """
    )
    try fixture.writeRollout(
        id: sessionID,
        content: """
        {"timestamp":"2026-04-04T12:00:00Z","type":"session_meta","payload":{"id":"\(sessionID)","timestamp":"2026-04-04T12:00:00Z","cwd":"\(cwd)","originator":"codex_cli_rs","source":"cli"}}
        {"timestamp":"2026-04-04T12:00:01Z","type":"event_msg","payload":{"type":"user_message","message":"执行长命令"}}
        {"timestamp":"2026-04-04T12:00:02Z","type":"response_item","payload":{"type":"function_call","name":"exec_command","call_id":"call-long-running","arguments":"{\\"cmd\\":\\"sleep 20\\"}"}}
        """
    )

    let detector = CodexSessionDetector(
        baseDirectory: fixture.baseURL,
        environmentProvider: { _ in [:] },
        cwdProvider: { _ in [4343: cwd] }
    )
    let now = try #require(DetectorSupport.parseISO8601("2026-04-04T12:00:20Z"))
    let sessions = await detector.detectSessions(
        context: DetectorSupport.DetectionContext(processes: [
            DetectorSupport.ProcEntry(
                pid: 4343,
                ppid: 1,
                tty: "ttys001",
                state: "S",
                cpu: 0,
                elapsedSeconds: 20,
                command: "codex",
                args: "codex"
            ),
        ]),
        now: now
    )

    let session = try #require(sessions.first)
    let runningSince = try #require(DetectorSupport.parseISO8601("2026-04-04T12:00:02Z"))
    #expect(session.status == .running)
    #expect(session.statusSince == runningSince)
}

@Test func codexSessionDetectorRecordsIdleSinceFromLatestActivity() async throws {
    let fixture = try makeCodexFixture()
    defer { try? FileManager.default.removeItem(at: fixture.baseURL) }

    let sessionID = "019d5000-aaaa-7aaa-8aaa-aaaaaaaaaaaa"
    let cwd = "/tmp/project"
    try fixture.writeSessionIndex(
        """
        {"id":"\(sessionID)","thread_name":"空闲会话","updated_at":"2026-04-04T12:00:02Z"}
        """
    )
    try fixture.writeRollout(
        id: sessionID,
        content: """
        {"timestamp":"2026-04-04T12:00:00Z","type":"session_meta","payload":{"id":"\(sessionID)","timestamp":"2026-04-04T12:00:00Z","cwd":"\(cwd)","originator":"codex_cli_rs","source":"cli"}}
        {"timestamp":"2026-04-04T12:00:01Z","type":"event_msg","payload":{"type":"user_message","message":"分析 idleSince 语义"}}
        {"timestamp":"2026-04-04T12:00:02Z","type":"event_msg","payload":{"type":"agent_reasoning","text":"Done"}}
        """
    )

    let detector = CodexSessionDetector(
        baseDirectory: fixture.baseURL,
        environmentProvider: { _ in [:] },
        cwdProvider: { _ in [4242: cwd] }
    )
    let now = try #require(DetectorSupport.parseISO8601("2026-04-04T12:00:20Z"))
    let sessions = await detector.detectSessions(
        context: DetectorSupport.DetectionContext(processes: [
            DetectorSupport.ProcEntry(
                pid: 4242,
                ppid: 1,
                tty: "ttys001",
                state: "S",
                cpu: 0,
                elapsedSeconds: 12,
                command: "codex",
                args: "codex"
            ),
        ]),
        now: now
    )

    let session = try #require(sessions.first)
    let idleSince = try #require(DetectorSupport.parseISO8601("2026-04-04T12:00:02Z"))
    #expect(session.status == .idle)
    #expect(session.idleSince == idleSince)
    #expect(session.statusSince == idleSince)
}

@Test func codexSessionDetectorReturnsIdleAfterToolCallCompletesAndWindowExpires() async throws {
    let fixture = try makeCodexFixture()
    defer { try? FileManager.default.removeItem(at: fixture.baseURL) }

    let sessionID = "019d5000-ffff-7fff-8fff-ffffffffffff"
    let cwd = "/tmp/project"
    try fixture.writeSessionIndex(
        """
        {"id":"\(sessionID)","thread_name":"长命令已结束","updated_at":"2026-04-04T12:00:02Z"}
        """
    )
    try fixture.writeRollout(
        id: sessionID,
        content: """
        {"timestamp":"2026-04-04T12:00:00Z","type":"session_meta","payload":{"id":"\(sessionID)","timestamp":"2026-04-04T12:00:00Z","cwd":"\(cwd)","originator":"codex_cli_rs","source":"cli"}}
        {"timestamp":"2026-04-04T12:00:01Z","type":"event_msg","payload":{"type":"user_message","message":"执行然后结束"}}
        {"timestamp":"2026-04-04T12:00:02Z","type":"response_item","payload":{"type":"function_call","name":"exec_command","call_id":"call-finished","arguments":"{\\"cmd\\":\\"echo done\\"}"}}
        {"timestamp":"2026-04-04T12:00:05Z","type":"event_msg","payload":{"type":"exec_command_end","call_id":"call-finished"}}
        """
    )

    let detector = CodexSessionDetector(
        baseDirectory: fixture.baseURL,
        environmentProvider: { _ in [:] },
        cwdProvider: { _ in [4545: cwd] }
    )
    let now = try #require(DetectorSupport.parseISO8601("2026-04-04T12:00:20Z"))
    let sessions = await detector.detectSessions(
        context: DetectorSupport.DetectionContext(processes: [
            DetectorSupport.ProcEntry(
                pid: 4545,
                ppid: 1,
                tty: "ttys001",
                state: "S",
                cpu: 0,
                elapsedSeconds: 20,
                command: "codex",
                args: "codex"
            ),
        ]),
        now: now
    )

    let session = try #require(sessions.first)
    let idleSince = try #require(DetectorSupport.parseISO8601("2026-04-04T12:00:05Z"))
    #expect(session.status == .idle)
    #expect(session.idleSince == idleSince)
    #expect(session.statusSince == idleSince)
}

@Test func codexSessionDetectorUsesCpuFallbackForBusyLiveProcess() async throws {
    let fixture = try makeCodexFixture()
    defer { try? FileManager.default.removeItem(at: fixture.baseURL) }

    let sessionID = "019d5000-abcd-7abc-8abc-abcdefabcdef"
    let cwd = "/tmp/project"
    try fixture.writeSessionIndex(
        """
        {"id":"\(sessionID)","thread_name":"CPU 兜底运行态","updated_at":"2026-04-04T12:00:02Z"}
        """
    )
    try fixture.writeRollout(
        id: sessionID,
        content: """
        {"timestamp":"2026-04-04T12:00:00Z","type":"session_meta","payload":{"id":"\(sessionID)","timestamp":"2026-04-04T12:00:00Z","cwd":"\(cwd)","originator":"codex_cli_rs","source":"cli"}}
        {"timestamp":"2026-04-04T12:00:01Z","type":"event_msg","payload":{"type":"user_message","message":"等待输出"}}
        {"timestamp":"2026-04-04T12:00:02Z","type":"event_msg","payload":{"type":"agent_reasoning","text":"still working"}}
        """
    )

    let detector = CodexSessionDetector(
        baseDirectory: fixture.baseURL,
        environmentProvider: { _ in [:] },
        cwdProvider: { _ in [4646: cwd] }
    )
    let now = try #require(DetectorSupport.parseISO8601("2026-04-04T12:00:20Z"))
    let sessions = await detector.detectSessions(
        context: DetectorSupport.DetectionContext(processes: [
            DetectorSupport.ProcEntry(
                pid: 4646,
                ppid: 1,
                tty: "ttys001",
                state: "S",
                cpu: 0.7,
                elapsedSeconds: 20,
                command: "codex",
                args: "codex"
            ),
        ]),
        now: now
    )

    let session = try #require(sessions.first)
    #expect(session.status == .running)
}

@Test func codexSessionDetectorMatchesDistinctProcessesForSessionsSharingSameCwd() async throws {
    let fixture = try makeCodexFixture()
    defer { try? FileManager.default.removeItem(at: fixture.baseURL) }

    let cwd = "/Users/test/project"
    let firstID = "019d5000-bbbb-7bbb-8bbb-bbbbbbbbbbbb"
    let secondID = "019d5000-cccc-7ccc-8ccc-cccccccccccc"
    try fixture.writeSessionIndex(
        """
        {"id":"\(firstID)","thread_name":"第一个 Codex","updated_at":"2026-04-04T12:00:05Z"}
        {"id":"\(secondID)","thread_name":"第二个 Codex","updated_at":"2026-04-04T12:00:04Z"}
        """
    )
    try fixture.writeRollout(
        id: firstID,
        content: """
        {"timestamp":"2026-04-04T12:00:00Z","type":"session_meta","payload":{"id":"\(firstID)","timestamp":"2026-04-04T12:00:00Z","cwd":"\(cwd)","originator":"codex_cli_rs","source":"cli"}}
        {"timestamp":"2026-04-04T12:00:05Z","type":"event_msg","payload":{"type":"agent_reasoning","text":"First"}}
        """
    )
    try fixture.writeRollout(
        id: secondID,
        content: """
        {"timestamp":"2026-04-04T12:00:00Z","type":"session_meta","payload":{"id":"\(secondID)","timestamp":"2026-04-04T12:00:00Z","cwd":"\(cwd)","originator":"codex_cli_rs","source":"cli"}}
        {"timestamp":"2026-04-04T12:00:04Z","type":"event_msg","payload":{"type":"agent_reasoning","text":"Second"}}
        """
    )

    let detector = CodexSessionDetector(
        baseDirectory: fixture.baseURL,
        environmentProvider: { _ in [:] },
        cwdProvider: { _ in
            [
                101: cwd,
                202: cwd,
            ]
        }
    )
    let now = try #require(DetectorSupport.parseISO8601("2026-04-04T12:00:06Z"))
    let sessions = await detector.detectSessions(
        context: DetectorSupport.DetectionContext(processes: [
            DetectorSupport.ProcEntry(
                pid: 101,
                ppid: 1,
                tty: "ttys001",
                state: "S",
                cpu: 0,
                elapsedSeconds: 4,
                command: "codex",
                args: "codex"
            ),
            DetectorSupport.ProcEntry(
                pid: 202,
                ppid: 1,
                tty: "ttys002",
                state: "S",
                cpu: 0,
                elapsedSeconds: 5,
                command: "codex",
                args: "codex"
            ),
        ]),
        now: now
    )

    #expect(sessions.count == 2)
    #expect(Set(sessions.map(\.pid)) == Set([101, 202]))
}

@Test func codexSessionDetectorTreatsVscodeOriginOverrideAsCliWithoutDesktopBundle() async throws {
    let fixture = try makeCodexFixture()
    defer { try? FileManager.default.removeItem(at: fixture.baseURL) }

    let sessionID = "019d5000-dddd-7ddd-8ddd-dddddddddddd"
    let cwd = "/Users/test/project"
    try fixture.writeSessionIndex(
        """
        {"id":"\(sessionID)","thread_name":"CLI 会话","updated_at":"2026-04-04T12:00:03Z"}
        """
    )
    try fixture.writeRollout(
        id: sessionID,
        content: """
        {"timestamp":"2026-04-04T12:00:00Z","type":"session_meta","payload":{"id":"\(sessionID)","timestamp":"2026-04-04T12:00:00Z","cwd":"\(cwd)","originator":"codex_cli_rs","source":"cli"}}
        {"timestamp":"2026-04-04T12:00:03Z","type":"event_msg","payload":{"type":"agent_reasoning","text":"Still CLI"}}
        """
    )

    let detector = CodexSessionDetector(
        baseDirectory: fixture.baseURL,
        environmentProvider: { _ in
            [
                "CODEX_INTERNAL_ORIGINATOR_OVERRIDE": "vscode",
                "TERM_PROGRAM": "ghostty",
            ]
        },
        cwdProvider: { _ in [303: cwd] }
    )
    let now = try #require(DetectorSupport.parseISO8601("2026-04-04T12:00:05Z"))
    let sessions = await detector.detectSessions(
        context: DetectorSupport.DetectionContext(processes: [
            DetectorSupport.ProcEntry(
                pid: 303,
                ppid: 1,
                tty: "ttys003",
                state: "S",
                cpu: 0,
                elapsedSeconds: 5,
                command: "codex",
                args: "codex"
            ),
        ]),
        now: now
    )

    let session = try #require(sessions.first)
    #expect(session.terminalContext?.origin == .cli)
}

@Test func codexSessionDetectorDoesNotBindFreshProcessToStaleRolloutOnlyByCwd() async throws {
    let fixture = try makeCodexFixture()
    defer { try? FileManager.default.removeItem(at: fixture.baseURL) }

    let sessionID = "019d565f-0a40-71c2-8292-c8627cfc5457"
    let cwd = "/Users/test/project"
    try fixture.writeSessionIndex(
        """
        {"id":"\(sessionID)","thread_name":"旧桌面会话","updated_at":"2026-04-04T02:43:16.795199Z"}
        """
    )
    try fixture.writeRollout(
        id: sessionID,
        content: """
        {"timestamp":"2026-04-04T02:43:10.423Z","type":"session_meta","payload":{"id":"\(sessionID)","timestamp":"2026-04-04T02:42:42.371Z","cwd":"\(cwd)","originator":"Codex Desktop","source":"vscode"}}
        {"timestamp":"2026-04-04T02:43:16.795Z","type":"event_msg","payload":{"type":"agent_reasoning","text":"Old desktop session"}}
        """
    )

    let detector = CodexSessionDetector(
        baseDirectory: fixture.baseURL,
        environmentProvider: { _ in [:] },
        cwdProvider: { _ in [999: cwd] }
    )
    let now = try #require(DetectorSupport.parseISO8601("2026-04-06T10:00:00Z"))
    let sessions = await detector.detectSessions(
        context: DetectorSupport.DetectionContext(processes: [
            DetectorSupport.ProcEntry(
                pid: 999,
                ppid: 1,
                tty: "ttys010",
                state: "S",
                cpu: 0,
                elapsedSeconds: 120,
                command: "codex",
                args: "codex"
            ),
        ]),
        now: now
    )

    #expect(sessions.isEmpty)
}

@Test func codexSessionDetectorIgnoresWaitingKeywordsInTurnContextAndMessages() async throws {
    let fixture = try makeCodexFixture()
    defer { try? FileManager.default.removeItem(at: fixture.baseURL) }

    let sessionID = "019d5000-2111-7222-8222-222222222222"
    try fixture.writeSessionIndex(
        """
        {"id":"\(sessionID)","thread_name":"启动即误判 waiting","updated_at":"2026-04-04T12:10:03Z"}
        """
    )
    try fixture.writeRollout(
        id: sessionID,
        content: """
        {"timestamp":"2026-04-04T12:10:00Z","type":"session_meta","payload":{"id":"\(sessionID)","timestamp":"2026-04-04T12:10:00Z","cwd":"/tmp/project","originator":"Codex Desktop","source":"vscode"}}
        {"timestamp":"2026-04-04T12:10:01Z","type":"response_item","payload":{"type":"message","role":"developer","content":[{"type":"input_text","text":"## request_user_input availability\nThe `request_user_input` tool is unavailable in Default mode."}]}}
        {"timestamp":"2026-04-04T12:10:02Z","type":"turn_context","payload":{"turn_id":"turn-1","cwd":"/tmp/project","collaboration_mode":{"mode":"default","settings":{"developer_instructions":"## request_user_input availability\nThe `request_user_input` tool is unavailable in Default mode."}}}}
        {"timestamp":"2026-04-04T12:10:03Z","type":"event_msg","payload":{"type":"agent_reasoning","text":"Inspecting files"}}
        """
    )

    let detector = CodexSessionDetector(baseDirectory: fixture.baseURL)
    let now = try #require(DetectorSupport.parseISO8601("2026-04-04T12:10:05Z"))
    let sessions = await detector.detectSessions(
        context: DetectorSupport.DetectionContext(processes: []),
        now: now
    )

    let session = try #require(sessions.first)
    #expect(session.status == .running)
    #expect(session.lastInputAt == nil)
}

@Test func codexSessionDetectorMarksAwaitingInputWhenRolloutContainsQuestionRequest() async throws {
    let fixture = try makeCodexFixture()
    defer { try? FileManager.default.removeItem(at: fixture.baseURL) }

    let sessionID = "019d5000-2222-7222-8222-222222222222"
    try fixture.writeSessionIndex(
        """
        {"id":"\(sessionID)","thread_name":"等待用户确认","updated_at":"2026-04-04T12:10:03Z"}
        """
    )
    try fixture.writeRollout(
        id: sessionID,
        content: """
        {"timestamp":"2026-04-04T12:10:00Z","type":"session_meta","payload":{"id":"\(sessionID)","timestamp":"2026-04-04T12:10:00Z","cwd":"/tmp/project","originator":"codex_cli_rs","source":"cli"}}
        {"timestamp":"2026-04-04T12:10:02Z","type":"response_item","payload":{"type":"function_call","name":"request_user_input","arguments":"{\\"question\\":\\"继续吗\\"}"}}
        """
    )

    let detector = CodexSessionDetector(baseDirectory: fixture.baseURL)
    let now = try #require(DetectorSupport.parseISO8601("2026-04-04T12:10:05Z"))
    let sessions = await detector.detectSessions(
        context: DetectorSupport.DetectionContext(processes: []),
        now: now
    )

    #expect(sessions.count == 1)
    #expect(sessions[0].status == .awaitingInput)
    #expect(sessions[0].currentTask == "等待用户确认")
    #expect(sessions[0].lastInputAt != nil)
}

@Test func codexSessionDetectorUsesTaskCompleteAsIdleAnchor() async throws {
    let fixture = try makeCodexFixture()
    defer { try? FileManager.default.removeItem(at: fixture.baseURL) }

    let sessionID = "019d5000-5555-7555-8555-555555555555"
    let cwd = "/tmp/project"
    try fixture.writeSessionIndex(
        """
        {"id":"\(sessionID)","thread_name":"任务已完成","updated_at":"2026-04-04T12:30:04Z"}
        """
    )
    try fixture.writeRollout(
        id: sessionID,
        content: """
        {"timestamp":"2026-04-04T12:30:00Z","type":"session_meta","payload":{"id":"\(sessionID)","timestamp":"2026-04-04T12:30:00Z","cwd":"\(cwd)","originator":"codex_cli_rs","source":"cli"}}
        {"timestamp":"2026-04-04T12:30:01Z","type":"response_item","payload":{"type":"function_call","name":"exec_command","call_id":"call-1"}}
        {"timestamp":"2026-04-04T12:30:04Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-1"}}
        """
    )

    let detector = CodexSessionDetector(baseDirectory: fixture.baseURL)
    let now = try #require(DetectorSupport.parseISO8601("2026-04-04T12:30:06Z"))
    let sessions = await detector.detectSessions(
        context: DetectorSupport.DetectionContext(processes: []),
        now: now
    )

    let session = try #require(sessions.first)
    let anchor = try #require(DetectorSupport.parseISO8601("2026-04-04T12:30:04Z"))
    #expect(session.status == .idle)
    #expect(session.idleSince == anchor)
    #expect(session.statusSince == anchor)
}

@Test func codexSessionDetectorTreatsAbortedAndFailedTurnsAsIdleAnchors() async throws {
    let fixture = try makeCodexFixture()
    defer { try? FileManager.default.removeItem(at: fixture.baseURL) }

    let sessionID = "019d5000-6666-7666-8666-666666666666"
    try fixture.writeSessionIndex(
        """
        {"id":"\(sessionID)","thread_name":"异常结束","updated_at":"2026-04-04T12:40:05Z"}
        """
    )
    try fixture.writeRollout(
        id: sessionID,
        content: """
        {"timestamp":"2026-04-04T12:40:00Z","type":"session_meta","payload":{"id":"\(sessionID)","timestamp":"2026-04-04T12:40:00Z","cwd":"/tmp/project","originator":"codex_cli_rs","source":"cli"}}
        {"timestamp":"2026-04-04T12:40:03Z","type":"event_msg","payload":{"type":"turn_failed","reason":"tool_error"}}
        {"timestamp":"2026-04-04T12:40:05Z","type":"event_msg","payload":{"type":"turn_aborted","reason":"user_cancelled"}}
        """
    )

    let detector = CodexSessionDetector(baseDirectory: fixture.baseURL)
    let now = try #require(DetectorSupport.parseISO8601("2026-04-04T12:40:06Z"))
    let sessions = await detector.detectSessions(
        context: DetectorSupport.DetectionContext(processes: []),
        now: now
    )

    let session = try #require(sessions.first)
    let anchor = try #require(DetectorSupport.parseISO8601("2026-04-04T12:40:05Z"))
    #expect(session.status == .idle)
    #expect(session.idleSince == anchor)
}

@Test func codexSessionDetectorLoadsRolloutPathFromSQLiteWhenFilenameFallbackWouldMiss() async throws {
    let fixture = try makeCodexFixture()
    defer { try? FileManager.default.removeItem(at: fixture.baseURL) }

    let sessionID = "019d5000-7777-7777-8777-777777777777"
    try fixture.writeSessionIndex(
        """
        {"id":"\(sessionID)","thread_name":"SQLite 路径优先","updated_at":"2026-04-04T12:50:03Z"}
        """
    )

    let sqliteRolloutDirectory = fixture.baseURL.appendingPathComponent("sqlite-rollouts", isDirectory: true)
    try FileManager.default.createDirectory(at: sqliteRolloutDirectory, withIntermediateDirectories: true)
    let rolloutURL = sqliteRolloutDirectory.appendingPathComponent("rollout-current.jsonl", isDirectory: false)
    try """
    {"timestamp":"2026-04-04T12:50:00Z","type":"session_meta","payload":{"id":"\(sessionID)","timestamp":"2026-04-04T12:50:00Z","cwd":"/tmp/project","originator":"Codex Desktop","source":"vscode"}}
    {"timestamp":"2026-04-04T12:50:03Z","type":"event_msg","payload":{"type":"agent_reasoning","text":"From sqlite path"}}
    """.write(to: rolloutURL, atomically: true, encoding: .utf8)
    try fixture.writeStateDatabase(sessionID: sessionID, rolloutPath: rolloutURL.path)

    let detector = CodexSessionDetector(baseDirectory: fixture.baseURL)
    let now = try #require(DetectorSupport.parseISO8601("2026-04-04T12:50:05Z"))
    let sessions = await detector.detectSessions(
        context: DetectorSupport.DetectionContext(processes: []),
        now: now
    )

    let session = try #require(sessions.first)
    #expect(session.title == "SQLite 路径优先")
    #expect(session.terminalContext?.bundleIdentifier == "com.openai.codex")
}

@Test func codexSessionDetectorIgnoresStaleSessionsWithoutLiveProcess() async throws {
    let fixture = try makeCodexFixture()
    defer { try? FileManager.default.removeItem(at: fixture.baseURL) }

    let sessionID = "019d5000-3333-7333-8333-333333333333"
    try fixture.writeSessionIndex(
        """
        {"id":"\(sessionID)","thread_name":"历史会话","updated_at":"2026-04-04T11:40:00Z"}
        """
    )
    try fixture.writeRollout(
        id: sessionID,
        content: """
        {"timestamp":"2026-04-04T11:39:00Z","type":"session_meta","payload":{"id":"\(sessionID)","timestamp":"2026-04-04T11:39:00Z","cwd":"/tmp/project","originator":"codex_cli_rs","source":"cli"}}
        {"timestamp":"2026-04-04T11:39:10Z","type":"event_msg","payload":{"type":"agent_reasoning","text":"Old work"}}
        """
    )

    let detector = CodexSessionDetector(baseDirectory: fixture.baseURL)
    let now = try #require(DetectorSupport.parseISO8601("2026-04-04T12:10:05Z"))
    let sessions = await detector.detectSessions(
        context: DetectorSupport.DetectionContext(processes: []),
        now: now
    )

    #expect(sessions.isEmpty)
}

@Test func codexSessionDetectorSynthesizesDesktopContextFromRolloutMetadata() async throws {
    let fixture = try makeCodexFixture()
    defer { try? FileManager.default.removeItem(at: fixture.baseURL) }

    let sessionID = "019d5000-4444-7444-8444-444444444444"
    try fixture.writeSessionIndex(
        """
        {"id":"\(sessionID)","thread_name":"桌面版 Codex 会话","updated_at":"2026-04-04T12:20:03Z"}
        """
    )
    try fixture.writeRollout(
        id: sessionID,
        content: """
        {"timestamp":"2026-04-04T12:20:00Z","type":"session_meta","payload":{"id":"\(sessionID)","timestamp":"2026-04-04T12:20:00Z","cwd":"/tmp/project","originator":"Codex Desktop","source":"vscode"}}
        {"timestamp":"2026-04-04T12:20:02Z","type":"event_msg","payload":{"type":"agent_reasoning","text":"Checking desktop session"}}
        """
    )

    let detector = CodexSessionDetector(baseDirectory: fixture.baseURL)
    let now = try #require(DetectorSupport.parseISO8601("2026-04-04T12:20:05Z"))
    let sessions = await detector.detectSessions(
        context: DetectorSupport.DetectionContext(processes: []),
        now: now
    )

    let session = try #require(sessions.first)
    #expect(session.terminalContext?.origin == .desktop)
    #expect(session.terminalContext?.bundleIdentifier == "com.openai.codex")
}

private struct CodexFixture {
    let baseURL: URL

    func writeSessionIndex(_ content: String) throws {
        let url = baseURL.appendingPathComponent("session_index.jsonl", isDirectory: false)
        try content.data(using: .utf8)?.write(to: url)
    }

    func writeRollout(id: String, content: String) throws {
        _ = try writeRolloutReturningURL(id: id, content: content)
    }

    func writeRolloutReturningURL(id: String, content: String) throws -> URL {
        let directory = baseURL
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("2026", isDirectory: true)
            .appendingPathComponent("04", isDirectory: true)
            .appendingPathComponent("04", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let filename = "rollout-2026-04-04T12-00-00-\(id).jsonl"
        let url = directory.appendingPathComponent(filename, isDirectory: false)
        try content.data(using: .utf8)?.write(to: url)
        return url
    }

    func writeStateDatabase(
        sessionID: String,
        rolloutPath: String,
        title: String = "",
        firstUserMessage: String = "",
        cwd: String = "",
        source: String = "",
        updatedAt: Int64 = 0
    ) throws {
        let databaseURL = baseURL.appendingPathComponent("state_5.sqlite", isDirectory: false)
        var database: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK, let database else {
            if let database { sqlite3_close(database) }
            throw NSError(domain: "CodexFixture", code: 1)
        }
        defer { sqlite3_close(database) }

        let createSQL = """
        CREATE TABLE threads (
            id TEXT PRIMARY KEY,
            rollout_path TEXT NOT NULL,
            updated_at INTEGER NOT NULL DEFAULT 0,
            source TEXT NOT NULL DEFAULT '',
            cwd TEXT NOT NULL DEFAULT '',
            title TEXT NOT NULL DEFAULT '',
            first_user_message TEXT NOT NULL DEFAULT ''
        );
        """
        guard sqlite3_exec(database, createSQL, nil, nil, nil) == SQLITE_OK else {
            throw NSError(domain: "CodexFixture", code: 2)
        }

        let insertSQL = """
        INSERT INTO threads (id, rollout_path, updated_at, source, cwd, title, first_user_message)
        VALUES (?, ?, ?, ?, ?, ?, ?);
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, insertSQL, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw NSError(domain: "CodexFixture", code: 3)
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, sessionID, -1, sqliteTransient)
        sqlite3_bind_text(statement, 2, rolloutPath, -1, sqliteTransient)
        sqlite3_bind_int64(statement, 3, updatedAt)
        sqlite3_bind_text(statement, 4, source, -1, sqliteTransient)
        sqlite3_bind_text(statement, 5, cwd, -1, sqliteTransient)
        sqlite3_bind_text(statement, 6, title, -1, sqliteTransient)
        sqlite3_bind_text(statement, 7, firstUserMessage, -1, sqliteTransient)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw NSError(domain: "CodexFixture", code: 4)
        }
    }
}

private func makeCodexFixture() throws -> CodexFixture {
    let baseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
        at: baseURL.appendingPathComponent("sessions", isDirectory: true),
        withIntermediateDirectories: true
    )
    return CodexFixture(baseURL: baseURL)
}
