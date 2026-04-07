# Session Naming In Lists Design

**Date:** 2026-04-05

**Status:** Confirmed

## Summary

本次设计要把 session 列表首行从 `pid` 改成真正对用户有意义的 session 名，并统一覆盖当前 VibeBar 支持的所有 Agent Client。session 名分为“稳定会话名”和“当前任务”两个语义：前者用于首行展示，后者用于辅助说明。对于支持重命名的客户端，用户显式命名优先；对于未重命名的会话，默认使用首个用户任务总结。

## Goals

- session 列表首行不再显示 `pid`
- `Codex`、`Claude Code`、`OpenCode`、`Gemini CLI`、`Aider`、`GitHub Copilot` 统一支持 session 名展示
- 已重命名会话优先显示显式 session 名
- 未重命名会话默认显示首个用户任务总结
- 超长 session 名在右侧终端 Tag 之前尾部省略，保持 Tag 完整可见

## Non-Goals

- 本次不改动 session 导航逻辑
- 本次不新增独立“编辑 session 名”UI
- 本次不试图为纯 `processScan` 且无任何 prompt/title 数据的会话推断伪名称

## Current State

- [`SessionSnapshot`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/Models.swift) 已有 `title` 和 `currentTask` 字段，但没有统一表达“名称质量”的来源标记。
- [`SessionDisplayFormatter`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/SessionDisplayFormatter.swift) 首行优先用 `title/currentTask`，但兜底仍会回退到 `tool + pid`。
- [`MenuContentView.swift`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/MenuContentView.swift) 仍直接硬编码首行显示 `pid`。
- [`CodexSessionDetector.swift`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/CodexSessionDetector.swift) 当前默认回退到 rollout 的最后一条用户消息，而不是首条任务总结。
- [`GeminiTranscriptDetector.swift`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/GeminiTranscriptDetector.swift) 目前只识别状态，不提取会话名。
- [`vibebar-agent`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarAgent/main.swift) 会从插件事件里取 `title`，但对 prompt 类 fallback 仍不足以表达“显式命名”和“默认命名”的优先级差异。

## Chosen Approach

采用“统一命名层 + 各客户端补原始命名来源 + UI 统一渲染规则”的方案。

### Why This Approach

- 只改 UI 不能解决不同客户端命名来源不一致的问题。
- 只改各个 detector / plugin 会导致规则散落，后续增加客户端时维护成本高。
- 引入统一的命名优先级后，UI 只消费稳定字段，合并层也能正确处理“显式重命名覆盖默认名”。

## Naming Model

### Session Name vs Current Task

- `title`：稳定 session 名，优先用于首行展示
- `currentTask`：当前任务或最近动作，作为辅助说明
- 新增 `SessionTitleSource` 用来区分：
  - `explicit`：显式命名，例如 rename、session API title、thread name
  - `derived`：从首条用户任务总结或 prompt 推导出的默认名

### Unified Priority

首行命名规则统一为：

1. `title` 且 `titleSource = explicit`
2. `title` 且 `titleSource = derived`
3. `currentTask`
4. `未命名会话`

`pid` 不再参与任何展示兜底。

## Per-Client Data Sources

### Codex

- 显式名：`session_index.jsonl.thread_name`
- 默认名：rollout 第一条 `user_message`
- 当前任务：rollout 最近一条 `user_message`

### Claude Code

- 显式名：插件 metadata 中的 `title/custom_title/thread_name`
- 默认名：`first_user_message`，或首次 prompt/message
- 当前任务：`current_task/prompt/tool_name`

### OpenCode

- 显式名：HTTP API `session.title` 或插件 `title`
- 默认名：首条 user message / prompt
- 当前任务：最新 `current_task`

### Gemini CLI

- 显式名：hook metadata `title`
- 默认名：transcript 第一条 `user` message
- 当前任务：transcript 最近一条 `user` message

### Aider / GitHub Copilot

- 显式名：notify/hook metadata `title`
- 默认名：wrapper 首条 prompt 或首个用户输入
- 当前任务：当前 prompt 或最近一次输入

## Merge Strategy

- `explicit` 标题可以覆盖缺失标题，或覆盖低质量的 `derived` 标题。
- `derived` 标题不能覆盖已有 `explicit` 标题。
- `currentTask` 只在缺失时回填，不能反向覆盖稳定 `title`。
- 插件会话与 detector 会话按 PID 合并时，状态仍由高优先级源决定，但名称按 `SessionTitleSource` 质量合并。

## UI Presentation

- 首行左侧显示 `SessionDisplayFormatter` 计算出的 session 名
- 首行右侧保持终端 Tag
- session 名单行显示，尾部省略，保证 Tag 宽度优先保留
- 第二行显示状态、时长和必要的 `currentTask`
- 目录继续单独占一行

## Error Handling

- 空字符串或纯空白标题视为无效
- 纯 `processScan` 且无 prompt/title 数据的会话显示 `未命名会话`
- 超长标题只在 UI 层截断，不修改底层原始值
- 单个 transcript / rollout 坏行跳过，不影响整体解析

## Validation

### Automated Validation

- `CodexSessionDetectorTests`：首条 vs 最近一条用户消息的区分
- `GeminiTranscriptDetectorTests`：首条与最近一条 user message 提取
- `SessionDisplayFormatterTests`：无 `pid` 兜底、无名兜底为 `未命名会话`
- `AppModelTests`：`explicit` 标题覆盖 `derived` 标题，且不影响插件状态

### Manual Validation

- `Codex`、`Claude Code`、`OpenCode`、`Gemini CLI` 各启动会话确认首行显示 session 名
- 长标题在右侧 Tag 前正确省略
- 无命名信息时显示 `未命名会话`
