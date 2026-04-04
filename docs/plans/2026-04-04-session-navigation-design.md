# Session Navigation Design

**Date:** 2026-04-04

**Status:** Confirmed

## Summary

本次设计承接前一轮 Codex session 检测，继续完成两件事：

1. 把 `terminalContext` 从普通文本升级为明确的 badge 展示。
2. 把 `terminalContext` 真正用于 session 跳转，让菜单栏和刘海中的 session 行可以跳回对应终端环境。

目标不是一次性复制 Vibe Island 的全部 terminal adapter，而是在现有 VibeBar 架构里补一条可扩展的“显示 + 跳转”链路，并明确不同终端复用器的精度边界。

## Goals

- 菜单栏和刘海使用统一的 badge 数据模型展示 `client / session manager / origin / tty`。
- session 行支持点击跳转。
- `tmux` 支持基于 `pane id` 的高优先级跳转。
- `zellij` 支持基于 `session name` 的保守跳转，并明确回退到 client/window 级激活。
- `Codex Desktop` 和普通 CLI terminal 都能走统一入口。

## Non-Goals

- 本次不实现每个 terminal 的窗口、tab、split 全量原生适配。
- 本次不承诺 `zellij` pane 级精确跳转，因为当前识别链路只有 `session name + pane id`，但没有可稳定调用的外部 pane 聚焦接口。
- 本次不实现 Terminal.app / Ghostty / Warp 的 pane/tab 精确跳转，只做 app 激活级回退。

## Current State

- [`SessionDisplayFormatter`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/SessionDisplayFormatter.swift) 已经能拼接终端摘要字符串，但没有 badge 抽象。
- [`NotchContentView`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/NotchContentView.swift) 和 [`StatusItemController`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/StatusItemController.swift) 都只消费纯文本。
- session 行目前没有统一点击跳转能力。
- `terminalContext` 已经能识别 `tmux / zellij / kitty / ghostty / iterm / warp / terminal / desktop`，但仅用于展示。

## Chosen Approach

采用“`Presentation Model + Navigator`”两层方案。

### Presentation Model

在 App 层新增 badge 模型，例如：

- `SessionBadge`
- `SessionBadgeTone`

由 [`SessionDisplayFormatter`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/SessionDisplayFormatter.swift) 统一生成 badge 列表。UI 只负责渲染，不再拼接终端字符串。

badge 类型分为：

- client：`Kitty`、`Ghostty`、`iTerm`、`Warp`、`Terminal`
- manager：`tmux`、`zellij`
- origin：`Codex Desktop`
- terminal identity：`tty`

### Navigator

在 App 层新增 `SessionNavigator`，统一处理跳转逻辑。

跳转优先级：

1. `Codex Desktop`：激活 `com.openai.codex`
2. `tmux`：按 `socket + pane id` 选择 pane，并尽量切到对应 session/window
3. `zellij`：按 `session name` 激活对应 session；若缺少更高精度能力，则回退到 client app 激活
4. terminal client：尽量做 client 级精确激活（如 iTerm session、Kitty window）
5. 最终回退：只激活 bundle 对应 app

## tmux Strategy

对于 `tmux`，已知数据包括：

- `TMUX` 原始值，可恢复 socket path
- `TMUX_PANE`
- 外层 `bundleIdentifier`

采用以下策略：

1. 从 `TMUX` 中解析 socket path
2. 用 `tmux display-message -p -t <pane>` 获取 `session_id` 和 `window_id`
3. 用 `tmux select-window -t <window>` 和 `tmux select-pane -t <pane>` 更新服务端焦点
4. 如果能唯一确定 client，则再执行 `switch-client`
5. 最后激活终端 app / client window

这条路径能提供 pane 级精度，并且即使 `switch-client` 不可用，也能退化为“当前 attached client 显示到正确 pane”。

## zellij Strategy

对于 `zellij`，当前可靠数据只有：

- `ZELLIJ_SESSION_NAME`
- `ZELLIJ_PANE_ID`
- 外层 `bundleIdentifier`

本机 CLI 能稳定做到的是 session 级 action，而不是 pane 级外部聚焦。因此本次采用：

1. 若有 `session name`，优先执行面向该 session 的 attach / action
2. 同时激活外层 terminal client
3. 保留 pane id 作为后续扩展字段，但不伪装成已支持 pane 级精确跳转

## UI Behavior

### Notch

- session 主标题继续显示 title / tool+pid
- 在次级信息下方增加 badge 行
- badge 点击不单独交互，整个 row 可点击跳转

### Menu

- `SessionMenuItemView` 增加 badge 容器
- item 高度允许根据 badge 行自适应
- 鼠标点击触发跳转

## Error Handling

- 跳转失败时不破坏现有刷新链路。
- 若精确命令失败，继续执行 app 激活回退。
- 若整条链路都失败，则蜂鸣提示。

## Testing

- App 层纯函数测试：
  - badge 生成顺序和标签
  - tmux socket/path 解析
  - jump action 规划优先级
- 构建与全量测试：
  - `swift test`
  - `swift build`
