# Codex Session Detection Design

**Date:** 2026-04-04

**Status:** Confirmed

## Summary

本次设计为 VibeBar 增加一条面向 Codex 的高可信检测链路，用来替代当前仅依赖 `wrapper` 和 `processScan` 的弱识别方式。目标是同时解决三件事：

1. 更准确地识别 Codex session 的运行状态。
2. 识别 session 当前归属的终端 Client 与终端复用器。
3. 为后续菜单栏 / 刘海 UI 展示保留结构化数据，但本次先完成采集、存储、合并和验证。

## Goals

- 支持从 Codex 的本地会话数据中恢复 session 标题、来源与最近活动。
- 支持结合 hook、rollout 文件和进程信息推断 `running / awaiting_input / idle / unknown`。
- 支持识别常见终端 Client：`Kitty`、`Ghostty`、`iTerm`、`Warp`，以及基础 `Terminal.app`。
- 支持识别终端复用器：`tmux`、`zellij`。
- 为 `Codex CLI` 和 `Codex Desktop` 统一输出 `SessionSnapshot`，并补充结构化终端上下文。

## Non-Goals

- 本次不实现菜单栏或刘海 UI 中的 Client / pane / tty 展示。
- 本次不实现像 Vibe Island 那样的终端窗口跳转或审批 UI。
- 本次不提供 Codex hooks 的自动安装器；仅兼容已有本地配置。
- 本次不追求 `zellij` 的 pane 级精确跳转，只做 session-manager 级识别。

## Current State

- [`SessionSnapshot`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/Models.swift#L225) 只有工具、PID、状态、时间、cwd、命令等基础字段，没有终端上下文字段。
- [`AgentEvent`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/AgentEvents.swift#L21) 已经支持 `metadata`，但 [`vibebar-agent`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarAgent/main.swift#L11) 只把它当作备注字符串处理。
- [`CompositeSessionDetector`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/CompositeSessionDetector.swift) 目前只接 Claude/OpenCode/Gemini/进程扫描，没有 Codex 的本地会话检测器。
- [`CLISettingsConfiguration`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/CLISettingsConfiguration.swift#L74) 里 `Codex` 只开放了 `processScan`，无法单独控制更高可信的数据源。
- [`CodexUsageLoader`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/CodexUsageLoader.swift) 已经知道 `~/.codex/sessions` 路径，但只解析 token usage，不参与 session 状态识别。

## External Evidence

基于本机实际配置和运行数据，Codex 相关的可用信号包括：

- `~/.codex/config.toml` 中的 `features.codex_hooks = true`
- `~/.codex/hooks.json` 中的 `SessionStart / Stop / UserPromptSubmit`
- `~/.codex/session_index.jsonl` 中的 `thread_name`、来源元数据
- `~/.codex/sessions/**/rollout-*.jsonl` 中的实时事件

同时，Vibe Island 当前本机缓存表明：

- Codex Desktop 会话可能没有 `tty`
- 终端 CLI 会话则需要依赖 `tty + env + parent process chain`
- `tmux` 能通过 `TMUX / TMUX_PANE` 识别
- `zellij` 目前没有现成链路，需要在 VibeBar 里自行补 `ZELLIJ*` 环境支持

## Chosen Approach

采用“`Hook + Codex 本地文件 + 终端环境解析` 三路融合”的方案。

### Why This Approach

- 比 `processScan` 准确，能知道官方 session 标题和最近活动。
- 比纯 hook 更稳，能覆盖未装 wrapper 的既有会话。
- 比纯文件扫描更实时，能借助 hook 锁定开始/停止边界。
- 能与当前 `SessionFileStore + CompositeSessionDetector + MonitorViewModel` 架构自然对接。

## Data Model

### Session Source

新增一类更明确的来源用于 Codex 本地会话数据，例如：

- `sessionIndex` 或等价命名，用来表示来自本地 session 文件，而不是 `processScan`

这样可以避免把高可信文件源误归类为低可信的 `processScan`。

### Terminal Context

在 [`Models.swift`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/Models.swift) 中新增结构化模型：

- `TerminalClientKind`
- `SessionManagerKind`
- `TerminalContext`

`TerminalContext` 至少包含：

- `clientKind`
- `bundleIdentifier`
- `tty`
- `clientSessionID`
- `clientWindowID`
- `sessionManagerKind`
- `sessionManagerSessionID`
- `sessionManagerPaneID`
- `origin`

其中：

- `origin` 用来区分 `cli` / `desktop` / `unknown`
- `clientSessionID` 用来容纳 `ITERM_SESSION_ID`、`KITTY_WINDOW_ID` 等
- `sessionManagerPaneID` 用来容纳 `TMUX_PANE` 等 pane 标识

### Session Title

在 `SessionSnapshot` 中新增：

- `title`

它优先来自：

1. hook 的显式 title / prompt metadata
2. `session_index.jsonl` 的 `thread_name`
3. rollout 中可恢复的首条用户意图

## Detection Pipeline

### 1. Hook Ingestion

`vibebar-agent` 继续消费 `AgentEvent`，但不再只把 `metadata` 写成备注。对于 Codex hook 事件：

- 从 `metadata` 中保留 `_tty`、`TERM_PROGRAM`、`TMUX`、`TMUX_PANE`、`KITTY_WINDOW_ID`、`ITERM_SESSION_ID`、`TERM_SESSION_ID`、`ZELLIJ`、`ZELLIJ_SESSION_NAME` 等字段
- 尝试生成 `TerminalContext`
- 作为高优先级心跳，刷新已有 session 文件

### 2. Codex Local Session Detector

新增 `CodexSessionDetector`，负责：

- 读取 `~/.codex/session_index.jsonl`
- 扫描 `~/.codex/sessions/**/rollout-*.jsonl`
- 为每个 session 计算：
  - `sessionID`
  - `title`
  - `updatedAt`
  - `lastMeaningfulActivityAt`
  - `rolloutPath`
  - `origin`
  - 推断状态

### 3. Process / Environment Correlation

通过 `DetectorSupport` 增加新能力：

- 读取进程环境变量
- 解析 tty
- 获取父进程链

然后新增 `TerminalContextResolver`：

- 先吃 hook metadata
- 再吃进程环境
- 最后用父进程名称兜底

### 4. Composite Merge

`CompositeSessionDetector` 增加 Codex 检测器，并让 `MonitorViewModel` 把它视为高于 `processScan`、低于实时 hook 的可信来源。

同一 session 的归并优先级：

1. plugin / hook 持续心跳
2. Codex 本地 session 文件
3. process scan

## State Resolution

Codex 的状态按以下顺序推断：

1. hook 显式状态优先
2. 最近几秒内 rollout 出现工具调用 / reasoning / assistant 增量等活动：
   - `running`
3. rollout 或 hook 出现等待用户确认 / 问答 / plan review 等关键词：
   - `awaiting_input`
4. session 文件存在且相关进程仍存活，但近期无活动：
   - `idle`
5. 无法确认：
   - `unknown`

对于 `Stop / SessionEnd`：

- hook 到达时立即清理或降级
- 无 hook 时按进程生存期和更新时间阈值回收

## Terminal and Session Manager Detection

### Supported Client Detection

首版支持：

- `kitty`
- `ghostty`
- `iterm`
- `warp`
- `terminal`
- `unknown`

识别依据包括：

- `TERM_PROGRAM`
- `__CFBundleIdentifier`
- `ITERM_SESSION_ID`
- `TERM_SESSION_ID`
- `KITTY_WINDOW_ID`
- 父进程链中的 app / terminal 进程名

### Supported Session Manager Detection

首版支持：

- `tmux`
- `zellij`
- `none`
- `unknown`

识别依据包括：

- `TMUX`
- `TMUX_PANE`
- `ZELLIJ`
- `ZELLIJ_SESSION_NAME`
- 父进程链中的 `tmux` / `zellij`

## Error Handling

- `session_index.jsonl` 或 rollout 文件缺失时，不影响 app 正常运行，直接回退到 `processScan`
- 单个坏行 JSON 跳过，不中断整个文件解析
- 进程环境读取失败时，只返回部分 `TerminalContext`
- 对 `Codex Desktop` 没有 `tty` 的情况，允许 `origin = desktop` 且 `tty = nil`

## Validation

### Manual Validation

- 安装了 Codex hooks 后，启动 Codex CLI，会生成带有 `title` 和 `terminalContext` 的 session。
- 在 `Kitty`、`Ghostty`、`iTerm`、`Warp` 中分别运行 Codex，`clientKind` 能正确分类。
- 在 `tmux` 中运行 Codex，能识别 `sessionManagerKind = tmux` 且记录 `TMUX_PANE`。
- 在 `zellij` 中运行 Codex，能识别 `sessionManagerKind = zellij`。
- 关闭 hooks 后，仍能通过 `session_index + rollout + processScan` 看到 Codex session，但实时性略降。

### Automated Validation

- 为终端环境解析器补单元测试
- 为 Codex rollout / session index 解析补 fixture 测试
- 为状态决策逻辑补纯函数测试

## Risks

- Codex 本地文件格式可能随版本变化，需要解析逻辑尽量容错。
- 没有 hook 时，session 与具体 PID 的绑定可能存在短时歧义。
- `zellij` 环境变量在不同启动方式下可能不一致，需要先做保守识别。
- 当前没有 UI 展示，调试时需要依赖 session 文件和日志验证结果。

## Implementation Direction

优先实现顺序：

1. 扩展模型和检测偏好枚举
2. 新增终端上下文解析器
3. 新增 Codex 本地会话检测器
4. 接入 `CompositeSessionDetector`
5. 扩展 `vibebar-agent` 写入结构化 metadata
6. 增加测试和构建验证
