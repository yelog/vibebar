# Agent Task And Approval Design

**Date:** 2026-04-04

**Status:** Confirmed

## Summary

本次设计的目标，是让 VibeBar 对 `Claude Code`、`Codex`、`OpenCode` 三类 Agent 同时具备两类能力：

1. 准确显示“当前正在执行的任务是什么”。
2. 当 Agent 进入等待用户确认或提问阶段时，在菜单栏下拉和刘海下拉中直接显示操作按钮，用户点击后由 VibeBar 自动回写结果并继续执行。

这里的 `Cloud Code` 按 `Claude Code` 理解。

## Goals

- 三个工具都能输出稳定的 `currentTask`。
- `Claude Code` 和 `OpenCode` 支持产品级的内联确认闭环。
- `Codex` 支持产品级的任务识别与等待态展示。
- 统一事件模型、统一存储模型、统一 UI 呈现，不为每个工具做三套状态机。
- 保持与现有 `SessionSnapshot + SessionFileStore + CompositeSessionDetector + VibeBarApp` 架构兼容。

## Non-Goals

- 本次不设计新的主界面信息架构，只在现有 session 行内补交互。
- 本次不承诺 `Codex` 在稳定模式下具备正式的内联确认回写。
- 本次不处理云端同步或跨设备协作，所有状态与交互都保持本机完成。
- 本次不覆盖 `Aider`、`Gemini`、`GitHub Copilot` 等其他工具。

## Current State

### 已有能力

- [`CodexSessionDetector.swift`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/CodexSessionDetector.swift) 已经通过 `session_index.jsonl + rollout-*.jsonl + process/env` 混合链路恢复 `Codex` 的 session、标题和运行状态。
- [`OpenCodeHTTPDetector.swift`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/OpenCodeHTTPDetector.swift) 能通过本地 HTTP API 恢复 `OpenCode` 的 session、title 和粗粒度状态。
- [`TerminalContextResolver.swift`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/TerminalContextResolver.swift) 已经能识别终端 Client、TTY、`tmux/zellij` 等上下文。
- [`NotchContentView.swift`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/NotchContentView.swift) 和 [`StatusItemController.swift`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/StatusItemController.swift) 已能展示 session 列表并触发打开/跳转。

### 当前缺口

- [`AgentEvents.swift`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/AgentEvents.swift) 只有单向 `AgentEvent`，没有结构化的交互请求/响应模型。
- [`main.swift`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarAgent/main.swift) 当前是“收事件即断开”的 socket server，不能挂起连接等待 UI 决策。
- [`SessionFileStore.swift`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/SessionFileStore.swift) 只有会话快照存储，没有待处理交互存储。
- `Claude` 插件 [`plugins/claude-vibebar-plugin/scripts/emit.js`](/Users/yelog/workspace/swift/VibeBar/plugins/claude-vibebar-plugin/scripts/emit.js) 和 `OpenCode` 插件 [`plugins/opencode-vibebar-plugin/index.js`](/Users/yelog/workspace/swift/VibeBar/plugins/opencode-vibebar-plugin/index.js) 现在都是单向上报。
- UI 只支持“打开 session”，不支持“允许 / 拒绝 / 回答”。

## Capability Matrix

| Tool | 当前任务识别 | 等待确认展示 | 内联确认回写 | 备注 |
| --- | --- | --- | --- | --- |
| Claude Code | 可做，需插件补强 | 可做 | 可做 | 依赖 `PermissionRequest` 等 hook |
| OpenCode | 可做，且最强 | 可做 | 可做 | 已有本地 API reply 闭环基础 |
| Codex | 可做，当前已较完整 | 可做 | 稳定版不可承诺 | 官方 hooks 面太窄 |

因此，本次设计把能力分成两个层级：

- 稳定能力：
  - 三个工具都支持 `currentTask`
  - `Claude Code` / `OpenCode` 支持内联确认
  - `Codex` 支持 `awaiting_input` 展示，但不承诺 inline approve
- 实验能力：
  - 可选增加 `Codex` PTY wrapper，尝试做 inline approve

## Approaches

### Approach A: 统一双向 Agent 总线 + 工具专用 bridge

做法：

- 扩展本地 socket 协议，让插件和 hooks 既能发事件，也能发“等待确认请求”。
- `vibebar-agent` 变成一个本地 broker：接请求、落盘、等待 UI 回答、再回包给原始调用方。
- `Claude Code` 与 `OpenCode` 各自实现桥接层，遵守各自协议完成阻塞等待和回写。
- `Codex` 继续使用现有混合检测链路做 `currentTask`，交互回写先不进入稳定交付。

优点：

- 与现有架构兼容，数据路径最清晰。
- `Claude` / `OpenCode` 能做成产品级稳定能力。
- `Codex` 不会被硬塞进脆弱实现。

缺点：

- 需要改协议、改存储、改 UI、改两套插件。

### Approach B: 每个工具各做一套实现

做法：

- `Claude` 在插件里自己等结果。
- `OpenCode` 在插件里自己等结果。
- `Codex` 在检测器里单独做等待态。
- App 侧按工具分支渲染和处理。

优点：

- 初期上手快。

缺点：

- 会把状态、交互、错误处理、超时逻辑复制三遍。
- 后续增加新工具时成本线性增长。

### Approach C: 强行统一到 wrapper / PTY

做法：

- `Claude`、`Codex`、`OpenCode` 全部通过 `vibebar <tool>` wrapper 启动。
- 所有确认都靠 PTY 读屏、提示词匹配和 stdin 注入。

优点：

- 看起来统一。

缺点：

- 最脆弱，最依赖终端文本格式。
- 对 `Codex` 也只能做到实验性质。
- 与现有插件体系方向相反。

## Chosen Approach

选择 **Approach A**。

推荐理由很直接：

- 它能让 `Claude Code` 和 `OpenCode` 形成真正的双向闭环。
- 它不要求把 `Codex` 拉到一个当前官方接入面并不支持的可靠级别。
- 它可以复用现有 `SessionSnapshot`、`SessionFileStore`、`MonitorViewModel`、`NotchContentView`、`StatusItemController`，只是在中间补“交互层”。

## Architecture

### 1. Unified Session Model

在 [`Models.swift`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/Models.swift) 中扩展：

- `SessionSnapshot.currentTask`
- `PendingInteraction`
- `InteractionKind`
- `InteractionOption`
- `InteractionDecision`
- `InteractionDecisionBehavior`

建议结构：

```swift
public struct PendingInteraction: Codable, Identifiable, Sendable, Equatable {
    public var id: String
    public var sessionID: String
    public var tool: ToolKind
    public var kind: InteractionKind
    public var title: String?
    public var message: String
    public var options: [InteractionOption]
    public var allowsFreeText: Bool
    public var requestedAt: Date
    public var expiresAt: Date?
    public var transportContext: [String: String]
}
```

这里的 `transportContext` 是 opaque 字段，用来保存 OpenCode 的 `question_id/permission_id`、Claude 的 hook context 等，不直接参与 UI 逻辑。

### 2. Unified Local Protocol

扩展 [`AgentEvents.swift`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/AgentEvents.swift)，引入统一 envelope：

- `event`
- `interaction_request`
- `interaction_response`

建议 NDJSON 形态：

```json
{"kind":"event","event":{...}}
{"kind":"interaction_request","request":{...}}
{"kind":"interaction_response","request_id":"...","decision":{...}}
```

协议规则：

- 普通状态更新仍走 fire-and-forget。
- 需要等待用户确认时，插件或 hook 保持 socket 连接不关闭，直到 agent 回写 `interaction_response`。
- agent 也允许 App 作为独立客户端发送 `interaction_response`，以便 UI 点击时唤醒原始阻塞连接。

### 3. Interaction Broker

[`main.swift`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarAgent/main.swift) 从单向 receiver 升级为本地 broker：

- 收到 `event` 时继续更新 session 文件。
- 收到 `interaction_request` 时：
  - 写入 `InteractionStore`
  - 缓存一个内存中的 pending responder
  - 保持原连接等待
- 收到 `interaction_response` 时：
  - 找到 pending responder
  - 将决策写回原连接
  - 删除 `InteractionStore` 中对应记录

这要求 `main.swift` 增加：

- 每连接独立处理
- 请求类型路由
- 超时与取消处理

### 4. Persistent Interaction Store

新增 [`InteractionStore.swift`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/InteractionStore.swift)，并在 [`Paths.swift`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/Paths.swift) 中新增：

- `interactionsDirectory`

存储位置建议：

- `~/Library/Application Support/VibeBar/interactions/*.json`

设计原则：

- session 与 interaction 分开存，避免把“当前状态”和“待处理动作”耦死。
- App 重启后仍能恢复待处理确认项。
- 如果 agent 进程已超时退出，UI 也能明确显示“已失效”。

### 5. Current Task Resolution

三个工具都统一输出 `currentTask`，但来源不同：

- `Claude Code`
  - `UserPromptSubmit` 的 prompt
  - `PreToolUse/PostToolUse` 期间可临时覆盖为更具体的 tool label
- `OpenCode`
  - `session.updated` 的 title
  - 无 title 时回退到最后一条 user message
- `Codex`
  - `session_index.jsonl.thread_name`
  - `rollout-*.jsonl.lastUserMessage`
  - 可选用最近 `tool` 或 `agent_reasoning` 事件更新运行中的描述

在合并层中，`currentTask` 比 `title` 优先级更高；`title` 可以保留给 UI 首行展示，而 `currentTask` 用于明确描述当前动作。

### 6. App Join Layer

[`AppModel.swift`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/AppModel.swift) 增加：

- 读取 `InteractionStore`
- 将 `PendingInteraction` 按 `sessionID` 关联到 `SessionSnapshot`
- 暴露新的 action API：
  - `approveInteraction(id:)`
  - `denyInteraction(id:)`
  - `answerInteraction(id:optionID:text:)`

建议把与 agent 通信的发送逻辑收敛到一个新对象，例如：

- [`InteractionActionHandler.swift`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/InteractionActionHandler.swift)

### 7. UI Presentation

[`NotchContentView.swift`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/NotchContentView.swift) 和 [`StatusItemController.swift`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/StatusItemController.swift) 增加交互区：

- `permission`
  - `允许`
  - `拒绝`
- `question`
  - 若有固定 options，直接显示多个按钮
  - 若允许自由文本，先做一个简化输入入口
- `planReview`
  - 首版只显示 `继续` / `返回终端查看`

MVP 中只要求：

- `Allow once`
- `Deny`
- 单选题按钮

自由文本和复杂 plan review 可放第二阶段。

## Tool-Specific Implementation

### Claude Code

现有插件：

- [`plugins/claude-vibebar-plugin/hooks/hooks.json`](/Users/yelog/workspace/swift/VibeBar/plugins/claude-vibebar-plugin/hooks/hooks.json)
- [`plugins/claude-vibebar-plugin/scripts/emit.js`](/Users/yelog/workspace/swift/VibeBar/plugins/claude-vibebar-plugin/scripts/emit.js)

需要升级为：

- 普通 hook 继续发 `event`
- `PermissionRequest` 改为发 `interaction_request`
- 脚本阻塞等待 agent 回包
- 按 Claude hook 协议输出允许/拒绝结果

同时，插件 metadata 里要补：

- prompt
- tool name
- cwd
- tty / terminal env
- 可能的 question/options 信息

### OpenCode

现有插件：

- [`plugins/opencode-vibebar-plugin/index.js`](/Users/yelog/workspace/swift/VibeBar/plugins/opencode-vibebar-plugin/index.js)

需要升级为：

- 保留当前 session/status 事件上报
- 新增 `permission.asked`
- 新增 `question.asked`
- 新增 `sendAndWaitResponse`
- 在收到 UI 响应后，调用 OpenCode 本地 reply API 继续执行

这条链路是最明确、最适合先交付的，因为你本机已有 `Vibe Island` 插件证明这套模式成立。

### Codex

稳定方案：

- 继续使用 [`CodexSessionDetector.swift`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/CodexSessionDetector.swift)
- 通过 `session_index.jsonl + rollout-*.jsonl + hooks` 输出：
  - `currentTask`
  - `awaiting_input`
  - `title`

稳定版不做 inline approve，原因是当前公开 hooks 只有：

- `SessionStart`
- `Stop`
- `UserPromptSubmit`

它缺少可阻塞等待 UI 回包的正式交互面。

实验方案：

- 增加 `vibebar codex -- ...` PTY wrapper
- 解析终端确认提示
- 将 UI 决策写回 stdin

这条路必须被标记为 `experimental`，不能和 `Claude/OpenCode` 放在同一稳定级别。

## Error Handling

- agent 收到 `interaction_request` 后如果在超时时间内没有 UI 决策：
  - 写入默认失败结果
  - 清理 pending request
- UI 对已过期请求点按钮时：
  - 提示“请求已失效”
  - 不再尝试回写
- 插件连接中断时：
  - 删除 interaction 文件
  - session 回退到 `awaiting_input` 或 `idle`，按工具特性决定

## Testing Strategy

### Core Tests

新增或补充：

- `InteractionStore` 读写测试
- 新协议编码/解码测试
- `currentTask` 合并优先级测试
- interaction 超时/清理测试

建议文件：

- [`Tests/VibeBarCoreTests/InteractionStoreTests.swift`](/Users/yelog/workspace/swift/VibeBar/Tests/VibeBarCoreTests/InteractionStoreTests.swift)
- [`Tests/VibeBarCoreTests/AgentMessageTests.swift`](/Users/yelog/workspace/swift/VibeBar/Tests/VibeBarCoreTests/AgentMessageTests.swift)
- [`Tests/VibeBarCoreTests/CompositeSessionDetectorTests.swift`](/Users/yelog/workspace/swift/VibeBar/Tests/VibeBarCoreTests/CompositeSessionDetectorTests.swift)

### App Tests

新增或补充：

- session 行渲染 currentTask 与 interaction button 的格式化测试
- 点击按钮后的 action dispatch 测试

建议文件：

- [`Tests/VibeBarAppTests/SessionDisplayFormatterTests.swift`](/Users/yelog/workspace/swift/VibeBar/Tests/VibeBarAppTests/SessionDisplayFormatterTests.swift)
- [`Tests/VibeBarAppTests/InteractionActionHandlerTests.swift`](/Users/yelog/workspace/swift/VibeBar/Tests/VibeBarAppTests/InteractionActionHandlerTests.swift)

## Rollout

建议按四个阶段交付：

1. 统一模型、协议、存储。
2. 打通 `OpenCode` 内联确认。
3. 打通 `Claude Code` 内联确认。
4. 补 `Codex` 的 `currentTask + awaiting_input` 完整展示；若用户坚持，再加实验性 wrapper。

## Decision

最终方案是：

- 用统一双向 agent 总线承载交互。
- `Claude Code` 和 `OpenCode` 做正式的 inline approve。
- `Codex` 保持稳定的任务识别与等待态展示；内联确认仅作为后续实验能力。

这个边界是必要的。否则实现上看起来统一，交付质量反而会被 `Codex` 这一条脆弱链路拖垮。
