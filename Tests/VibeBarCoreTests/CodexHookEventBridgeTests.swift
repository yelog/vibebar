import Foundation
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
