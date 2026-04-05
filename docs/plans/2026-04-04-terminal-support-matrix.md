# Terminal Support Matrix

**Date:** 2026-04-04

## Summary

这份文档梳理当前 VibeBar 的 session 终端识别能力，并给出下一阶段值得支持的常用终端优先级。

这里把“终端 client”和“session manager”分开看：

- `client` 指外层终端应用，例如 `Kitty`、`Ghostty`、`iTerm2`
- `session manager` 指运行在终端里的复用器，例如 `tmux`、`zellij`

## Current Client Support

| Client | 识别 | 展示 | 精确跳转 | 备注 |
| --- | --- | --- | --- | --- |
| Kitty | 完整 | 完整 | 完整 | 支持 `Kitty #n`，可精确到 tab/pane |
| Ghostty | 完整 | 中等 | 中等 | 支持 app 识别与激活；纯 Ghostty tab/pane 还未做稳定映射 |
| iTerm2 | 完整 | 基础 | 基础 | 当前主要是识别与 app 激活 |
| Warp | 完整 | 基础 | 基础 | 当前主要是识别与 app 激活 |
| Terminal.app | 完整 | 基础 | 基础 | 当前主要是识别与 app 激活 |
| Codex App | 完整 | 完整 | 完整 | 走 desktop origin，不属于终端 client |

## Current Session Manager Support

| Manager | 识别 | 展示 | 精确跳转 | 备注 |
| --- | --- | --- | --- | --- |
| tmux | 完整 | 完整 | 完整 | 支持 `tmux #n`，这里的 `#n` 是 `window_index` |
| zellij | 完整 | 完整 | 中等 | 支持 `zellij #n`；pane 聚焦是 best-effort |

## Recognition-Only Candidates In Code

这些终端已经出现在扫描白名单里，但还没有进入正式的 `TerminalClientKind` 能力面：

- `WezTerm GUI`
- `Alacritty`
- `Hyper`

它们当前最多只影响“这是交互式终端链路”的启发式判断，不会出现在 session badge 中，也没有专属跳转逻辑。

## Current Gaps

### Ghostty

- 当前版本已经能通过 bundle id、进程链和环境变量稳定识别 `Ghostty`
- 当前也已知 `Ghostty` 暴露 AppleScript `window/tab/terminal`
- 但我们还没有把 session 侧的 `GHOSTTY_SURFACE_ID` 和 AppleScript `terminal id` 做稳定映射
- 因此纯 `Ghostty` 场景下，不能产品级地显示 `Ghostty #n`，也不能精确到指定 tab/pane

### iTerm2 / Warp / Terminal.app

- 这几类终端当前都停留在“识别 + 应用激活”
- 缺少 tab/session/pane 的结构化枚举与定位逻辑

### WezTerm

- 当前还未正式支持
- 但它最值得优先补，因为官方 CLI 已经能稳定列出 `window/tab/pane`，也能按 pane 激活

## Recommended Priority

### P0

- `WezTerm`

理由：

- 官方 CLI 直接支持列出 `windows/tabs/panes`
- 官方 CLI 直接支持按 `pane-id` 激活
- session 环境有标准字段 `WEZTERM_PANE`
- 这条链路和 `Kitty` 一样，天然适合做 `#n` 展示和精确跳转

### P1

- `Ghostty` 深化支持
- `iTerm2` 深化支持

理由：

- `Ghostty` 已有 AppleScript 字典，剩下的主要是 session 到 terminal surface 的映射问题
- `iTerm2` 在 macOS 开发场景仍很常见，产品价值足够高

### P2

- `Alacritty`
- `Warp`

理由：

- `Alacritty` 使用量不低，但 tabs/splits/mux 能力不如 `Kitty/WezTerm` 适合投入精确导航
- `Warp` 常见，但自动化/控制能力的投入产出比目前不如 `WezTerm`

### P3

- `Hyper`
- `Tabby`
- `Rio`

理由：

- 都有一定用户群，但对当前 macOS 菜单栏 AI agent 产品来说，优先级明显低于前两组

## Recommended Product Direction

建议把终端支持分成三档：

### Tier 1: Fully Navigable

- Kitty
- tmux
- zellij
- WezTerm（下一阶段）

要求：

- 能识别
- 能展示终端/manager badge
- 能显示 tab 序号
- 能精确跳转到正确 tab
- 能精确或 best-effort 跳到正确 pane

### Tier 2: Recognized With App-Level Focus

- Ghostty
- iTerm2
- Warp
- Terminal.app

要求：

- 能识别
- 能展示 badge
- 能回跳应用
- 不承诺 pane 级精确导航

### Tier 3: Heuristic Recognition

- Alacritty
- Hyper
- Tabby
- Rio

要求：

- 先做到识别与展示
- 等官方控制面清晰后再做精确导航

## Notes

- `tmux #n` 的 `#n` 是 tmux window index，本质上等价于用户视角里的 tab
- `zellij #n` 的 `#n` 是 zellij tab index，本质上属于 manager 而不是外层 terminal client
- `Ghostty #n` 在没有稳定 surface 映射前不应展示，否则容易误标
- `WezTerm` 是当前最值得补的下一站，因为它既有结构化枚举，也有官方激活命令
