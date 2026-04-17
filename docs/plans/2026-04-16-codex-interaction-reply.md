# Codex Interaction Reply Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 为 VibeBar 打通 Codex CLI hooks 的全量交互回传闭环，支持权限审批、AskUserQuestion 单题/多题回答，以及 plan review 审核与批注。

**Architecture:** 继续沿用现有 `PendingInteraction + AgentEnvelope + vibebar-agent + InteractionStore + App UI` 主链路，只补 `CodexInteractionBridge`、阻塞式 `codex-hook`、以及更精确的 broker 生命周期管理。非交互 hook 仍走 fire-and-forget `AgentEvent`，交互 hook 改为 `interaction_request -> wait -> interaction_response -> hookSpecificOutput` 的同步回包路径。

**Tech Stack:** Swift 6.2, Foundation, Darwin, AppKit, SwiftUI, Unix Domain Socket, Swift Testing, macOS 13+

---

### Task 1: Extend Interaction Models For Structured Codex Questions

**Files:**
- Modify: `Sources/VibeBarCore/Models.swift`
- Test: `Tests/VibeBarCoreTests/AgentMessageTests.swift`

**Step 1: Write the failing test**

在 `AgentMessageTests.swift` 增加新断言，覆盖：

- `PendingInteraction` 可以编码/解码结构化 prompt 列表
- 多题 `AskUserQuestion` 能保留 `prompt.id`、`title`、`options`、`allowsFreeText`、`allowsMultipleSelection`
- 单题 permission / planReview 不受影响

示例测试数据：

```swift
let interaction = PendingInteraction(
    id: "interaction-codex-question",
    sessionID: "plugin-codex-hook-sess-1",
    tool: .codex,
    kind: .question,
    title: "需要用户回答",
    message: "请回答以下问题",
    options: [],
    allowsFreeText: false,
    requestedAt: Date(timeIntervalSince1970: 1_700_000_000),
    transportContext: ["hook_event_name": "PermissionRequest"],
    prompts: [
        InteractionPrompt(
            id: "工作模式",
            title: "你希望我接下来以哪种方式协作？",
            options: [
                InteractionOption(id: "direct", label: "直接执行"),
                InteractionOption(id: "plan", label: "先给方案"),
            ],
            allowsFreeText: false,
            allowsMultipleSelection: false
        )
    ]
)
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter AgentMessageTests`

Expected: FAIL，因为 `PendingInteraction` 还没有结构化 prompt 字段或相关类型。

**Step 3: Write minimal implementation**

在 `Models.swift` 中新增最小结构：

```swift
public struct InteractionPrompt: Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var options: [InteractionOption]
    public var allowsFreeText: Bool
    public var allowsMultipleSelection: Bool
    public var metadata: [String: String]
}
```

并在 `PendingInteraction` 中新增：

```swift
public var prompts: [InteractionPrompt]
```

要求：

- `prompts` 默认空数组
- 旧交互 payload 不需要迁移逻辑即可解码
- `displayOptions` 对旧 permission 行为保持不变

**Step 4: Run test to verify it passes**

Run: `swift test --filter AgentMessageTests`

Expected: PASS

**Step 5: Commit**

```bash
git add Sources/VibeBarCore/Models.swift Tests/VibeBarCoreTests/AgentMessageTests.swift
git commit -m "feat(core): add structured interaction prompts"
```

### Task 2: Add Codex Interaction Bridge

**Files:**
- Create: `Sources/VibeBarCore/CodexInteractionBridge.swift`
- Test: `Tests/VibeBarCoreTests/CodexInteractionBridgeTests.swift`

**Step 1: Write the failing test**

新增 `CodexInteractionBridgeTests.swift`，覆盖：

- 普通 `PermissionRequest` -> `PendingInteraction(kind: .permission)`
- `tool_name = AskUserQuestion` 的 `PermissionRequest` -> `PendingInteraction(kind: .question)`
- 多题 `questions` 能映射为多个 `InteractionPrompt`
- plan review payload -> `PendingInteraction(kind: .planReview)`
- `InteractionDecision(behavior: .allow)` -> `hookSpecificOutput.decision.behavior = allow`
- 多题回答 -> `updatedInput.answers`
- timeout / disconnect 的默认 decision 能映射为保守 deny

示例 API：

```swift
enum CodexInteractionBridge {
    static func interaction(from data: Data, context: CodexHookBridgeContext) -> PendingInteraction?
    static func responseData(for interaction: PendingInteraction, decision: InteractionDecision?) -> Data
    static func defaultDecision(for interaction: PendingInteraction, reason: String) -> InteractionDecision?
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter CodexInteractionBridgeTests`

Expected: FAIL，因为 bridge 文件尚不存在。

**Step 3: Write minimal implementation**

实现要点：

- 从 `hook_event_name`、`tool_name`、`tool_input` 识别 permission / question / planReview
- 为多题 `AskUserQuestion` 生成稳定 answer key：
  - 先用 header
  - header 重复时追加 `_2`、`_3`
  - header 缺失时回退 `answer_1`、`answer_2`
- 保留 `transportContext` 中的原始关键字段，至少包含：
  - `hook_event_name`
  - `tool_name`
  - `session_id`
  - `cwd`
  - `request_kind`
- 输出 reply JSON 时对齐 `Codex` 协议：

```swift
[
    "hookSpecificOutput": [
        "hookEventName": "PermissionRequest",
        "decision": [
            "behavior": "allow",
            "updatedInput": ["answers": answers],
        ],
    ],
]
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter CodexInteractionBridgeTests`

Expected: PASS

**Step 5: Commit**

```bash
git add Sources/VibeBarCore/CodexInteractionBridge.swift Tests/VibeBarCoreTests/CodexInteractionBridgeTests.swift
git commit -m "feat(codex): add interaction bridge"
```

### Task 3: Add A Shared Agent Socket Client With Request/Reply Support

**Files:**
- Create: `Sources/VibeBarCore/AgentSocketClient.swift`
- Modify: `Sources/VibeBarApp/InteractionActionHandler.swift`
- Test: `Tests/VibeBarCoreTests/AgentSocketClientTests.swift`

**Step 1: Write the failing test**

新增 `AgentSocketClientTests.swift`，覆盖：

- 能发送 `AgentEnvelope(kind: .event)`
- 能发送 `AgentEnvelope(kind: .interactionRequest)` 并阻塞等待 `interactionResponse`
- 读到 `interaction_response` 后能正确 decode `requestID` 与 `decision`

建议用临时 Unix socket server 做集成测试。

示例 API：

```swift
public struct AgentSocketClient {
    public func send(_ envelope: AgentEnvelope) -> Bool
    public func sendAndWait(_ envelope: AgentEnvelope, timeout: TimeInterval) -> AgentInteractionResponse?
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter AgentSocketClientTests`

Expected: FAIL，因为共享 socket client 尚不存在。

**Step 3: Write minimal implementation**

- 把 `InteractionActionHandler.send(...)` 里的 Unix socket 逻辑迁到 `AgentSocketClient`
- 提供两种入口：
  - fire-and-forget
  - send-and-wait
- `InteractionActionHandler` 改为依赖 `AgentSocketClient.send(...)`
- 保持 `InteractionActionHandler` 的公开行为不变

**Step 4: Run test to verify it passes**

Run: `swift test --filter AgentSocketClientTests`

Expected: PASS

**Step 5: Commit**

```bash
git add Sources/VibeBarCore/AgentSocketClient.swift Sources/VibeBarApp/InteractionActionHandler.swift Tests/VibeBarCoreTests/AgentSocketClientTests.swift
git commit -m "feat(agent): add socket request reply client"
```

### Task 4: Extract And Test Session-Aware Interaction Broker State

**Files:**
- Create: `Sources/VibeBarCore/InteractionBrokerState.swift`
- Modify: `Sources/VibeBarAgent/main.swift`
- Test: `Tests/VibeBarCoreTests/InteractionBrokerStateTests.swift`

**Step 1: Write the failing test**

新增 `InteractionBrokerStateTests.swift`，覆盖：

- 同一 `sessionID` 新 interaction 到来时，旧 interaction 会被 drain
- timeout 时生成保守 deny 响应
- caller 断连时 interaction 被清理
- 晚到的 `interaction_response` 不会重新挂回状态

示例 API：

```swift
struct InteractionBrokerState {
    mutating func begin(_ interaction: PendingInteraction) -> PendingInteraction?
    mutating func resolve(requestID: String, response: AgentInteractionResponse) -> PendingInteraction?
    mutating func timeout(requestID: String) -> PendingInteraction?
    mutating func disconnect(requestID: String) -> PendingInteraction?
}
```

`begin(_:)` 返回需要被 drain 的旧 interaction，便于 agent 统一清理与写回。

**Step 2: Run test to verify it fails**

Run: `swift test --filter InteractionBrokerStateTests`

Expected: FAIL，因为 broker state 尚不存在。

**Step 3: Write minimal implementation**

- 把 `main.swift` 中与 `pendingResponders`、`earlyInteractionResponses`、同 session 覆盖相关的状态机抽到 core
- `main.swift` 只保留 socket I/O、store 读写、以及“把 state 决策翻译成具体清理动作”
- 对 `Codex` 默认 drain 行为使用 `CodexInteractionBridge.defaultDecision(...)`

**Step 4: Run test to verify it passes**

Run: `swift test --filter InteractionBrokerStateTests`

Expected: PASS

**Step 5: Commit**

```bash
git add Sources/VibeBarCore/InteractionBrokerState.swift Sources/VibeBarAgent/main.swift Tests/VibeBarCoreTests/InteractionBrokerStateTests.swift
git commit -m "feat(agent): add session-aware interaction broker state"
```

### Task 5: Wire Blocking Codex Hook Replies End To End

**Files:**
- Modify: `Sources/VibeBarCore/CodexHookInstaller.swift`
- Modify: `Sources/VibeBarCLI/main.swift`
- Modify: `Tests/VibeBarCoreTests/CodexHookInstallerTests.swift`
- Modify: `Tests/VibeBarCoreTests/CodexHookEventBridgeTests.swift`

**Step 1: Write the failing test**

扩展现有测试，覆盖：

- `CodexHookInstaller` 会安装 `PermissionRequest` hook，且 timeout 远大于普通状态 hook
- `handleCodexHookCommand` 对交互型 hook 不再仅发送 `AgentEvent`
- 收到 `interaction_response` 后会把 `hookSpecificOutput` 写到 stdout

建议新增至少一个 focused test，验证安装后的事件清单包含：

```swift
["SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop", "PermissionRequest"]
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter CodexHookInstallerTests`

Expected: FAIL，因为当前 installer 还没有 `PermissionRequest`，且 `codex-hook` 仍是 fire-and-forget。

**Step 3: Write minimal implementation**

- 给 `CodexHookInstaller` 增加 `PermissionRequest`，使用长 timeout
- 在 `main.swift` 的 `handleCodexHookCommand` 中新增分支：
  - 若 `CodexInteractionBridge.interaction(...) != nil`
  - 则用 `AgentSocketClient.sendAndWait(...)` 发 `interaction_request`
  - 拿到 `AgentInteractionResponse`
  - 调 `CodexInteractionBridge.responseData(...)`
  - 将 JSON 写入 stdout
- 非交互事件继续使用现有 `CodexHookEventBridge`

示例伪代码：

```swift
if let interaction = CodexInteractionBridge.interaction(from: input, context: context) {
    let response = socketClient.sendAndWait(
        AgentEnvelope(kind: .interactionRequest, request: interaction),
        timeout: interaction.expiresAt?.timeIntervalSinceNow ?? 86400
    )
    let reply = CodexInteractionBridge.responseData(for: interaction, decision: response?.decision)
    FileHandle.standardOutput.write(reply)
    return 0
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter CodexHookInstallerTests`

Expected: PASS

**Step 5: Commit**

```bash
git add Sources/VibeBarCore/CodexHookInstaller.swift Sources/VibeBarCLI/main.swift Tests/VibeBarCoreTests/CodexHookInstallerTests.swift Tests/VibeBarCoreTests/CodexHookEventBridgeTests.swift
git commit -m "feat(codex): add blocking hook replies"
```

### Task 6: Add Codex-Safe Interaction UI For Buttons, Free Text, And Multi-Question Answers

**Files:**
- Modify: `Sources/VibeBarApp/AppModel.swift`
- Modify: `Sources/VibeBarApp/SessionDisplayFormatter.swift`
- Modify: `Sources/VibeBarApp/NotchExpandedBodyView.swift`
- Modify: `Sources/VibeBarApp/StatusItemController.swift`
- Create: `Tests/VibeBarAppTests/InteractionActionHandlerTests.swift`
- Modify: `Tests/VibeBarAppTests/SessionDisplayFormatterTests.swift`

**Step 1: Write the failing test**

补 UI/formatter tests，覆盖：

- `planReview` 仍显示继续 / 拒绝
- `Codex` 多题 question 会暴露 structured prompts，而不是退化成单个按钮条
- `allowsFreeText == true` 时展示输入框与提交动作
- `InteractionActionHandler` 对 `tool == .codex` 不会尝试走 OpenCode HTTP reply

示例测试数据：

```swift
let interaction = PendingInteraction(
    id: "codex-plan",
    sessionID: "plugin-codex-hook-sess-1",
    tool: .codex,
    kind: .planReview,
    title: "计划审查",
    message: "是否继续按这个计划执行？",
    allowsFreeText: true,
    requestedAt: Date(),
    prompts: [
        InteractionPrompt(id: "review", title: "补充意见", options: [], allowsFreeText: true, allowsMultipleSelection: false)
    ]
)
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter SessionDisplayFormatterTests`

Expected: FAIL，因为当前 UI 只有按钮条，没有 structured prompt 与自由文本入口。

**Step 3: Write minimal implementation**

- `SessionDisplayFormatter` 只保留按钮 label/role 逻辑，不承担多题答案采集
- 在 `NotchExpandedBodyView` 和 `StatusItemController` 中增加最小交互区：
  - 单题按钮继续沿用现有 button strip
  - 多题 / 自由文本场景显示输入控件与提交按钮
- `AppModel.resolveInteraction(...)` 继续接受统一 `InteractionDecision`
- 若 `CodexInteractionBridge` 需要 richer metadata，UI 在 `decision.metadata` 中写入：
  - `prompt_id`
  - `comment`
  - `selected_values`

**Step 4: Run test to verify it passes**

Run: `swift test --filter SessionDisplayFormatterTests`

Expected: PASS

Run: `swift test --filter InteractionActionHandlerTests`

Expected: PASS

**Step 5: Commit**

```bash
git add Sources/VibeBarApp/AppModel.swift Sources/VibeBarApp/SessionDisplayFormatter.swift Sources/VibeBarApp/NotchExpandedBodyView.swift Sources/VibeBarApp/StatusItemController.swift Tests/VibeBarAppTests/InteractionActionHandlerTests.swift Tests/VibeBarAppTests/SessionDisplayFormatterTests.swift
git commit -m "feat(app): add codex interaction reply UI"
```

### Task 7: Validate End To End And Update User-Facing Docs

**Files:**
- Modify: `README.md`
- Modify: `AGENTS.md`
- Modify: `docs/plans/2026-04-16-codex-interaction-reply-design.md`

**Step 1: Add focused documentation updates**

- 在 `README.md` 补充 `Codex` hook 的交互能力与限制
- 在 `AGENTS.md` 补充 `Codex` hooks 事件清单与手工验证方式
- 如果实施中协议细节有调整，同步回写设计文档

**Step 2: Run focused and full tests**

Run: `swift test --filter AgentMessageTests`
Expected: PASS

Run: `swift test --filter CodexInteractionBridgeTests`
Expected: PASS

Run: `swift test --filter AgentSocketClientTests`
Expected: PASS

Run: `swift test --filter InteractionBrokerStateTests`
Expected: PASS

Run: `swift test --filter CodexHookInstallerTests`
Expected: PASS

Run: `swift test --filter SessionDisplayFormatterTests`
Expected: PASS

Run: `swift test`
Expected: PASS

Run: `swift build`
Expected: PASS

**Step 3: Manual verification**

Run:

```bash
swift run vibebar-agent --verbose
swift run VibeBarApp
```

Expected:

- `PermissionRequest` 在 VibeBar 内可允许/拒绝
- `AskUserQuestion` 单题可选择或文本回答
- `AskUserQuestion` 多题可提交多组 answers
- `PlanReview` 可继续 / 拒绝 / 附加意见
- timeout / disconnect 时 Codex 收到保守拒绝或空安全回复

**Step 4: Commit**

```bash
git add README.md AGENTS.md docs/plans/2026-04-16-codex-interaction-reply-design.md
git commit -m "docs: describe codex interaction reply flow"
```

Plan complete and saved to `docs/plans/2026-04-16-codex-interaction-reply.md`. Two execution options:

**1. Subagent-Driven (this session)** - 我分任务逐个实现、每步验证、在关键节点做代码审查。

**2. Parallel Session (separate)** - 你开一个新会话，按这份计划用 `executing-plans` 批量推进。

**Which approach?**
