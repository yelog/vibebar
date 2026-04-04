import Foundation
import Testing
@testable import VibeBarCore

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
    #expect(sessions[0].cwd == "/tmp/project")
    #expect(sessions[0].status == .running)
    #expect(sessions[0].source == .sessionFile)
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
    #expect(sessions[0].lastInputAt != nil)
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

private struct CodexFixture {
    let baseURL: URL

    func writeSessionIndex(_ content: String) throws {
        let url = baseURL.appendingPathComponent("session_index.jsonl", isDirectory: false)
        try content.data(using: .utf8)?.write(to: url)
    }

    func writeRollout(id: String, content: String) throws {
        let directory = baseURL
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("2026", isDirectory: true)
            .appendingPathComponent("04", isDirectory: true)
            .appendingPathComponent("04", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let filename = "rollout-2026-04-04T12-00-00-\(id).jsonl"
        let url = directory.appendingPathComponent(filename, isDirectory: false)
        try content.data(using: .utf8)?.write(to: url)
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
