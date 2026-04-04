# Agent Task And Approval Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 为 VibeBar 增加统一的当前任务识别与内联确认架构，让 Claude Code、OpenCode、Codex 都能稳定显示 `currentTask`，并让 Claude Code 与 OpenCode 支持在菜单栏 / 刘海 UI 中直接确认后继续执行。

**Architecture:** 以现有 `SessionSnapshot + SessionFileStore + CompositeSessionDetector + VibeBarApp` 为骨架，新增独立的 `PendingInteraction` 模型、双向 agent 协议、本地 `InteractionStore` 与 UI action handler。Claude 与 OpenCode 通过插件桥接接入双向交互，Codex 继续使用 session 文件检测链路输出 `currentTask` 与等待态，并把内联确认保留为实验性扩展。

**Tech Stack:** Swift 6.2、AppKit、SwiftUI、Foundation、Unix Domain Socket、Node.js 插件脚本、Swift Package Manager。

---

### Task 1: 扩展核心模型与路径

**Files:**
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/Models.swift`
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/Paths.swift`
- Test: `/Users/yelog/workspace/swift/VibeBar/Tests/VibeBarCoreTests/AgentMessageTests.swift`

**Step 1: 写失败测试**

为 `PendingInteraction`、`InteractionDecision`、`currentTask` 的编码/解码和默认值写测试，覆盖：

- `SessionSnapshot` 能编码 `currentTask`
- `PendingInteraction` 能保留 `options`
- `InteractionDecision` 能表达 `allow/deny/select/text`

**Step 2: 运行测试确认失败**

Run: `swift test --filter AgentMessageTests`

Expected: 编译失败，提示缺少 `PendingInteraction` 或相关字段。

**Step 3: 最小实现模型与路径**

在 `Models.swift` 增加：

```swift
public enum InteractionKind: String, Codable, Sendable {
    case permission
    case question
    case planReview = "plan_review"
}
```

并在 `SessionSnapshot` 中加入：

```swift
public var currentTask: String?
public var pendingInteractionID: String?
```

在 `Paths.swift` 中新增：

```swift
public static let interactionsFolderName = "interactions"
public static var interactionsDirectory: URL { ... }
```

**Step 4: 运行测试确认通过**

Run: `swift test --filter AgentMessageTests`

Expected: PASS

**Step 5: Commit**

```bash
git add Sources/VibeBarCore/Models.swift Sources/VibeBarCore/Paths.swift Tests/VibeBarCoreTests/AgentMessageTests.swift
git commit -m "feat(core): add interaction models"
```

### Task 2: 增加 InteractionStore

**Files:**
- Create: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/InteractionStore.swift`
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/Paths.swift`
- Test: `/Users/yelog/workspace/swift/VibeBar/Tests/VibeBarCoreTests/InteractionStoreTests.swift`

**Step 1: 写失败测试**

覆盖：

- 写入单个 interaction
- 读取全部 interaction
- 删除 interaction
- 清理过期 interaction

**Step 2: 运行测试确认失败**

Run: `swift test --filter InteractionStoreTests`

Expected: 编译失败，提示 `InteractionStore` 不存在。

**Step 3: 实现最小存储**

实现与 `SessionFileStore` 一致的原子写入风格：

```swift
public struct InteractionStore {
    public func write(_ interaction: PendingInteraction) throws { ... }
    public func loadAll() -> [PendingInteraction] { ... }
    public func delete(id: String) { ... }
    public func cleanupExpired(now: Date) { ... }
}
```

**Step 4: 运行测试确认通过**

Run: `swift test --filter InteractionStoreTests`

Expected: PASS

**Step 5: Commit**

```bash
git add Sources/VibeBarCore/InteractionStore.swift Sources/VibeBarCore/Paths.swift Tests/VibeBarCoreTests/InteractionStoreTests.swift
git commit -m "feat(core): add interaction store"
```

### Task 3: 升级本地 agent 协议

**Files:**
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/AgentEvents.swift`
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarAgent/main.swift`
- Test: `/Users/yelog/workspace/swift/VibeBar/Tests/VibeBarCoreTests/AgentMessageTests.swift`

**Step 1: 写失败测试**

增加协议测试，覆盖：

- `event` envelope 解码
- `interaction_request` envelope 解码
- `interaction_response` envelope 解码

**Step 2: 运行测试确认失败**

Run: `swift test --filter AgentMessageTests`

Expected: FAIL，无法解码新的消息种类。

**Step 3: 实现协议与 broker 骨架**

在 `AgentEvents.swift` 中新增：

```swift
public enum AgentEnvelopeKind: String, Codable, Sendable {
    case event
    case interactionRequest = "interaction_request"
    case interactionResponse = "interaction_response"
}
```

在 `main.swift` 中：

- 把 `handleClient(fd:)` 改成逐消息路由
- 引入 pending responder 映射
- 收到 `interaction_request` 时写入 `InteractionStore`
- 收到 `interaction_response` 时唤醒原请求方

**Step 4: 运行核心测试**

Run: `swift test --filter AgentMessageTests`

Expected: PASS

**Step 5: 做一次最小集成验证**

Run: `swift build`

Expected: `Build complete!`

**Step 6: Commit**

```bash
git add Sources/VibeBarCore/AgentEvents.swift Sources/VibeBarAgent/main.swift Tests/VibeBarCoreTests/AgentMessageTests.swift
git commit -m "feat(agent): add bidirectional interaction protocol"
```

### Task 4: 把 currentTask 合并进检测链路

**Files:**
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/CodexSessionDetector.swift`
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/OpenCodeHTTPDetector.swift`
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/CompositeSessionDetector.swift`
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarAgent/main.swift`
- Test: `/Users/yelog/workspace/swift/VibeBar/Tests/VibeBarCoreTests/CodexSessionDetectorTests.swift`
- Test: `/Users/yelog/workspace/swift/VibeBar/Tests/VibeBarCoreTests/CompositeSessionDetectorTests.swift`

**Step 1: 写失败测试**

覆盖：

- `Codex` 优先取 `thread_name`，回退到 `lastUserMessage`
- `OpenCode` 优先取 `title`，回退到 user prompt
- plugin 事件带来的 `currentTask` 不应被弱来源覆盖

**Step 2: 运行测试确认失败**

Run: `swift test --filter CodexSessionDetectorTests`

Expected: FAIL，`currentTask` 断言不成立。

**Step 3: 实现最小变更**

- `CodexSessionDetector` 输出 `currentTask`
- `OpenCodeHTTPDetector` 输出 `currentTask`
- `main.swift` 从 plugin metadata 中提取 prompt/title
- `CompositeSessionDetector` 合并 `currentTask`

**Step 4: 运行测试确认通过**

Run: `swift test --filter CodexSessionDetectorTests`

Expected: PASS

**Step 5: 回归合并测试**

Run: `swift test --filter CompositeSessionDetectorTests`

Expected: PASS

**Step 6: Commit**

```bash
git add Sources/VibeBarCore/CodexSessionDetector.swift Sources/VibeBarCore/OpenCodeHTTPDetector.swift Sources/VibeBarCore/CompositeSessionDetector.swift Sources/VibeBarAgent/main.swift Tests/VibeBarCoreTests/CodexSessionDetectorTests.swift Tests/VibeBarCoreTests/CompositeSessionDetectorTests.swift
git commit -m "feat(session): track current task across detectors"
```

### Task 5: 打通 OpenCode 内联确认

**Files:**
- Modify: `/Users/yelog/workspace/swift/VibeBar/plugins/opencode-vibebar-plugin/index.js`
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarAgent/main.swift`
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/AgentEvents.swift`
- Test: `/Users/yelog/workspace/swift/VibeBar/Tests/VibeBarCoreTests/AgentMessageTests.swift`

**Step 1: 写失败测试**

至少补协议层测试，覆盖 `interaction_request` 中的：

- `permission`
- `question`
- `options`
- `transportContext`

**Step 2: 运行测试确认失败**

Run: `swift test --filter AgentMessageTests`

Expected: FAIL，缺少 `PendingInteraction` 字段或协议映射。

**Step 3: 实现插件阻塞回写**

在 `plugins/opencode-vibebar-plugin/index.js` 中新增：

- `sendAndWaitResponse(...)`
- `permission.asked`
- `question.asked`
- 在收到 UI 决策后调用本地 reply API

保持普通心跳与 status 上报不变。

**Step 4: 运行构建与静态验证**

Run: `swift build`

Expected: `Build complete!`

**Step 5: 手动集成验证**

Run:

```bash
swift run vibebar-agent --verbose
swift run VibeBarApp
```

Expected:

- OpenCode 发起确认时，菜单栏或刘海出现按钮
- 点击后 OpenCode 会继续执行

**Step 6: Commit**

```bash
git add plugins/opencode-vibebar-plugin/index.js Sources/VibeBarAgent/main.swift Sources/VibeBarCore/AgentEvents.swift Tests/VibeBarCoreTests/AgentMessageTests.swift
git commit -m "feat(opencode): add interactive approval bridge"
```

### Task 6: 打通 Claude Code 内联确认

**Files:**
- Modify: `/Users/yelog/workspace/swift/VibeBar/plugins/claude-vibebar-plugin/scripts/emit.js`
- Modify: `/Users/yelog/workspace/swift/VibeBar/plugins/claude-vibebar-plugin/hooks/hooks.json`
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarAgent/main.swift`
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/PluginDetector.swift`

**Step 1: 写失败测试**

用现有协议测试补充 Claude payload 场景，至少覆盖：

- `PermissionRequest` -> `interaction_request`
- `UserPromptSubmit` -> `currentTask`

**Step 2: 运行测试确认失败**

Run: `swift test --filter AgentMessageTests`

Expected: FAIL，Claude 交互消息缺字段。

**Step 3: 实现阻塞 hook bridge**

在 `emit.js` 中增加：

- 统一 envelope 发送
- `PermissionRequest` 时等待 agent 响应
- 按 Claude hook 协议输出 allow/deny

`hooks.json` 保持现有 hook 覆盖范围，但对交互型 hook 使用新的 bridge 行为。

**Step 4: 运行构建**

Run: `swift build`

Expected: `Build complete!`

**Step 5: 手动集成验证**

Run:

```bash
swift run vibebar-agent --verbose
swift run VibeBarApp
claude --plugin-dir /Users/yelog/workspace/swift/VibeBar/plugins/claude-vibebar-plugin
```

Expected:

- Claude 发起权限确认时，VibeBar 显示允许/拒绝按钮
- 点击后 Claude 继续执行或拒绝

**Step 6: Commit**

```bash
git add plugins/claude-vibebar-plugin/scripts/emit.js plugins/claude-vibebar-plugin/hooks/hooks.json Sources/VibeBarAgent/main.swift Sources/VibeBarCore/PluginDetector.swift
git commit -m "feat(claude): add interactive hook approvals"
```

### Task 7: 在 App 中展示并处理交互

**Files:**
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/AppModel.swift`
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/NotchContentView.swift`
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/StatusItemController.swift`
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/SessionDisplayFormatter.swift`
- Create: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/InteractionActionHandler.swift`
- Test: `/Users/yelog/workspace/swift/VibeBar/Tests/VibeBarAppTests/SessionDisplayFormatterTests.swift`
- Test: `/Users/yelog/workspace/swift/VibeBar/Tests/VibeBarAppTests/InteractionActionHandlerTests.swift`

**Step 1: 写失败测试**

覆盖：

- session 行在有 `PendingInteraction` 时显示按钮或动作标识
- 点击 `允许/拒绝` 会发出正确 decision
- `question` 类型能渲染选项按钮

**Step 2: 运行测试确认失败**

Run: `swift test --filter SessionDisplayFormatterTests`

Expected: FAIL，缺少 interaction 展示字段。

**Step 3: 实现最小 UI**

- `AppModel` 读取 `InteractionStore`
- `InteractionActionHandler` 负责向 agent 发送 `interaction_response`
- `NotchContentView` 与 `StatusItemController` 增加按钮
- `SessionDisplayFormatter` 输出 `currentTask` 和 interaction label

**Step 4: 运行测试确认通过**

Run: `swift test --filter SessionDisplayFormatterTests`

Expected: PASS

**Step 5: 全量测试**

Run: `swift test`

Expected: 全部 PASS

**Step 6: Commit**

```bash
git add Sources/VibeBarApp/AppModel.swift Sources/VibeBarApp/NotchContentView.swift Sources/VibeBarApp/StatusItemController.swift Sources/VibeBarApp/SessionDisplayFormatter.swift Sources/VibeBarApp/InteractionActionHandler.swift Tests/VibeBarAppTests/SessionDisplayFormatterTests.swift Tests/VibeBarAppTests/InteractionActionHandlerTests.swift
git commit -m "feat(app): surface and resolve pending interactions"
```

### Task 8: 收尾 Codex 能力边界与文档

**Files:**
- Modify: `/Users/yelog/workspace/swift/VibeBar/README.md`
- Modify: `/Users/yelog/workspace/swift/VibeBar/CLAUDE.md`
- Modify: `/Users/yelog/workspace/swift/VibeBar/docs/plans/2026-04-04-agent-interactions-design.md`

**Step 1: 补文档**

明确说明：

- `Claude Code` / `OpenCode` 支持 inline approve
- `Codex` 稳定版支持 `currentTask + awaiting_input`
- `Codex` inline approve 属于实验能力

**Step 2: 运行最终验证**

Run:

```bash
swift build
swift test
```

Expected:

- `Build complete!`
- 测试全部通过

**Step 3: Commit**

```bash
git add README.md CLAUDE.md docs/plans/2026-04-04-agent-interactions-design.md
git commit -m "docs: document agent interaction support matrix"
```

Plan complete and saved to `docs/plans/2026-04-04-agent-interactions.md`. Two execution options:

**1. Subagent-Driven (this session)** - 我在当前会话按任务逐步实现、逐步回归。

**2. Parallel Session (separate)** - 你开一个新会话，按这份计划并行执行。

如果你要继续，我建议选 **1**，因为这次改动会同时触碰 Core、Agent、App 和两套插件。
