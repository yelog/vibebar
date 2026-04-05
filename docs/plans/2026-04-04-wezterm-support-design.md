# WezTerm Support Design

**Date:** 2026-04-04

**Status:** Proposed

## Summary

本次设计的目标，是让 VibeBar 对 `WezTerm` 达到接近 `Kitty` 的支持等级：

- 准确识别 `WezTerm` session
- 在菜单栏/刘海中展示 `WezTerm #n`
- 点击 session 后跳到正确 tab，并把焦点落到正确 pane

与 `iTerm2`、`Warp` 相比，`WezTerm` 的优势是官方 CLI 已经能列出结构化的 `window/tab/pane` 信息，并直接按 `pane-id` 激活目标 pane。

## Goals

- 新增 `WezTerm` 作为正式 `TerminalClientKind`
- 支持从进程环境和父进程链识别 `WezTerm`
- 支持为 `WezTerm` session 展示 tab 序号
- 支持 `WezTerm` pane 级精确跳转
- 保持现有 `tmux/zellij` 逻辑兼容

## Non-Goals

- 本次不实现 WezTerm workspace badge
- 本次不接管 WezTerm 自己的 mux 生命周期
- 本次不为 `Alacritty/Hyper` 一起补支持

## Current State

- [`TerminalClientKind`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/Models.swift) 还没有 `wezterm`
- [`ProcessScanner.swift`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/ProcessScanner.swift) 已经把 `wezterm-gui` 放进终端白名单
- [`TerminalContextResolver.swift`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/TerminalContextResolver.swift) 还没有识别 `WEZTERM_PANE` / `WEZTERM_UNIX_SOCKET`
- [`SessionNavigator.swift`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/SessionNavigator.swift) 还没有 WezTerm 专用导航策略
- [`SessionDisplayFormatter.swift`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/SessionDisplayFormatter.swift) 还不能展示 `WezTerm #n`

## Official Capability Model

基于 WezTerm 官方文档：

- `wezterm cli list --format json` 能列出 `window_id / tab_id / pane_id / cwd / title`
- `wezterm cli activate-pane --pane-id <id>` 能直接激活目标 pane
- `wezterm cli` 默认支持通过环境变量 `WEZTERM_PANE`、`WEZTERM_UNIX_SOCKET` 定位当前实例

这意味着 WezTerm 是一个天然适合做“session 到 pane 精确映射”的终端。

## Approaches

### Approach A: 只做识别与 app 激活

优点：

- 实现简单

缺点：

- 没有 tab 序号
- 没有 pane 级精确跳转
- 浪费 WezTerm 官方 CLI 能力

### Approach B: `WEZTERM_PANE` 直接驱动跳转（推荐）

流程：

1. 从环境或插件 metadata 中采集 `WEZTERM_PANE` 和 `WEZTERM_UNIX_SOCKET`
2. 检测阶段调用 `wezterm cli list --format json`
3. 通过 `pane_id` 找到目标 `tab_id`、`window_id`
4. 通过枚举顺序推导 tab index
5. 点击 session 时执行 `wezterm cli activate-pane --pane-id <pane_id>`

优点：

- 精度高
- 结构化信息丰富
- 和 Kitty 路径相似，产品一致性好

### Approach C: 只靠 `cwd/pid` 回退匹配

优点：

- 不依赖环境变量

缺点：

- 容易撞到同项目多个 pane
- 精度明显弱于 `WEZTERM_PANE`

## Chosen Approach

选择 **Approach B**，并保留 `cwd/pid` 作为回退。

## Data Model

在 [`TerminalContext`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/Models.swift) 中扩展：

- `clientKind = .wezterm`
- `clientSessionID` 保存 `WEZTERM_PANE`
- `clientControlAddress` 保存 `WEZTERM_UNIX_SOCKET`
- `clientTabIndex` 保存推导出的 tab index

如有需要，可后续补：

- `clientTabTitle`
- `clientWindowID`

## Detection

### Environment Keys

新增采集：

- `WEZTERM_PANE`
- `WEZTERM_UNIX_SOCKET`

这些字段要进入：

- [`DetectorSupport.swift`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/DetectorSupport.swift)
- `Claude/OpenCode` 插件 metadata

### Client Detection

[`TerminalContextResolver.swift`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/TerminalContextResolver.swift) 需要新增：

- bundle id / 进程名对 `wezterm-gui` 的识别
- `WEZTERM_PANE` 命中时直接判定为 `WezTerm`

## Enrichment

参照现有 Kitty enrichment，在 [`AppModel.swift`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/AppModel.swift) 增加 `WezTerm` enrichment：

1. 读取 `WEZTERM_UNIX_SOCKET`
2. 调 `wezterm cli list --format json`
3. 按 `pane_id == WEZTERM_PANE` 匹配
4. 用同一 `window_id` 下的 tab 排序推导 `clientTabIndex`
5. 将结果 merge 回 `SessionSnapshot.terminalContext`

如果没有 `WEZTERM_UNIX_SOCKET`，则回退：

- 直接调 `wezterm cli list --format json`
- 用 `pid/cwd` 做 best-effort 匹配

## Navigation

在 [`SessionNavigator.swift`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/SessionNavigator.swift) 增加：

- `focusWezTermPane(paneID: String, socketPath: String?)`

执行逻辑：

1. 优先 `wezterm cli activate-pane --pane-id <pane_id>`
2. 如果有 `WEZTERM_UNIX_SOCKET`，通过环境或参数显式指向正确实例
3. 最后激活 `WezTerm.app`

`activate-pane` 本身会把包含该 pane 的 tab/window 一起带到前台，所以不需要像 zellij 那样拆成“先 tab 后 pane”的两步。

## UI

在 [`SessionDisplayFormatter.swift`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/SessionDisplayFormatter.swift) 中新增：

- `WezTerm #n`
- 没有 index 时回退 `WezTerm`

## Testing

需要新增或补强的测试：

- `TerminalContextResolver` 能识别 `WEZTERM_PANE`
- `SessionDisplayFormatter` 能显示 `WezTerm #n`
- `SessionNavigator` 能从 `wezterm cli list --format json` 匹配 tab/pane
- `SessionNavigator` 能生成正确的 WezTerm 跳转计划
- `swift build`
- `swift test`

## Risks

- 如果用户同时运行多个 WezTerm GUI/mux 实例，需要正确使用 `WEZTERM_UNIX_SOCKET`
- 如果 agent 进程丢失 `WEZTERM_PANE`，则只能退回到 `pid/cwd` 匹配
- 若用户环境里的 `wezterm` CLI 不可用，则只能退化成 app 激活

## Recommendation

`WezTerm` 应该是下一阶段终端支持的最高优先级。它的官方控制面已经足够完整，能用相对较低的实现成本换来接近 `Kitty` 的体验质量。
