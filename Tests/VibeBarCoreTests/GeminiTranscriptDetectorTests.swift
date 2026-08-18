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

@Test func geminiTranscriptDetectorResolvesTerminalContextFromParentChain() async throws {
    let fixture = try makeGeminiFixture()
    defer { try? FileManager.default.removeItem(at: fixture.geminiHome) }

    let cwd = "/tmp/gemini-terminal-project"
    try fixture.writeTranscript(
        cwd: cwd,
        messages: """
        [
          {
            "type": "user",
            "timestamp": "2026-04-20T10:00:00Z",
            "text": "定位 Gemini 跳转问题"
          },
          {
            "type": "gemini",
            "timestamp": "2026-04-20T10:00:02Z",
            "text": "开始检查"
          }
        ]
        """
    )

    let detector = GeminiTranscriptDetector(geminiHome: fixture.geminiHome)
    let sessions = await detector.detectSessions(
        context: DetectorSupport.DetectionContext(processes: [
            DetectorSupport.ProcEntry(
                pid: 4321,
                ppid: 4200,
                tty: "ttys011",
                state: "S",
                cpu: 0,
                elapsedSeconds: 12,
                command: "/usr/local/bin/gemini",
                args: "gemini"
            ),
            DetectorSupport.ProcEntry(
                pid: 4200,
                ppid: 4100,
                tty: "ttys011",
                state: "S",
                cpu: 0,
                elapsedSeconds: 20,
                command: "/bin/zsh",
                args: "-zsh"
            ),
            DetectorSupport.ProcEntry(
                pid: 4100,
                ppid: 1,
                tty: "ttys011",
                state: "S",
                cpu: 0,
                elapsedSeconds: 30,
                command: "/Applications/kitty.app/Contents/MacOS/kitty",
                args: "kitty"
            ),
        ]),
        cwdByPID: [4321: cwd],
        now: try #require(DetectorSupport.parseISO8601("2026-04-20T10:00:05Z"))
    )

    let session = try #require(sessions.first)
    #expect(session.terminalContext?.clientKind == .kitty)
    #expect(session.terminalContext?.bundleIdentifier == "net.kovidgoyal.kitty")
    #expect(session.terminalContext?.origin == .cli)
}

@Test func geminiTranscriptDetectorIgnoresVersionProbeProcess() async throws {
    let fixture = try makeGeminiFixture()
    defer { try? FileManager.default.removeItem(at: fixture.geminiHome) }

    let cwd = "/tmp/gemini-version-project"
    try fixture.writeTranscript(
        cwd: cwd,
        messages: """
        [
          {
            "type": "user",
            "timestamp": "2026-04-20T10:00:00Z",
            "text": "真实会话内容"
          }
        ]
        """
    )

    let detector = GeminiTranscriptDetector(geminiHome: fixture.geminiHome)
    let sessions = await detector.detectSessions(
        context: DetectorSupport.DetectionContext(processes: [
            DetectorSupport.ProcEntry(
                pid: 4321,
                ppid: 4200,
                tty: nil,
                state: "S",
                cpu: 0,
                elapsedSeconds: 1,
                command: "/usr/local/bin/gemini",
                args: "gemini --version"
            ),
        ]),
        cwdByPID: [4321: cwd],
        now: try #require(DetectorSupport.parseISO8601("2026-04-20T10:00:05Z"))
    )

    #expect(sessions.isEmpty)
}

@Test func geminiTranscriptDetectorParsesUnchangedTranscriptOnlyOnce() async throws {
    let diagnostics = EnergyDiagnostics()

    let fixture = try makeGeminiFixture()
    defer { try? FileManager.default.removeItem(at: fixture.geminiHome) }

    let cwd = "/tmp/gemini-spy-project"
    let transcriptURL = try fixture.writeTranscript(
        cwd: cwd,
        messages: """
        [
          { "type": "user", "timestamp": "2026-04-05T10:00:00Z", "text": "hello" }
        ]
        """
    )

    let detector = GeminiTranscriptDetector(geminiHome: fixture.geminiHome, diagnostics: diagnostics)
    let context = DetectorSupport.DetectionContext(processes: [
        DetectorSupport.ProcEntry(
            pid: 4321,
            ppid: 1,
            tty: nil,
            state: "S",
            cpu: 0,
            elapsedSeconds: 12,
            command: "/usr/local/bin/gemini",
            args: "gemini"
        ),
    ])
    let now = try #require(DetectorSupport.parseISO8601("2026-04-05T10:00:05Z"))

    _ = await detector.detectSessions(context: context, cwdByPID: [4321: cwd], now: now)
    _ = await detector.detectSessions(context: context, cwdByPID: [4321: cwd], now: now)
    #expect(diagnostics.count(for: .transcriptParse) == 1)

    let handle = try FileHandle(forWritingTo: transcriptURL)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data("""
    ,{ "type": "gemini", "timestamp": "2026-04-05T10:00:02Z", "text": "done" }
    """.utf8))
    try handle.close()

    _ = await detector.detectSessions(context: context, cwdByPID: [4321: cwd], now: now)
    #expect(diagnostics.count(for: .transcriptParse) == 2)
}

private struct GeminiFixture {
    let geminiHome: URL

    func writeTranscript(cwd: String, messages: String) throws -> URL {
        let sessionDir = geminiHome
            .appendingPathComponent("tmp", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let chatsDir = sessionDir.appendingPathComponent("chats", isDirectory: true)
        try FileManager.default.createDirectory(at: chatsDir, withIntermediateDirectories: true)
        try cwd.data(using: .utf8)?.write(to: sessionDir.appendingPathComponent(".project_root", isDirectory: false))
        let url = chatsDir.appendingPathComponent("session.json", isDirectory: false)
        try messages.data(using: .utf8)?.write(to: url)
        return url
    }
}

private func makeGeminiFixture() throws -> GeminiFixture {
    let geminiHome = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: geminiHome, withIntermediateDirectories: true)
    return GeminiFixture(geminiHome: geminiHome)
}
