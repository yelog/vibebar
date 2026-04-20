import Foundation
import SQLite3
import Testing
@testable import VibeBarCore

@Test func codexHookEventBridgeMapsSessionStartToRunningEvent() throws {
    let context = CodexHookBridgeContext(
        environment: [:],
        currentDirectory: "/tmp/project",
        processID: 9001,
        parentPID: 4242,
        ttyPath: "/dev/ttys001"
    )

    let event = try #require(
        CodexHookEventBridge.makeEvent(
            from: [
                "hook_event_name": "SessionStart",
                "session_id": "sess-1",
                "cwd": "/tmp/project",
            ],
            context: context
        )
    )

    #expect(event.source == .codexHook)
    #expect(event.tool == .codex)
    #expect(event.sessionID == "sess-1")
    #expect(event.eventType == "session_start")
    #expect(event.status == .running)
    #expect(event.pid == 4242)
    #expect(event.parentPID == 9001)
    #expect(event.metadata["_tty"] == "/dev/ttys001")
}

@Test func codexHookEventBridgeMapsStopToIdleWithoutDeletingSession() throws {
    let context = CodexHookBridgeContext(
        environment: [:],
        currentDirectory: "/tmp/project",
        processID: 9001,
        parentPID: 4242
    )

    let event = try #require(
        CodexHookEventBridge.makeEvent(
            from: [
                "hook_event_name": "Stop",
                "session_id": "sess-2",
            ],
            context: context
        )
    )

    #expect(event.eventType == "stop")
    #expect(event.status == .idle)
}

@Test func codexHookEventBridgeMapsSessionEndToTerminalEventWithoutStatus() throws {
    let context = CodexHookBridgeContext(
        environment: [:],
        currentDirectory: "/tmp/project",
        processID: 9001,
        parentPID: 4242
    )

    let event = try #require(
        CodexHookEventBridge.makeEvent(
            from: [
                "hook_event_name": "SessionEnd",
                "session_id": "sess-3",
            ],
            context: context
        )
    )

    #expect(event.eventType == "session_end")
    #expect(event.status == nil)
}

@Test func codexHookEventBridgeCarriesPromptToolAndTerminalMetadata() throws {
    let context = CodexHookBridgeContext(
        environment: [
            "TERM_PROGRAM": "ghostty",
            "__CFBundleIdentifier": "com.mitchellh.ghostty",
            "TMUX": "/tmp/tmux-1000/default,123,0",
            "TMUX_PANE": "%1",
        ],
        currentDirectory: "/tmp/project",
        processID: 9001,
        parentPID: 4242,
        ttyPath: "/dev/ttys009"
    )

    let event = try #require(
        CodexHookEventBridge.makeEvent(
            from: [
                "hook_event_name": "PreToolUse",
                "session_id": "sess-4",
                "prompt": "继续分析这个问题",
                "tool_name": "exec_command",
                "thread_name": "修复状态监控",
            ],
            context: context
        )
    )

    #expect(event.eventType == "pre_tool_use")
    #expect(event.status == .running)
    #expect(event.metadata["prompt"] == "继续分析这个问题")
    #expect(event.metadata["first_user_message"] == "继续分析这个问题")
    #expect(event.metadata["tool_name"] == "exec_command")
    #expect(event.metadata["thread_name"] == "修复状态监控")
    #expect(event.metadata["TERM_PROGRAM"] == "ghostty")
    #expect(event.metadata["__CFBundleIdentifier"] == "com.mitchellh.ghostty")
    #expect(event.metadata["TMUX_PANE"] == "%1")
    #expect(event.metadata["_tty"] == "/dev/ttys009")
}

@Test func codexHookEventBridgeBackfillsSessionMetadataFromLocalCodexState() throws {
    let fixture = try makeCodexHookFixture()
    defer { try? FileManager.default.removeItem(at: fixture.baseURL) }

    let rolloutPath = fixture.baseURL
        .appendingPathComponent("sessions", isDirectory: true)
        .appendingPathComponent("2026/04/20/rollout-current.jsonl", isDirectory: false)
    try FileManager.default.createDirectory(
        at: rolloutPath.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try Data().write(to: rolloutPath)

    try fixture.writeThreadState(
        sessionID: "sess-local-title",
        rolloutPath: rolloutPath.path,
        title: "修复 Codex App 会话名",
        firstUserMessage: "请分析当前未命名问题",
        cwd: "/tmp/project",
        source: "vscode"
    )

    let context = CodexHookBridgeContext(
        environment: ["CODEX_HOME": fixture.baseURL.path],
        currentDirectory: "/tmp/project",
        processID: 9001,
        parentPID: 4242
    )

    let event = try #require(
        CodexHookEventBridge.makeEvent(
            from: [
                "hook_event_name": "SessionStart",
                "session_id": "sess-local-title",
            ],
            context: context
        )
    )

    #expect(event.metadata["thread_name"] == "修复 Codex App 会话名")
    #expect(event.metadata["title"] == "修复 Codex App 会话名")
    #expect(event.metadata["session_title"] == "修复 Codex App 会话名")
    #expect(event.metadata["first_user_message"] == "请分析当前未命名问题")
    #expect(event.metadata["last_user_message"] == "请分析当前未命名问题")
    #expect(event.metadata["transcript_path"] == rolloutPath.path)
    #expect(event.metadata["source"] == "vscode")
 }

@Test func codexHookEventBridgeRejectsPayloadWithoutSessionID() {
    let context = CodexHookBridgeContext(
        environment: [:],
        currentDirectory: "/tmp/project",
        processID: 9001,
        parentPID: 4242
    )

    let event = CodexHookEventBridge.makeEvent(
        from: [
            "hook_event_name": "SessionStart",
        ],
        context: context
    )

    #expect(event == nil)
}

private let codexHookSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private struct CodexHookFixture {
    let baseURL: URL

    func writeThreadState(
        sessionID: String,
        rolloutPath: String,
        title: String,
        firstUserMessage: String,
        cwd: String,
        source: String
    ) throws {
        let databaseURL = baseURL.appendingPathComponent("state_5.sqlite", isDirectory: false)
        var database: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK, let database else {
            if let database { sqlite3_close(database) }
            throw NSError(domain: "CodexHookFixture", code: 1)
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
            throw NSError(domain: "CodexHookFixture", code: 2)
        }

        let insertSQL = """
        INSERT INTO threads (id, rollout_path, updated_at, source, cwd, title, first_user_message)
        VALUES (?, ?, ?, ?, ?, ?, ?);
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, insertSQL, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw NSError(domain: "CodexHookFixture", code: 3)
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, sessionID, -1, codexHookSQLiteTransient)
        sqlite3_bind_text(statement, 2, rolloutPath, -1, codexHookSQLiteTransient)
        sqlite3_bind_int64(statement, 3, 1_744_000_000)
        sqlite3_bind_text(statement, 4, source, -1, codexHookSQLiteTransient)
        sqlite3_bind_text(statement, 5, cwd, -1, codexHookSQLiteTransient)
        sqlite3_bind_text(statement, 6, title, -1, codexHookSQLiteTransient)
        sqlite3_bind_text(statement, 7, firstUserMessage, -1, codexHookSQLiteTransient)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw NSError(domain: "CodexHookFixture", code: 4)
        }
    }
}

private func makeCodexHookFixture() throws -> CodexHookFixture {
    let baseURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
    return CodexHookFixture(baseURL: baseURL)
}
