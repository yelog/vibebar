import Foundation
import Testing
@testable import VibeBarCore

private func makeTestSession(id: String = "test-session", tool: ToolKind = .claudeCode, status: ToolActivityState = .idle, cwd: String? = "/Users/test/project") -> SessionSnapshot {
    SessionSnapshot(
        id: id,
        tool: tool,
        pid: 12345,
        status: status,
        source: .plugin,
        startedAt: Date(timeIntervalSince1970: 1700000000),
        updatedAt: Date(timeIntervalSince1970: 1700001000),
        cwd: cwd,
        command: ["claude", "--dangerously-skip-permissions"]
    )
}

@Test func hookContextEnvironmentContainsRequiredFields() {
    let session = makeTestSession()
    let context = HookContext(trigger: .sessionStarted, session: session, previousState: nil)
    let env = context.environment
    
    #expect(env["VIBEBAR_TRIGGER"] == "session_started")
    #expect(env["VIBEBAR_SESSION_ID"] == "test-session")
    #expect(env["VIBEBAR_TOOL"] == "claude-code")
    #expect(env["VIBEBAR_STATUS"] == "idle")
    #expect(env["VIBEBAR_PID"] == "12345")
    #expect(env["VIBEBAR_CWD"] == "/Users/test/project")
}

@Test func hookContextEnvironmentIncludesPreviousStateWhenProvided() {
    let session = makeTestSession()
    let context = HookContext(trigger: .stateChanged, session: session, previousState: .running)
    let env = context.environment
    
    #expect(env["VIBEBAR_PREV_STATUS"] == "running")
}

@Test func hookContextEnvironmentOmitsPreviousStateWhenNil() {
    let session = makeTestSession()
    let context = HookContext(trigger: .sessionStarted, session: session, previousState: nil)
    let env = context.environment
    
    #expect(env["VIBEBAR_PREV_STATUS"] == nil)
}

@Test func hookContextEnvironmentOmitsCwdWhenEmpty() {
    let session = makeTestSession(cwd: nil)
    let context = HookContext(trigger: .sessionStarted, session: session, previousState: nil)
    let env = context.environment
    
    #expect(env["VIBEBAR_CWD"] == nil)
}

@Test func hookContextEnvironmentOmitsCwdWhenNil() {
    let session = SessionSnapshot(
        id: "test",
        tool: .claudeCode,
        pid: 12345,
        status: .idle,
        source: .plugin,
        startedAt: Date(),
        updatedAt: Date(),
        cwd: nil,
        command: ["claude"]
    )
    let context = HookContext(trigger: .sessionStarted, session: session, previousState: nil)
    let env = context.environment
    
    #expect(env["VIBEBAR_CWD"] == nil)
}

@Test func hookContextEnvironmentTimestampsUseISO8601() {
    let session = makeTestSession()
    let context = HookContext(trigger: .sessionStarted, session: session, previousState: nil)
    let env = context.environment
    
    #expect(env["VIBEBAR_STARTED_AT"]?.contains("2023") == true)
    #expect(env["VIBEBAR_UPDATED_AT"]?.contains("2023") == true)
    #expect(env["VIBEBAR_EVENT_TIME"]?.contains("T") == true)
    #expect(env["VIBEBAR_STARTED_AT"]?.contains("Z") == true)
}

@Test func hookContextEnvironmentContainsToolDisplayName() {
    let session = makeTestSession(tool: .claudeCode)
    let context = HookContext(trigger: .sessionStarted, session: session, previousState: nil)
    let env = context.environment
    
    #expect(env["VIBEBAR_TOOL_DISPLAY"] == "Claude Code")
}

@Test func hookContextEnvironmentForCodexTool() {
    let session = makeTestSession(tool: .codex)
    let context = HookContext(trigger: .runningToIdle, session: session, previousState: .running)
    let env = context.environment
    
    #expect(env["VIBEBAR_TOOL"] == "codex")
    #expect(env["VIBEBAR_TOOL_DISPLAY"] == "Codex")
    #expect(env["VIBEBAR_TRIGGER"] == "running_to_idle")
}

@Test func hookContextJsonPayloadIsValidJson() throws {
    let session = makeTestSession()
    let context = HookContext(trigger: .sessionStarted, session: session, previousState: nil)
    
    guard let data = context.jsonPayload else {
        Issue.record("jsonPayload should not be nil")
        return
    }
    
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(json != nil)
    #expect(json?["trigger"] as? String == "session_started")
}

@Test func hookContextJsonPayloadContainsSessionData() throws {
    let session = makeTestSession(id: "my-session", tool: .claudeCode, status: .running)
    let context = HookContext(trigger: .stateChanged, session: session, previousState: .idle)
    
    guard let data = context.jsonPayload else {
        Issue.record("jsonPayload should not be nil")
        return
    }
    
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let sessionData = json?["session"] as? [String: Any]
    
    #expect(sessionData?["id"] as? String == "my-session")
    #expect(sessionData?["tool"] as? String == "claude-code")
    #expect(sessionData?["status"] as? String == "running")
    #expect(sessionData?["previous_status"] as? String == "idle")
}

@Test func hookContextJsonPayloadIncludesCommand() throws {
    let session = makeTestSession()
    let context = HookContext(trigger: .sessionStarted, session: session, previousState: nil)
    
    guard let data = context.jsonPayload else {
        Issue.record("jsonPayload should not be nil")
        return
    }
    
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let sessionData = json?["session"] as? [String: Any]
    let command = sessionData?["command"] as? [String]
    
    #expect(command?.count == 2)
    #expect(command?.contains("claude") == true)
    #expect(command?.contains("--dangerously-skip-permissions") == true)
}

@Test func hookContextJsonStringMatchesPayload() {
    let session = makeTestSession()
    let context = HookContext(trigger: .sessionStarted, session: session, previousState: nil)
    
    guard let jsonString = context.jsonString else {
        Issue.record("jsonString should not be nil")
        return
    }
    
    #expect(jsonString.contains("session_started"))
    #expect(jsonString.contains("test-session"))
    #expect(jsonString.contains("claude-code"))
}

@Test func hookContextTimestampDefaultsToNow() {
    let before = Date()
    let session = makeTestSession()
    let context = HookContext(trigger: .sessionStarted, session: session, previousState: nil)
    let after = Date()
    
    #expect(context.timestamp >= before)
    #expect(context.timestamp <= after)
}

@Test func hookContextTimestampCanBeProvided() {
    let fixedDate = Date(timeIntervalSince1970: 1600000000)
    let session = makeTestSession()
    let context = HookContext(trigger: .sessionStarted, session: session, previousState: nil, timestamp: fixedDate)
    
    #expect(context.timestamp == fixedDate)
}

@Test func hookContextCodableRoundtrip() throws {
    let session = makeTestSession()
    let original = HookContext(trigger: .runningToIdle, session: session, previousState: .running)
    
    let encoder = JSONEncoder()
    let data = try encoder.encode(original)
    
    let decoder = JSONDecoder()
    let decoded = try decoder.decode(HookContext.self, from: data)
    
    #expect(decoded.trigger == original.trigger)
    #expect(decoded.session.id == original.session.id)
    #expect(decoded.previousState == original.previousState)
}

@Test func hookContextEnvironmentForAllToolKinds() {
    for tool in ToolKind.allCases {
        let session = makeTestSession(tool: tool)
        let context = HookContext(trigger: .sessionStarted, session: session, previousState: nil)
        let env = context.environment
        
        #expect(env["VIBEBAR_TOOL"] == tool.rawValue)
        #expect(env["VIBEBAR_TOOL_DISPLAY"] != nil)
        #expect(env["VIBEBAR_TOOL_DISPLAY"]?.isEmpty == false)
    }
}

@Test func hookContextEnvironmentForAllTriggers() {
    let session = makeTestSession()
    for trigger in HookTrigger.allCases {
        let context = HookContext(trigger: trigger, session: session, previousState: nil)
        let env = context.environment
        
        #expect(env["VIBEBAR_TRIGGER"] == trigger.rawValue)
    }
}

@Test func terminalContextCodableRoundtrip() throws {
    let original = TerminalContext(
        clientKind: .kitty,
        bundleIdentifier: "net.kovidgoyal.kitty",
        clientControlAddress: "unix:/tmp/kitty-7033",
        tty: "ttys014",
        clientSessionID: "22",
        clientWindowID: "22",
        sessionManagerKind: .tmux,
        sessionManagerSessionID: "/tmp/tmux-501/default,123,0",
        sessionManagerPaneID: "%3",
        sessionManagerTabName: "开发",
        sessionManagerTabIndex: 2,
        origin: .cli
    )

    let encoder = JSONEncoder()
    let data = try encoder.encode(original)

    let decoder = JSONDecoder()
    let decoded = try decoder.decode(TerminalContext.self, from: data)

    #expect(decoded == original)
}

@Test func terminalContextResolverDetectsKittyAndTmuxFromMetadata() {
    let context = TerminalContextResolver.resolve(
        metadata: [
            "TERM_PROGRAM": "ghostty",
            "KITTY_WINDOW_ID": "22",
            "KITTY_LISTEN_ON": "unix:/tmp/kitty-7033",
            "TMUX": "/tmp/tmux-501/default,123,0",
            "TMUX_PANE": "%3",
            "_tty": "ttys014",
            "__CFBundleIdentifier": "net.kovidgoyal.kitty",
        ],
        originHint: .cli
    )

    #expect(context?.clientKind == .kitty)
    #expect(context?.clientControlAddress == "unix:/tmp/kitty-7033")
    #expect(context?.tty == "ttys014")
    #expect(context?.sessionManagerKind == .tmux)
    #expect(context?.sessionManagerPaneID == "%3")
    #expect(context?.origin == .cli)
}

@Test func terminalContextResolverDetectsZellijFromMetadata() {
    let context = TerminalContextResolver.resolve(
        metadata: [
            "TERM_PROGRAM": "ghostty",
            "ZELLIJ": "0",
            "ZELLIJ_SESSION_NAME": "workspace",
            "ZELLIJ_PANE_ID": "7",
            "zellij_tab_name": "后端",
            "ZELLIJ_TAB_INDEX": "1",
            "_tty": "ttys006",
        ],
        originHint: .cli
    )

    #expect(context?.clientKind == .ghostty)
    #expect(context?.sessionManagerKind == .zellij)
    #expect(context?.sessionManagerSessionID == "workspace")
    #expect(context?.sessionManagerPaneID == "7")
    #expect(context?.sessionManagerTabName == "后端")
    #expect(context?.sessionManagerTabIndex == 1)
}

@Test func terminalContextResolverDetectsCodexDesktopFromBundleIdentifier() {
    let context = TerminalContextResolver.resolve(
        metadata: [
            "__CFBundleIdentifier": "com.openai.codex",
        ]
    )

    #expect(context?.bundleIdentifier == "com.openai.codex")
    #expect(context?.origin == .desktop)
    #expect(context?.clientKind == .unknown)
}

@Test func terminalContextResolverFallsBackToProcessChainTTYAndKittyLoginWrapper() {
    let context = TerminalContextResolver.resolve(
        metadata: [:],
        processChain: [
            DetectorSupport.ProcEntry(
                pid: 91639,
                ppid: 96473,
                tty: "ttys005",
                state: "S",
                cpu: 0,
                elapsedSeconds: 10,
                command: "opencode",
                args: "opencode"
            ),
            DetectorSupport.ProcEntry(
                pid: 96473,
                ppid: 96468,
                tty: "ttys005",
                state: "S",
                cpu: 0,
                elapsedSeconds: 10,
                command: "-zsh",
                args: "-zsh"
            ),
            DetectorSupport.ProcEntry(
                pid: 96468,
                ppid: 7033,
                tty: "ttys005",
                state: "S",
                cpu: 0,
                elapsedSeconds: 10,
                command: "/usr/bin/login",
                args: "/usr/bin/login -f -l -p yelog /Applications/kitty.app/Contents/MacOS/kitten run-shell --shell /bin/zsh"
            ),
        ]
    )

    #expect(context?.tty == "ttys005")
    #expect(context?.clientKind == .kitty)
    #expect(context?.bundleIdentifier == "net.kovidgoyal.kitty")
    #expect(context?.origin == .cli)
}
