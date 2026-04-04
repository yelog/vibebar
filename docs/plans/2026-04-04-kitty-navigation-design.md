# Kitty Navigation Design

**Date:** 2026-04-04

**Status:** Confirmed

## Summary

本次设计解决的是 `Kitty` 自带多 tab 和 split pane 场景下的精准跳转问题。

和 `zellij` 不同，Kitty 暴露了官方 remote control 接口，能直接按 `window id` 聚焦具体 pane；而在 Kitty 里，聚焦 pane 本身就会自动切到对应 tab。因此这一条链路可以做到比 zellij 更高精度的导航。

## Goals

- 让运行在 Kitty 原生 tab/split 中的 session，点击后直接跳到正确 tab 和正确 pane
- 对 `Kitty + tmux/zellij` 组合场景，先保持内层 session manager 跳转，再补外层 Kitty pane 聚焦
- 保持当前菜单栏/刘海 UI 和其他终端逻辑不变

## Non-Goals

- 本次不为 Kitty 增加额外 UI 展示字段
- 本次不实现 Kitty session 持久缓存
- 本次不改变 tmux / zellij 既有识别逻辑

## Current State

- [`TerminalContextResolver`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/TerminalContextResolver.swift) 已能识别 `KITTY_WINDOW_ID`
- 但 [`DetectorSupport`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/DetectorSupport.swift) 还没采 `KITTY_LISTEN_ON`
- [`SessionNavigator`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/SessionNavigator.swift) 对 Kitty 只有 app 激活，没有 tab/pane 精确跳转
- 本机验证表明：
  - `/Applications/kitty.app/Contents/MacOS/kitty @ --to <addr> ls` 能返回完整的 OS window / tab / window 树
  - `focus-tab` 和 `focus-window` 都支持按 `id` / `window_id` 匹配

## Approach

### Approach A: 只激活 Kitty app

优点：
- 简单

缺点：
- 无法切到正确 tab/pane

### Approach B: 只用 `KITTY_WINDOW_ID`

优点：
- 足够把 pane 精确聚焦

缺点：
- 如果 window id 失效，没有回退路径

### Approach C: `KITTY_LISTEN_ON + KITTY_WINDOW_ID + kitty @ ls`（推荐）

流程：
1. 采集 `KITTY_LISTEN_ON` 到 `TerminalContext`
2. 导航时优先 `focus-window --match id:<KITTY_WINDOW_ID>`
3. 若失败，再用 `kitty @ ls` 解析树并按 `pid/cwd` 回退匹配
4. 找到目标后先 `focus-tab --match window_id:<id>`，再 `focus-window --match id:<id>`
5. 最后激活 `Kitty.app`

优点：
- 纯 Kitty 场景下可以稳定精确到 pane
- 对 window id 漂移有回退

## Chosen Approach

采用 Approach C。

## Data Model

在 [`TerminalContext`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/Models.swift) 中新增：

- `clientControlAddress`

Kitty 场景下它保存 `KITTY_LISTEN_ON`。

## Navigation Strategy

- 如果 `sessionManagerKind == .none` 且 `clientKind == .kitty`
  - 直接走 Kitty 精确导航
- 如果 `sessionManagerKind == .tmux/.zellij` 且 `clientKind == .kitty`
  - 先执行 tmux / zellij 内层跳转
  - 再执行 Kitty 外层 pane 聚焦
  - 最后激活 `Kitty.app`

## Testing

- `TerminalContextResolver` 采集 `KITTY_LISTEN_ON`
- `SessionNavigator` 生成 Kitty 导航计划
- `kitty @ ls` JSON 解析与目标 window 匹配
- `swift build`
- `swift test`
