import Foundation
import Testing
@testable import VibeBarCore

@Test func geminiTranscriptDetectorBuildsSessionNameFromFirstUserMessage() async throws {
    let fixture = try makeGeminiFixture()
    defer { try? FileManager.default.removeItem(at: fixture.geminiHome) }

    let cwd = "/tmp/gemini-project"
    try fixture.writeTranscript(
        cwd: cwd,
        messages: """
        [
          {
            "type": "user",
            "timestamp": "2026-04-05T10:00:00Z",
            "text": "先分析当前 session 名逻辑"
          },
          {
            "type": "gemini",
            "timestamp": "2026-04-05T10:00:02Z",
            "text": "好的，我先看看"
          },
          {
            "type": "user",
            "timestamp": "2026-04-05T10:00:05Z",
            "content": [
              { "text": "然后补齐 Gemini 的默认会话名" }
            ]
          }
        ]
        """
    )

    let detector = GeminiTranscriptDetector(geminiHome: fixture.geminiHome)
    let sessions = await detector.detectSessions(
        context: DetectorSupport.DetectionContext(processes: [
            DetectorSupport.ProcEntry(
                pid: 4321,
                ppid: 1234,
                tty: "ttys001",
                state: "S",
                cpu: 0,
                elapsedSeconds: 12,
                command: "/usr/local/bin/gemini",
                args: "gemini"
            ),
        ]),
        cwdByPID: [4321: cwd],
        now: try #require(DetectorSupport.parseISO8601("2026-04-05T10:00:06Z"))
    )

    let session = try #require(sessions.first)
    #expect(session.title == "先分析当前 session 名逻辑")
    #expect(session.titleSource == .derived)
    #expect(session.currentTask == "然后补齐 Gemini 的默认会话名")
}

@Test func geminiTranscriptDetectorRecordsIdleSinceFromLastModelOutput() async throws {
    let fixture = try makeGeminiFixture()
    defer { try? FileManager.default.removeItem(at: fixture.geminiHome) }

    let cwd = "/tmp/gemini-idle-project"
    try fixture.writeTranscript(
        cwd: cwd,
        messages: """
        [
          {
            "type": "user",
            "timestamp": "2026-04-05T10:00:00Z",
            "text": "分析空闲折叠"
          },
          {
            "type": "gemini",
            "timestamp": "2026-04-05T10:00:02Z",
            "text": "已经分析完成"
          }
        ]
        """
    )

    let detector = GeminiTranscriptDetector(geminiHome: fixture.geminiHome)
    let sessions = await detector.detectSessions(
        context: DetectorSupport.DetectionContext(processes: [
            DetectorSupport.ProcEntry(
                pid: 4321,
                ppid: 1234,
                tty: "ttys001",
                state: "S",
                cpu: 0,
                elapsedSeconds: 12,
                command: "/usr/local/bin/gemini",
                args: "gemini"
            ),
        ]),
        cwdByPID: [4321: cwd],
        now: try #require(DetectorSupport.parseISO8601("2026-04-05T10:00:10Z"))
    )

    let session = try #require(sessions.first)
    let idleSince = try #require(DetectorSupport.parseISO8601("2026-04-05T10:00:02Z"))
    #expect(session.status == .idle)
    #expect(session.idleSince == idleSince)
    #expect(session.statusSince == idleSince)
}

private struct GeminiFixture {
    let geminiHome: URL

    func writeTranscript(cwd: String, messages: String) throws {
        let sessionDir = geminiHome
            .appendingPathComponent("tmp", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let chatsDir = sessionDir.appendingPathComponent("chats", isDirectory: true)
        try FileManager.default.createDirectory(at: chatsDir, withIntermediateDirectories: true)
        try cwd.data(using: .utf8)?.write(to: sessionDir.appendingPathComponent(".project_root", isDirectory: false))
        try messages.data(using: .utf8)?.write(to: chatsDir.appendingPathComponent("session.json", isDirectory: false))
    }
}

private func makeGeminiFixture() throws -> GeminiFixture {
    let geminiHome = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: geminiHome, withIntermediateDirectories: true)
    return GeminiFixture(geminiHome: geminiHome)
}
