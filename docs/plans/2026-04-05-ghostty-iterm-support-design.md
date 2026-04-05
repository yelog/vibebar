# Ghostty And iTerm2 Deep Support Design

**Date:** 2026-04-05

**Status:** Proposed

## Summary

本次设计目标是把 `Ghostty` 和 `iTerm2` 从“能识别 client 并激活应用”的中等支持，提升到接近 `Kitty/WezTerm` 的正式支持等级。

- `Ghostty`：补齐纯 `Ghostty tab/split` 场景下的 tab 序号展示与跳转，pane 聚焦做 `best-effort`
- `iTerm2`：补齐 `window/tab/session` 级别的精确识别与跳转

## Goals

- 为 `Ghostty` session 展示 `Ghostty #n`
- 为 `iTerm2` session 展示 `iTerm #n`
- 纯 `Ghostty` 场景下支持 tab 级可靠跳转
- 纯 `Ghostty` 场景下支持 pane 级 `best-effort` 聚焦
- `iTerm2` 场景下支持 window/tab/session 级精确跳转
- 保持与现有 `tmux/zellij` 链路兼容

## Non-Goals

- 本次不修改 `tmux/zellij` 行为
- 本次不新增新的插件安装流程
- 本次不要求 `Ghostty` 达到和 `iTerm2` 相同的 pane 精度

## Current State

- [`TerminalContextResolver.swift`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/TerminalContextResolver.swift) 已能识别 `Ghostty` 与 `iTerm2`
- [`SessionDisplayFormatter.swift`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/SessionDisplayFormatter.swift) 对 `Ghostty` 只有 `clientTabIndex` 展示入口，对 `iTerm2` 还没有 `#n`
- [`AppModel.swift`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/AppModel.swift) 当前只做了 `Kitty / WezTerm / tmux / zellij` enrichment
- [`SessionNavigator.swift`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/SessionNavigator.swift) 当前对 `Ghostty` 与 `iTerm2` 只有 `.activateBundle(...)` 回退

## Capability Analysis

### Ghostty

截至 2026 年 4 月 5 日，Ghostty 官方文档确认 macOS 上暴露 AppleScript：

- 对象模型：`application -> windows -> tabs -> terminals`
- `tab` 提供 `id / index / selected / focused terminal`
- `terminal` 提供 `id / name / working directory`
- 支持 `focus terminal`、`select tab`、`activate window`

来源：[Ghostty AppleScript 文档](https://ghostty.org/docs/features/applescript)

关键限制：

- 进程环境里的 `GHOSTTY_SURFACE_ID` 与 AppleScript 的 `terminal id` 不是同一套 ID
- `terminal` 不暴露 `tty`
- 因此无法像 `Kitty/WezTerm/iTerm2` 一样用稳定原生 ID 直接精确锁定 pane

### iTerm2

截至 2026 年 4 月 5 日，iTerm2 官方 AppleScript 文档确认：

- 对象模型：`window -> tab -> session`
- `tab` 提供 `index`
- `session` 提供 `id / unique id / tty / name`
- `window/tab/session` 都支持 `select`

来源：[iTerm2 AppleScript 文档](https://iterm2.com/3.0/documentation-scripting.html)

这意味着 iTerm2 可以用 `tty` 精确定位 session，再反推出所属 tab 和 window。

## Approaches

### Approach A: 只做 tab 序号展示

优点：

- 实现简单

缺点：

- 不解决核心跳转问题

### Approach B: Ghostty best-effort + iTerm2 精确（推荐）

Ghostty：

1. 用 AppleScript 抓取 `window/tab/terminal` 树
2. 用 `cwd + terminal title` 匹配目标 terminal
3. 补齐 `clientTabID / clientTabIndex / clientNativeSessionID`
4. 跳转时优先 `focus terminal`

iTerm2：

1. 用 AppleScript 抓取 `window/tab/session` 树
2. 用 `tty` 精确匹配 session
3. 补齐 `clientTabIndex / clientNativeSessionID / clientWindowID`
4. 跳转时 `select window -> select tab -> select session`

优点：

- 兼顾可实现性与精度
- 与现有 enrichment 架构一致

缺点：

- Ghostty pane 仍有歧义边界

### Approach C: 为 Ghostty 增加专门桥接层

优点：

- Ghostty 也可接近 pane 精确

缺点：

- 侵入性大，要改 plugin/wrapper/store
- 超出当前需求

## Chosen Approach

选择 **Approach B**。

## Data Model

扩展 [`TerminalContext`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/Models.swift)：

- `clientTabID`
- `clientNativeSessionID`

保留现有字段：

- `clientSessionID`：继续承载环境原始标识
  - Ghostty: `GHOSTTY_SURFACE_ID`
  - iTerm2: `ITERM_SESSION_ID`
- `clientTabIndex`
- `clientWindowID`

## Enrichment Design

在 [`AppModel.swift`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/AppModel.swift) 的 `enrichTerminalTabs` 中新增两段：

- `enrichGhosttyTabs`
- `enrichITermTabs`

### Ghostty Enrichment

抓取 AppleScript 快照，至少包括：

- `window id`
- `tab id`
- `tab index`
- `tab selected`
- `terminal id`
- `terminal name`
- `terminal working directory`

匹配顺序：

1. `cwd` 唯一精确匹配
2. `cwd` 相似度最高
3. `terminal name` 与命令名/最近标题的弱匹配
4. 若仍歧义，只在单 tab 场景补 tab index，不补 native terminal id

### iTerm2 Enrichment

抓取 AppleScript 快照，至少包括：

- `window id`
- `tab index`
- `session id`
- `session unique id`
- `session tty`
- `session name`

匹配顺序：

1. `tty`
2. `clientSessionID` / `unique id`
3. `cwd`

## Navigation Design

### Ghostty

新增策略：

- `.focusGhosttyTerminal(windowID: String?, tabID: String?, terminalID: String?, cwd: String?)`

执行逻辑：

1. 如果拿到 `terminalID`，直接 `focus terminal`
2. 否则若拿到 `tabID`，`select tab`
3. 若拿到 `windowID`，`activate window`
4. 最后 `activate Ghostty`

### iTerm2

新增策略：

- `.focusITermSession(windowID: String?, tabIndex: Int?, tty: String?, uniqueID: String?)`

执行逻辑：

1. 如果能用 `tty/unique id` 在脚本里精确找到 session，执行 `select`
2. 再确保 tab/window 被带到前台
3. 最后回退 `activate iTerm2`

## UI Design

在 [`SessionDisplayFormatter.swift`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/SessionDisplayFormatter.swift)：

- `Ghostty #n`
- `iTerm #n`

不增加额外 badge，保持与 `Kitty #n / WezTerm #n` 一致。

## Risks

- Ghostty 在同项目多 pane、相同 cwd、相似标题场景下可能无法唯一定位 terminal
- iTerm2 在本机未安装时无法做运行时联调，只能依赖单测和官方文档
- AppleScript 依赖 Automation 权限，首次控制时可能触发系统授权

## Recommendation

先把 `Ghostty` 做到“tab 可靠 + pane best-effort”，把 `iTerm2` 做到“tab/pane 精确”。这条路径与现有架构兼容，且能显著提升菜单和跳转体验。
