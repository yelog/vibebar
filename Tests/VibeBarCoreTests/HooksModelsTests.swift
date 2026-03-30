import Foundation
import Testing
@testable import VibeBarCore

@Test func hookTriggerRawValuesMatchExpected() {
    #expect(HookTrigger.sessionStarted.rawValue == "session_started")
    #expect(HookTrigger.sessionEnded.rawValue == "session_ended")
    #expect(HookTrigger.stateChanged.rawValue == "state_changed")
    #expect(HookTrigger.runningToIdle.rawValue == "running_to_idle")
    #expect(HookTrigger.runningToAwaiting.rawValue == "running_to_awaiting")
    #expect(HookTrigger.idleToRunning.rawValue == "idle_to_running")
}

@Test func hookTriggerIsCaseIterable() {
    #expect(HookTrigger.allCases.count == 6)
}

@Test func hookTriggerIsIdentifiable() {
    let trigger: HookTrigger = .sessionStarted
    #expect(trigger.id == "session_started")
}

@Test func hookTriggerDescriptionProvidesHumanReadableText() {
    #expect(HookTrigger.sessionStarted.description == "New session detected")
    #expect(HookTrigger.sessionEnded.description == "Session ended (process terminated)")
    #expect(HookTrigger.runningToIdle.description == "Task completed (running → idle)")
    #expect(HookTrigger.runningToAwaiting.description == "Waiting for input (running → awaiting)")
}

@Test func hookActionTypeRawValuesMatchExpected() {
    #expect(HookActionType.shell.rawValue == "shell")
    #expect(HookActionType.webhook.rawValue == "webhook")
}

@Test func hookActionTypeIsCaseIterable() {
    #expect(HookActionType.allCases.count == 2)
}

@Test func hookActionTypeIsIdentifiable() {
    let actionType: HookActionType = .shell
    #expect(actionType.id == "shell")
}

@Test func hookActionShellFactoryCreatesCorrectAction() {
    let action = HookAction.shell(command: "echo test", timeout: 5.0)
    #expect(action.type == .shell)
    #expect(action.shellCommand == "echo test")
    #expect(action.timeout == 5.0)
    #expect(action.webhookURL == nil)
}

@Test func hookActionWebhookFactoryCreatesCorrectAction() {
    let action = HookAction.webhook(url: "https://example.com/hook", method: "POST", headers: ["X-Auth": "token"], timeout: 10.0)
    #expect(action.type == .webhook)
    #expect(action.webhookURL == "https://example.com/hook")
    #expect(action.webhookMethod == "POST")
    #expect(action.webhookHeaders?["X-Auth"] == "token")
    #expect(action.timeout == 10.0)
    #expect(action.shellCommand == nil)
}

@Test func hookActionDefaultTimeout() {
    let shellAction = HookAction(type: .shell, shellCommand: "test")
    #expect(shellAction.timeout == 30.0)
    
    let webhookAction = HookAction(type: .webhook, webhookURL: "https://test.com")
    #expect(webhookAction.timeout == 30.0)
}

@Test func hookConfigDefaultValues() {
    let hook = HookConfig(name: "Test Hook", triggers: [.sessionStarted], action: .shell(command: "echo"))
    #expect(hook.id.isEmpty == false)
    #expect(hook.name == "Test Hook")
    #expect(hook.isEnabled == true)
    #expect(hook.triggers == [.sessionStarted])
    #expect(hook.tools == nil)
    #expect(hook.createdAt <= Date())
    #expect(hook.updatedAt <= Date())
}

@Test func hookConfigTouchUpdatesTimestamp() {
    var hook = HookConfig(name: "Test", triggers: [.sessionStarted], action: .shell(command: "test"))
    let originalUpdatedAt = hook.updatedAt
    hook.createdAt = Date(timeIntervalSinceNow: -100)
    hook.updatedAt = Date(timeIntervalSinceNow: -100)
    hook.touch()
    #expect(hook.updatedAt.timeIntervalSince(originalUpdatedAt) >= 0)
}

@Test func hookConfigWithToolsFilter() {
    let hook = HookConfig(
        name: "Claude Only",
        triggers: [.sessionStarted],
        tools: [.claudeCode],
        action: .shell(command: "test")
    )
    #expect(hook.tools?.contains(.claudeCode) == true)
    #expect(hook.tools?.contains(.codex) == false)
}

@Test func hookConfigIsIdentifiable() {
    let hook = HookConfig(name: "Test", triggers: [], action: .shell(command: "test"))
    #expect(hook.id == hook.id)
}

@Test func hooksConfigDefaultIsEmpty() {
    let config = HooksConfig.default
    #expect(config.version == 1)
    #expect(config.hooks.isEmpty)
}

@Test func hooksConfigCanBeInitializedWithHooks() {
    let hook1 = HookConfig(name: "Hook 1", triggers: [.sessionStarted], action: .shell(command: "a"))
    let hook2 = HookConfig(name: "Hook 2", triggers: [.sessionEnded], action: .webhook(url: "https://test.com"))
    let config = HooksConfig(version: 1, hooks: [hook1, hook2])
    #expect(config.hooks.count == 2)
    #expect(config.hooks[0].name == "Hook 1")
    #expect(config.hooks[1].name == "Hook 2")
}

@Test func hookConfigCodableRoundtrip() throws {
    let original = HookConfig(
        name: "Test Hook",
        isEnabled: true,
        triggers: [.sessionStarted, .runningToIdle],
        tools: [.claudeCode, .codex],
        action: .webhook(url: "https://example.com/hook", method: "POST", headers: ["Auth": "key"])
    )
    
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(original)
    
    let decoder = JSONDecoder()
    let decoded = try decoder.decode(HookConfig.self, from: data)
    
    #expect(decoded.id == original.id)
    #expect(decoded.name == original.name)
    #expect(decoded.isEnabled == original.isEnabled)
    #expect(decoded.triggers == original.triggers)
    #expect(decoded.tools == original.tools)
    #expect(decoded.action.type == original.action.type)
    #expect(decoded.action.webhookURL == original.action.webhookURL)
    #expect(decoded.action.webhookMethod == original.action.webhookMethod)
    #expect(decoded.action.webhookHeaders == original.action.webhookHeaders)
}

@Test func hooksConfigCodableRoundtrip() throws {
    let hook = HookConfig(name: "Hook", triggers: [.sessionStarted], action: .shell(command: "echo"))
    let original = HooksConfig(version: 1, hooks: [hook])
    
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(original)
    
    let decoder = JSONDecoder()
    let decoded = try decoder.decode(HooksConfig.self, from: data)
    
    #expect(decoded.version == original.version)
    #expect(decoded.hooks.count == original.hooks.count)
    #expect(decoded.hooks.first?.name == original.hooks.first?.name)
}