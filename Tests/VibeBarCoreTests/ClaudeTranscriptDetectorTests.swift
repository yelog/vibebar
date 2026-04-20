import Foundation
import Testing
@testable import VibeBarCore

@Test func claudeTranscriptDetectorResolvesTerminalContextFromParentChain() async throws {
    let fixture = try makeClaudeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.claudeHome) }

    let cwdURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: cwdURL, withIntermediateDirectories: true)
    let cwd = cwdURL.path
    let sessionID = "session-501"

    try fixture.writeSessionMeta(pid: 501, sessionID: sessionID)

    try fixture.writeTranscript(
        cwd: cwd,
        sessionFileName: "\(sessionID).jsonl",
        lines: [
            #"{"type":"user","timestamp":"2026-04-20T10:00:00Z","message":{"role":"user","content":"修复 Claude 跳转"}}"#,
            #"{"type":"assistant","timestamp":"2026-04-20T10:00:02Z","message":{"role":"assistant","content":"开始分析"}}"#,
        ]
    )

    let detector = ClaudeTranscriptDetector(claudeHome: fixture.claudeHome)
    let sessions = await detector.detectSessions(
        context: DetectorSupport.DetectionContext(processes: [
            DetectorSupport.ProcEntry(
                pid: 501,
                ppid: 401,
                tty: "ttys009",
                state: "S",
                cpu: 0,
                elapsedSeconds: 12,
                command: "/usr/local/bin/claude",
                args: "claude"
            ),
            DetectorSupport.ProcEntry(
                pid: 401,
                ppid: 301,
                tty: "ttys009",
                state: "S",
                cpu: 0,
                elapsedSeconds: 20,
                command: "/bin/zsh",
                args: "-zsh"
            ),
            DetectorSupport.ProcEntry(
                pid: 301,
                ppid: 1,
                tty: "ttys009",
                state: "S",
                cpu: 0,
                elapsedSeconds: 30,
                command: "/Applications/kitty.app/Contents/MacOS/kitty",
                args: "kitty"
            ),
        ]),
        cwdByPID: [501: cwd],
        now: try #require(DetectorSupport.parseISO8601("2026-04-20T10:00:05Z"))
    )

    let session = try #require(sessions.first)
    #expect(session.title == "修复 Claude 跳转")
    #expect(session.terminalContext?.clientKind == .kitty)
    #expect(session.terminalContext?.bundleIdentifier == "net.kovidgoyal.kitty")
    #expect(session.terminalContext?.origin == .cli)
}

private struct ClaudeFixture {
    let claudeHome: URL

    func writeSessionMeta(pid: Int32, sessionID: String, name: String? = nil) throws {
        let sessionsDir = claudeHome.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)

        var payload: [String: String] = ["sessionId": sessionID]
        if let name {
            payload["name"] = name
        }

        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        try data.write(to: sessionsDir.appendingPathComponent("\(pid).json", isDirectory: false))
    }

    func writeTranscript(cwd: String, sessionFileName: String, lines: [String]) throws {
        let projectDir = claudeHome
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent(encodeClaudeProjectPath(cwd), isDirectory: true)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        let contents = lines.joined(separator: "\n") + "\n"
        try contents.data(using: .utf8)?.write(to: projectDir.appendingPathComponent(sessionFileName, isDirectory: false))
    }
}

private func makeClaudeFixture() throws -> ClaudeFixture {
    let claudeHome = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: claudeHome, withIntermediateDirectories: true)
    return ClaudeFixture(claudeHome: claudeHome)
}

private func encodeClaudeProjectPath(_ path: String) -> String {
    "-" + path.dropFirst().replacingOccurrences(of: "/", with: "-")
}
