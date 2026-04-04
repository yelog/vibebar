# Zellij Pane Navigation Design

**Date:** 2026-04-04

**Status:** Confirmed

## Summary

当前 VibeBar 已经能把运行在 zellij 里的 session 切到正确 tab，但当同一 tab 下存在多个 pane 时，焦点仍然会落在 zellij 当前记住的 pane 上，而不一定是 agent 所在 pane。

本次设计解决的是这个差距：在 `go-to-tab-name` 成功后，追加一次 pane 级的 best-effort 聚焦。

## Constraints

- `zellij 0.43.1` 没有公开的 `focus-pane <id>` / `go-to-pane-id` 能力
- 当前进程环境中可以拿到 `ZELLIJ_SESSION_NAME` 和多数情况下的 `ZELLIJ_PANE_ID`
- `dump-layout` 能返回 tab 内 pane 结构、focus 标记、command 和 cwd 线索
- `move-focus` 只能按方向移动焦点，不支持按 pane id 精确切换

## Goals

- 切到正确 zellij tab 后，尽量把焦点再落到 agent 所在 pane
- 保持 Ghostty / Kitty / iTerm / Warp 的外层 app 激活回退
- 对简单分屏和常见嵌套分屏尽量有效

## Non-Goals

- 本次不承诺 pane 级 100% 精确跳转
- 本次不实现 zellij 内部插件或私有协议控制
- 本次不改变 tmux 的现有精确跳转链路

## Approaches

### Approach A: 只切 tab，不处理 pane

优点：
- 最稳定

缺点：
- 不能解决当前问题

### Approach B: 用 pane id 直接跳

优点：
- 理论上最准确

缺点：
- 当前 zellij CLI 不支持

### Approach C: dump-layout + move-focus 迭代（推荐）

流程：
1. 先切到目标 tab
2. 读取当前 `dump-layout`
3. 解析当前 tab 的 pane 树、当前焦点 pane、目标 agent pane
4. 基于公共父 split 推导下一步方向
5. 执行一次 `move-focus`
6. 重新读取 `dump-layout`，最多迭代若干次直到命中目标 pane

优点：
- 不依赖额外插件
- 能覆盖大多数左右/上下分屏和常见嵌套布局

缺点：
- 对复杂布局只是 best-effort

## Chosen Approach

采用 Approach C。

## Detection Strategy

目标 pane 的判定优先级：

1. `pane command` 与 session 可执行名匹配
2. pane 有效 cwd 与 session.cwd 精确匹配
3. pane 有效 cwd 与 session.cwd 前缀最相近

当前焦点 pane 的判定来自 `dump-layout` 中 leaf pane 的 `focus=true`。

## Navigation Strategy

- `go-to-tab-name` 成功后，再读取一次 `dump-layout`
- 若目标 pane 已经聚焦，则结束
- 否则根据当前焦点 pane 和目标 pane 在 pane 树中的最近分歧层，推导方向：
  - `vertical` split: `left/right`
  - `horizontal` split: `up/down`
- 执行 `move-focus`
- 最多迭代 6 次，避免死循环
- 无法推断或没有进展时，保留当前 tab 焦点并结束

## Testing

- 纯函数测试：
  - pane 树解析
  - 目标 pane 匹配
  - 下一步方向推导
- 集成级验证：
  - `swift build`
  - `swift test`
