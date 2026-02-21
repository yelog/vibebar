# VibeBar

VibeBar 是一个 macOS 菜单栏状态监控应用（第一版），用于展示 `claude`、`codex`、`opencode` 三类 TUI 会话的运行状态和数量。

## 第一版能力

- 菜单栏图标支持彩色状态扇形 + 中心总数。
- 支持状态：`未启动`（工具级）、`空闲`、`运行中`、`等待用户操作`。
- 支持多实例并发（同一工具可同时多进程）。
- 支持两条监控链路：
  - `vibebar` PTY wrapper（高精度，推荐）
  - `ps` 进程扫描兜底（零侵入）

## 架构

- `VibeBarApp`：菜单栏应用，负责聚合状态和展示。
- `vibebar`：透明 PTY wrapper，负责转发输入输出并写会话状态。
- `VibeBarCore`：共享模型、会话存储、进程扫描、聚合逻辑。

状态文件写入目录：

- `~/Library/Application Support/VibeBar/sessions/*.json`

## 如何构建

```bash
swift build
```

## 如何运行

### 1) 启动菜单栏应用

```bash
swift run VibeBarApp
```

说明：该命令会持续驻留，不会返回 shell，这是正常行为。请保持该进程运行，并在另一个终端执行 `vibebar` 命令。
若启动后输出 `onConsole=false` 或 `当前不是 macOS 图形控制台会话`，表示你在非 GUI 会话（如远程/受限终端）运行，右上角图标不会显示。

### 2) 用 wrapper 启动 TUI（推荐）

```bash
swift run vibebar claude
swift run vibebar codex
swift run vibebar opencode
```

也可以透传原始参数：

```bash
swift run vibebar codex -- --model gpt-5-codex
```

如果图标没有出现，请先清理旧实例再重启：

```bash
pkill -f VibeBarApp || true
swift run VibeBarApp
```

并确认是在本机 `Terminal.app` / `iTerm` 的图形登录会话中运行（不是 SSH/后台会话）。

## 状态判定规则（第一版）

### Wrapper 通道

- `运行中`：最近 0.8s 内有输出活动。
- `等待用户操作`：检测到交互提示后进入锁存状态，直到用户输入后解除。
- `空闲`：进程存活但不满足以上条件。

### 兜底通道

- 扫描命令名识别 `claude` / `codex` / `opencode`。
- CPU 较高时标记 `运行中`，否则标记 `空闲`。

## 菜单栏图标语义

- 外环扇形：各状态数量占比。
- 中心数字：当前会话总数。
- 颜色：
  - 绿：运行中
  - 黄：等待用户
  - 蓝：空闲
  - 灰：未启动/无会话

## 文档调研（2026-02-20）

已对齐的官方文档（用于后续精度增强）：

- Claude Code CLI Reference: <https://docs.anthropic.com/en/docs/claude-code/cli-reference>
- OpenAI Codex CLI docs: <https://developers.openai.com/codex/cli>
- OpenAI Codex Non-interactive: <https://developers.openai.com/codex/cli/non-interactive>
- OpenCode CLI docs: <https://opencode.ai/docs/cli>
- OpenCode `run` docs: <https://opencode.ai/docs/cli/run>

## 已知限制

- 如果用户不通过 `vibebar` 启动，`等待用户操作` 的精度会下降。
- 提示词检测是启发式规则，可能出现误判。
- 当前未接入各工具的结构化事件流（例如 JSON 事件）作为主判定源。

## 下一步建议

- 增加“结构化模式”：
  - Claude: `--output-format stream-json`
  - Codex: `exec --json`
  - OpenCode: `run --format json`
- 将事件流解析纳入统一状态机，降低 prompt 文本匹配误差。
- 增加每个会话的历史轨迹与耗时统计。
