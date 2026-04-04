# Zellij Tab Navigation Design

**Date:** 2026-04-04

**Status:** Confirmed

## Summary

本次设计解决一个具体问题：当 session 运行在 `Ghostty + zellij` 或其他 `terminal client + zellij` 组合下时，VibeBar 当前只能激活外层 terminal app，不能切到正确的 zellij tab。

根因不是 app 激活失败，而是当前数据模型和跳转逻辑都只识别到了 `zellij session`，没有拿到 `tab` 这一层信息；同时 `SessionNavigator` 对 zellij 执行的还是只读查询命令，没有真正执行 tab 切换。

## Goals

- 让点击运行在 zellij 中的 session 时，尽量切到正确的 zellij tab。
- 保持当前 `Ghostty/Kitty/iTerm/Warp` 的 app 激活回退。
- 兼容没有 plugin/hook 的场景，允许仅靠本地检测链路工作。

## Non-Goals

- 本次不实现 zellij pane 级精确跳转。
- 本次不要求用户先切换 Claude/OpenCode 配置到 VibeBar 才能生效。
- 本次不改动 tmux 既有跳转策略。

## Current State

- [`TerminalContext`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/Models.swift) 只有 `sessionManagerSessionID` 和 `sessionManagerPaneID`，没有 `tab name`。
- [`SessionNavigator`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/SessionNavigator.swift) 的 `focusZellijSession()` 只是执行 `query-tab-names`，不会改变 tab 焦点。
- 本机验证表明：
  - `zellij --session <session> action go-to-tab-name <name>` 是可用的
  - `zellij --session <session> action dump-layout` 能返回 tab 名和每个 tab/pane 的 `cwd`
  - 当前 agent 进程未必继承 `ZELLIJ_SESSION_NAME` / `ZELLIJ_TAB_NAME`，所以不能只依赖环境变量

## Approaches

### Approach A: 只依赖 hook/plugin 注入 tab name

- 在 hook/plugin 里显式传 `zellij session name + tab name`
- 点击时直接 `go-to-tab-name`

优点：
- 最准确

缺点：
- 当前用户机器的 Claude/OpenCode 仍然接在 Vibe Island，不会立刻解决问题

### Approach B: 点击时纯 CLI 反查

- 仅根据 `session name + cwd`
- 点击时查询 `dump-layout`
- 从 layout 中推断最匹配的 tab，再 `go-to-tab-name`

优点：
- 不依赖 plugin/hook

缺点：
- 纯推断，精度受 layout 和命名习惯影响

### Approach C: 混合方案（推荐）

- 数据模型新增 `sessionManagerTabName` / `sessionManagerTabIndex`
- 若 hook/plugin 已提供 tab 信息，直接使用
- 若没有，则在点击时用 `dump-layout + cwd` 反查
- 成功推断后执行 `go-to-tab-name`
- 失败时仍回退到 terminal app 激活

优点：
- 立刻能修当前问题
- 未来接 hook/plugin 后可无缝提升精度

## Chosen Approach

采用 Approach C。

## Data Model

在 [`TerminalContext`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/Models.swift) 中新增：

- `sessionManagerTabName`
- `sessionManagerTabIndex`

这些字段默认可为空。

## Detection Strategy

### Primary

若环境或 metadata 中已存在 zellij tab 信息，则直接写入 `TerminalContext`。

预留可兼容的 key：

- `ZELLIJ_TAB_NAME`
- `ZELLIJ_TAB_INDEX`
- `zellij_tab_name`
- `zellij_tab_index`

### Fallback

若当前只有 zellij session name，但没有 tab 信息，则在跳转时再进行一次即时推断：

1. 执行 `zellij --session <session> action dump-layout`
2. 解析 layout 中每个 `tab` 的：
   - `name`
   - `focus`
   - `cwd`
3. 用当前 session 的 `cwd` 与 tab/pane 的 cwd 做匹配
4. 若有唯一最佳匹配，取该 tab name
5. 若无匹配，则回退到当前 focus tab 或仅激活 terminal app

## Navigation Strategy

zellij 点击跳转改为：

1. 若有 `tab name`：
   - `zellij --session <session> action go-to-tab-name <tab>`
2. 否则尝试即时推断 tab
3. 无论是否成功，最后都激活外层 terminal client app

这样即使 zellij 命令成功但 app 未置前，也能稳定把窗口带到前台。

## Testing

- 纯函数测试：
  - layout 解析
  - `cwd -> tab name` 匹配
  - plan 生成优先级
- 全量验证：
  - `swift build`
  - `swift test`
