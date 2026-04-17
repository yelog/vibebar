# Codex Interaction Reply Design

**Date:** 2026-04-16

**Status:** Confirmed

## Implementation Notes (2026-04-17)

- `PendingInteraction` 已加入 `prompts: [InteractionPrompt]`，兼容旧 payload 缺省解码。
- `CodexInteractionBridge` 已落地在 core，负责：
  - `PermissionRequest` / `AskUserQuestion` / `PlanReview` 识别
  - `InteractionDecision -> hookSpecificOutput` 映射
  - 多题 answer key 去重，当前 UI 通过 `answer.<stable-key>` metadata 回填答案
- `AgentSocketClient` 已抽到 core，统一承担 fire-and-forget 和 request/reply 两条 Unix socket 路径。
- `InteractionBrokerState` 已抽到 core，用于同 session 交互覆盖、timeout / disconnect 清理，以及 late response 丢弃判定。
- UI 复用了统一的 `SessionInteractionContentView`：
  - 旧单题按钮条保持不变
  - Codex 多题 / 自由文本交互改为结构化输入区
  - plan review 继续保留 `继续 / 拒绝` 按钮，并可附带评论 metadata

## Summary

本次设计的目标，是让 `VibeBar` 在已经具备 `Codex` 实时状态监控的基础上，继续打通 `Codex` 的交互回传闭环，让菜单栏和刘海 UI 可以直接完成：

1. `PermissionRequest` 权限审批
2. `AskUserQuestion` 单题与多题回答
3. `PlanReview` 审核与批注

核心原则是复用现有的 `PendingInteraction + AgentEnvelope + vibebar-agent + InteractionStore + AppModel + InteractionActionHandler` 架构，不引入第二套专门给 `Codex` 的 UI 或状态机。

## Goals

- `Codex` 的权限、问题、plan review 都能在 `VibeBar` UI 中直接处理。
- `Codex` hooks 在需要交互时保持同步阻塞，直到 `VibeBar` 返回正式回复。
- 继续沿用统一的 `PendingInteraction` 模型，而不是为 `Codex` 另建一套请求/响应类型。
- 在超时、断连、重复上报、多 session 并存时保持保守且可预测的行为。
- 保持与现有 `Codex` 实时状态链路兼容，不回退到 PTY 注入或 UI 文本匹配方案。

## Non-Goals

- 本次不做 `Codex Desktop` 的独立交互协议支持，先只覆盖 `Codex CLI hooks`。
- 本次不做跨重启恢复“仍可继续回复”的挂起 hook 连接；进程断了就按保守策略关闭交互。
- 本次不做新的 `Codex` 专属 UI，继续复用现有 session 行内交互样式。
- 本次不做复杂的长期权限规则编辑界面；如果 hook 支持 `always allow`，只做最小协议映射。
- 本次不重构 `Claude` / `OpenCode` 的现有交互体系，除非为 `Codex` 接入所需的最小抽取确有必要。

## Current State

### 已有能力

- [`CodexHookInstaller.swift`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/CodexHookInstaller.swift) 已经能为 `Codex` 安装实时 hooks，并确保 `codex_hooks = true`。
- [`CodexHookEventBridge.swift`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/CodexHookEventBridge.swift) 已经能把非交互 hook 事件映射为 `AgentEvent`。
- [`vibebar-agent`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarAgent/main.swift) 已支持 `interaction_request` / `interaction_response` 双向 envelope，并维护 `InteractionStore`。
- [`PendingInteraction`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/Models.swift) 与 [`InteractionActionHandler.swift`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/InteractionActionHandler.swift) 已服务于 `OpenCode` / `Claude` 的交互闭环。
- [`SessionDisplayFormatter.swift`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/SessionDisplayFormatter.swift) 已支持 `permission`、`question`、`planReview` 三类交互按钮生成。

### 当前缺口

- `vibebar codex-hook` 目前只处理 fire-and-forget 事件，无法对交互型 hook 保持连接并同步回包。
- 缺少一个把 `Codex` hook JSON 映射到 `PendingInteraction` 的专用 bridge。
- 缺少一个把 `InteractionDecision` 映射回 `Codex hookSpecificOutput` JSON 的专用 bridge。
- `vibebar-agent` 目前会等待通用 `interaction_response`，但还没有 `Codex` 专属的保守 drain / timeout / disconnect 策略。
- `InteractionActionHandler` 当前只对 `OpenCode` 做直接 reply 特判，没有 `Codex` 的 reply 适配分支。

## Approaches

### Approach A: Synchronous Codex Hook Bridge On Top Of Unified Interaction Bus

做法：

- `vibebar codex-hook` 识别交互型 hook 事件。
- 将其转成统一 `PendingInteraction` 发给 `vibebar-agent`。
- 阻塞等待 `interaction_response`。
- 再把结果转回 `Codex` 需要的 `hookSpecificOutput` JSON 输出到 stdout。

优点：

- 与 `CodeIsland` 的工作方式一致，符合 `Codex` hook 的同步回复模型。
- 可以完整覆盖权限、问题和 plan review。
- 复用 `VibeBar` 现有交互协议和 UI，系统边界清晰。

缺点：

- 需要给 `vibebar-agent` 增加更精确的 responder 生命周期管理。

### Approach B: Asynchronous File Or Event Reply

做法：

- hook 先上报 interaction，后续 UI 再通过文件或异步事件补发回复给 `Codex`。

优点：

- bridge 实现简单。

缺点：

- 不符合 `Codex` 的交互模型；大多数交互都要求 hook 当场返回结果。
- 极易出现 hook 已结束、回复已无效的问题。

### Approach C: Wrapper / PTY Injection

做法：

- 让 `vibebar codex` wrapper 读取终端输出并向 PTY 注入 `y/n`、文本或选项。

优点：

- 看起来不依赖 hook 回复协议。

缺点：

- 极度脆弱，依赖终端文案和 UI 格式。
- 对 `PlanReview`、多题问题和 Desktop 模式都不可靠。

## Chosen Approach

选择 **Approach A**。

原因很直接：

- 这是唯一一个既能稳定覆盖 `PermissionRequest`，又能支持 `AskUserQuestion` 和 `PlanReview` 的方案。
- 它与当前 `VibeBar` 已实现的双向 interaction bus 完全同向，只需补 `Codex` 适配层。
- 它避免把 `Codex` 拉回到 PTY 注入这类不可靠实现。

## Architecture

### 1. Two-Path `codex-hook` Command

`vibebar codex-hook` 分成两条路径：

- 非交互事件：继续走 `CodexHookEventBridge -> AgentEvent`
- 交互事件：走 `CodexInteractionBridge -> PendingInteraction -> interaction_request`

交互事件不会立即退出，而是等待 agent 返回结果后再向 stdout 输出 `hookSpecificOutput`。

### 2. `CodexInteractionBridge`

新增一个 core 组件，例如：

- [`CodexInteractionBridge.swift`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/CodexInteractionBridge.swift)

职责：

- 识别交互型 hook 事件：
  - `PermissionRequest`
  - `AskUserQuestion`
  - `PlanReview`
- 将原始 hook JSON 转成 `PendingInteraction`
- 将 `InteractionDecision` 转成 `Codex` 需要的 `hookSpecificOutput` JSON
- 负责 `answers` key 的生成、去重、fallback 与 plan review payload 组装

这层必须放在 `VibeBarCore`，避免同样的协议知识散落在 `VibeBarCLI`、`VibeBarAgent` 和 `VibeBarApp` 中。

### 3. Pending Interaction Mapping

统一映射规则：

- 普通 `PermissionRequest` -> `PendingInteraction(kind: .permission)`
- `PermissionRequest` + `tool_name = AskUserQuestion` -> `PendingInteraction(kind: .question)`
- `PermissionRequest` + plan review 标记 -> `PendingInteraction(kind: .planReview)`

为了稳定支持 `AskUserQuestion` 多题场景，`PendingInteraction` 的扁平字段还需要补一层结构化 prompt 描述，例如可选增加：

- `prompts: [InteractionPrompt]`
- `InteractionPrompt(id:title:options:allowsFreeText:allowsMultipleSelection:metadata:)`

单题权限与 plan review 仍可继续只使用现有 `message/options/allowsFreeText`，但多题 `Codex` 问题不能再仅靠单个 `message` 字段表达，否则 UI 无法稳定收集并回填多组 `answers`。

`transportContext` 保存 `Codex` 原始字段，包括但不限于：

- `hook_event_name`
- `tool_name`
- `question headers`
- `request id`
- `plan review payload`
- `session_id`
- `cwd`

UI 不直接依赖这些内部字段，只通过 `PendingInteraction` 的标准字段显示与回传。

### 4. Agent-Side Responder Lifecycle

`vibebar-agent` 继续使用统一的 `interaction_request` / `interaction_response` 协议，但要补足 `Codex` 的同步等待语义：

- `interaction.id -> pending responder`
- `sessionID -> active interaction`
- 收到 UI 回复后：
  - 唤醒等待中的 hook caller
  - 清理 `InteractionStore`
  - 清理 `SessionSnapshot.pendingInteractionID`
- caller 断连或超时时：
  - 清理 pending responder
  - 清理对应 interaction
  - 恢复 session 状态

如果同一 `sessionID` 上来了新的交互，而旧交互尚未处理，则旧交互必须按保守策略 drain，而不是静默丢弃。

### 5. Reply Protocol

回包格式遵循 `Codex` hook 协议，核心结构为：

```json
{"hookSpecificOutput": { ... }}
```

最小映射：

- 权限允许：

```json
{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}
```

- 权限拒绝：

```json
{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny"}}}
```

- AskUserQuestion 回答：

```json
{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","updatedInput":{"answers":{"key":"value"}}}}}
```

Plan review 也走同一出口，但 payload 细节由 `CodexInteractionBridge` 结合原始 hook 字段生成，不把协议细节泄露给 UI 层。

### 6. `InteractionActionHandler` Extension

`InteractionActionHandler.submit(...)` 继续作为 UI 统一入口。

扩展规则：

- `tool == .opencode`：保持现有 OpenCode 逻辑
- `tool == .codex`：新增 Codex reply 分支
- 其他工具：继续走统一 agent response relay

`Codex` 不走 OpenCode 的 HTTP reply，也不直接写 session 文件；所有 UI 决策都先进入 `interaction_response`，再由等待中的 `codex-hook` 进程拿到最终 reply JSON。

### 7. UI Reuse

UI 继续复用当前 session 行内交互呈现，不新增 `Codex` 专属界面：

- `permission`：允许 / 拒绝 / 可选 always allow
- `question`：单选、多选、自由文本
- `planReview`：继续 / 拒绝 / 可选评论

如果 `Codex` 的 payload 不支持某种 richer action，bridge 负责降级，而不是把协议分支暴露给 UI。

## Timeout, Disconnect, And Queue Policy

### Queue Model

- 全局允许多个挂起 interaction
- 同一 `sessionID` 只允许一个前台 interaction
- 同一 session 新 interaction 到来时，旧 interaction 必须先 drain

### Conservative Defaults

- `PermissionRequest` 超时或断连：`deny`
- `AskUserQuestion` 若来自 `PermissionRequest`：`deny`
- 普通 question 超时或断连：空响应或空答案
- `PlanReview` 超时或断连：拒绝继续

### Late Responses

如果 hook caller 已断连，而 UI 再迟到地发出 `interaction_response`：

- agent 接收但丢弃
- 不报错
- 不恢复已经清理掉的 interaction

### State Mapping

- interaction 挂起时：`SessionSnapshot.status = .awaitingInput`
- 用户批准后：先回到 `.running`
- 最终是否进入 `.idle`，交给后续 `Stop` / transcript 完成事件决定

这样可以避免 UI 决策和 `Codex` 真实运行状态打架。

## Testing Strategy

### Core Tests

- `CodexInteractionBridgeTests`
- `PermissionRequest` / `AskUserQuestion` / `PlanReview` 映射
- `InteractionDecision -> hookSpecificOutput` 映射
- 多题 answers key 去重与 fallback

### Agent Tests

- 同 session 新交互 drain 旧交互
- timeout 返回保守 deny
- caller 提前断连时 interaction 被清理
- 晚到的 `interaction_response` 不污染状态

### App Tests

- `InteractionActionHandler` 对 `tool == .codex` 走 Codex bridge
- `SessionDisplayFormatter` 与 `AppModel` 正确展示 Codex interaction
- `planReview` approve / reject / comment 映射正确

### Manual Validation

- 启动 `vibebar-agent` 与 `VibeBarApp`
- 安装 Codex hooks
- 分别触发：
  - 权限审批
  - AskUserQuestion 单题
  - AskUserQuestion 多题
  - plan review
- 验证：
  - UI 正确展示
  - 回复后 Codex 立即继续
  - timeout 时收到保守拒绝
  - terminal 侧先回答后，VibeBar 中 pending interaction 自动消失

## MVP Scope

第一版稳定范围：

- `Codex CLI hooks`
- `PermissionRequest`
- `AskUserQuestion`
- `PlanReview`
- allow / deny / select / text
- timeout / disconnect / drain

明确延期：

- `Codex Desktop` 专属交互协议
- 跨重启恢复仍可继续回复的挂起 hook caller
- 专门的长期权限规则编辑界面
- 多客户端同时回复同一 interaction 的复杂仲裁

## Rationale

这个方案的核心优点是：

- 对 `Codex` 协议足够尊重，采用同步 hook 回包，而不是事后补救
- 对 `VibeBar` 架构足够克制，只加 bridge 和 responder 生命周期管理
- 对产品体验足够一致，`Codex` 交互会自然进入现有菜单栏和刘海交互流，而不是成为一个特例系统
