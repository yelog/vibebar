# VibeBar

VibeBar 是一个 macOS 菜单栏状态监控应用（第一版），用于展示 `claude`、`codex`、`opencode` 三类 TUI 会话的运行状态和数量。

## 第一版能力

- 菜单栏图标支持彩色状态扇形 + 中心总数。
- 支持状态：`未启动`（工具级）、`空闲`、`运行中`、`等待用户操作`。
- 支持多实例并发（同一工具可同时多进程）。
- 支持两条监控链路：
  - `vibebar` PTY wrapper（高精度，推荐）
  - `ps` 进程扫描兜底（零侵入）
- 支持结构化事件链路：
  - `vibebar-agent` 本地 socket 接收插件事件

## 架构

- `VibeBarApp`：菜单栏应用，负责聚合状态和展示。
- `vibebar`：透明 PTY wrapper，负责转发输入输出并写会话状态。
- `vibebar-agent`：本地事件接收服务，负责接收插件事件并写会话状态。
- `VibeBarCore`：共享模型、会话存储、进程扫描、聚合逻辑。
- `plugins/*`：Claude/OpenCode 插件（monorepo 管理）。

状态文件写入目录：

- `~/Library/Application Support/VibeBar/sessions/*.json`
- Agent socket 路径：`~/Library/Application Support/VibeBar/runtime/agent.sock`

## 安装（.dmg 下载）

1. 从 [GitHub Releases](../../releases) 下载最新 `VibeBar-xxx-universal.dmg`
2. 打开 .dmg，将 VibeBar.app 拖到 Applications
3. 首次启动：右键 → 打开（绕过 Gatekeeper）
4. VibeBar 将以菜单栏图标形式运行，agent 服务会自动启动

> 注：插件功能需要对应 CLI 工具已安装（claude / opencode）

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

### 2) 启动本地 Agent（插件模式推荐）

```bash
swift run vibebar-agent --verbose
```

可查看默认 socket 路径：

```bash
swift run vibebar-agent --print-socket-path
```

### 3) 用 wrapper 启动 TUI（推荐）

```bash
swift run vibebar claude
swift run vibebar codex
swift run vibebar opencode
```

也可以透传原始参数：

```bash
swift run vibebar codex -- --model gpt-5-codex
```

### 4) 配置插件接入（推荐用于高精度状态）

仓库内已提供一键配置脚本：

```bash
bash scripts/install/setup-local-plugins.sh
```

详细说明见：

- `plugins/README.md`
- `plugins/opencode-vibebar-plugin/README.md`
- `plugins/claude-vibebar-plugin/README.md`

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

### Agent 事件通道

- 插件发送 `NDJSON` 到 `agent.sock`，每行一个事件。
- 核心字段：
  - `source`: `claude-plugin` / `opencode-plugin`
  - `tool`: `claude-code` / `opencode`
  - `session_id`: 插件侧会话 ID
  - `event_type`: 事件类型（如 `session_started`、`status_changed`、`session_ended`）
  - `status`: `running` / `awaiting_input` / `idle`（可选，缺省时由事件名推断）
- Agent 会把插件会话写成 `source=plugin`，并自动处理结束事件回收。

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
- OpenCode Plugins docs: <https://opencode.ai/docs/plugins/>
- Claude Code Hooks docs: <https://docs.anthropic.com/en/docs/claude-code/hooks>

## 已知限制

- 如果 Claude/OpenCode 未安装插件，仍会退化到 wrapper/`ps` 的启发式判定。
- 提示词检测是启发式规则，可能出现误判（主要影响非插件链路）。
- Codex 当前仍未接入插件链路，建议继续使用 wrapper + 兜底扫描。

## 下一步建议

- 接入 Codex 事件增强（`notify`/结构化输出），减少 `awaiting` 误判。
- 增加 Agent 会话持久化策略（崩溃恢复、去重序列号）。
- 增加每个会话的历史轨迹与耗时统计。
