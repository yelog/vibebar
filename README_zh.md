# VibeBar

[English](README.md) · **[中文](README_zh.md)** · [日本語](README_ja.md) · [한국어](README_ko.md)

VibeBar 是一款轻量级 macOS 菜单栏应用，可实时监控 **Claude Code**、**Codex**、**OpenCode**、**Aider**、**Gemini CLI** 和 **GitHub Copilot** 的 TUI 会话状态。

<table>
  <tr>
    <th>代理会话和 Token 使用趋势</th>
    <th>代理会话和 Token 使用趋势</th>
  </tr>
  <tr>
    <td>
      <img src="docs/images/vibebar-light.png" />
    </td>
    <td>
      <img src="docs/images/vibebar-dark.png" />
    </td>
  </tr>
</table>

支持多种图标样式和配色方案，可以在设置中按喜好调整。

<img src="docs/images/vibebar-setting.png" alt="VibeBar 设置截图" width="600" />

## 接入方式（重要）

- **Claude Code**：推荐安装 VibeBar 插件。
- **OpenCode**：推荐安装 VibeBar 插件。
- **Aider**：推荐使用 `vibebar` 包装器，并可选择使用 `vibebar notify` 获得更好的等待输入信号。
- **Gemini CLI**：推荐使用 `vibebar` 包装器。在无头/提示模式下，包装器会自动启用 `--output-format stream-json`（除非已手动设置）。
- **GitHub Copilot**：推荐安装 VibeBar Hooks 插件，在 **设置 → 插件 → GitHub Copilot → 安装** 中操作。VibeBar 会自动将 `.github/hooks/hooks.json` 部署到当前所有运行中的 Copilot 会话项目目录。安装后新打开的项目需再次点击**安装**，或手动复制 hooks 文件。
- **Codex**：推荐使用 `vibebar` 包装器，因为 Codex 目前没有插件体系。
- `vibebar` 包装器支持 `claude` / `codex` / `opencode` / `aider` / `gemini` / `copilot`，但插件集成仍是首选方式（如可用）。

## 功能特性

- 菜单栏实时显示多个会话和工具的运行状态。
- 支持在带刘海的 MacBook 屏幕上启用刘海展示模式；当前主屏不支持时会自动回退为普通菜单栏入口。
- 会话状态：`running`（运行中）、`awaiting_input`（等待输入）、`idle`（空闲）、`stopped`（已停止）、`unknown`（未知）。
- 三路数据通道保障可靠性：
  - PTY 包装器（`vibebar`）
  - 本地插件事件，通过 `vibebar-agent` 传递
  - `ps` 进程扫描兜底
- 应用内管理 Claude Code、OpenCode 和 GitHub Copilot 插件（安装、卸载、更新）。
- 应用内管理 `vibebar` 包装器命令。
- 多种图标样式、配色主题，支持开机启动和自动更新检查。
- 多语言界面（`English`、`中文`、`日本語`、`한국어`）。

## Token 使用量追踪

VibeBar 可以追踪支持的人工智能工具的 Token 使用量，并提供详细的分析和可视化：

**支持的工具：**
- **Claude Code** — 从 `~/.config/claude/projects/*/usage.jsonl` 读取
- **Codex** — 从 `~/.codex/sessions/*/usage.jsonl` 读取
- **OpenCode** — 从 `~/.local/share/opencode/opencode.db` 读取

**Token 指标：**
- 输入 Token、输出 Token
- 缓存读取 Token、缓存写入 Token
- 总 Token 数和预估成本（USD）

**可视化选项：**
- **GitHub 风格热力图** — 39 周活动矩阵，颜色深浅表示使用量
- **柱状图** — 按时间段显示的堆叠柱状图
- **折线图** — 显示使用量趋势的折线图

**配置选项：**
- 在 **Token** 或 **成本** 视图之间切换
- 调整粒度：小时 / 天 / 周 / 月
- 分组方式：工具 / 模型 / 无
- 设置刷新间隔：5分钟 / 15分钟 / 30分钟 / 1小时
- 自定义显示的最大序列数

通过菜单栏下拉菜单即可查看您的 AI 使用模式和成本概览。

## 项目结构

- `VibeBarCore`：核心模型、存储、聚合、扫描器、插件/包装器检测。
- `VibeBarApp`：macOS 菜单栏应用与设置界面。
- `VibeBarCLI`（`vibebar`）：目标 CLI 的 PTY 包装器。
- `VibeBarAgent`（`vibebar-agent`）：插件事件的本地 Unix Socket 服务器。
- `plugins/*`：Claude Code、OpenCode 和 GitHub Copilot Hooks 插件包。

## 会话检测原理

VibeBar 融合三路数据：

1. `vibebar` PTY 包装器：高精度的交互状态采集。
2. `vibebar-agent` Socket 事件：插件生命周期与状态上报。
3. `ps` 扫描兜底：在前两路数据缺失时，通过进程发现会话。

工具级别的状态优先级：

`running > awaiting_input > idle > stopped > unknown`

运行时数据路径：

- 会话文件：`~/Library/Application Support/VibeBar/sessions/*.json`
- Agent Socket：`~/Library/Application Support/VibeBar/runtime/agent.sock`

## 安装

### 方式一：直接下载（推荐）

1. 从 [GitHub Releases](https://github.com/yelog/VibeBar/releases) 下载最新的 `VibeBar-*-universal.dmg`。
2. 将 `VibeBar.app` 拖入「应用程序」文件夹。
3. 首次启动时右键点击应用，选择**打开**（绕过 Gatekeeper）。

### 方式二：Homebrew

添加此仓库为 tap 后安装：

```bash
brew tap yelog/vibebar https://github.com/yelog/vibebar.git
brew install --cask yelog/vibebar/vibebar
```

**升级：**

```bash
brew upgrade --cask yelog/vibebar/vibebar
```

### 方式三：从源码构建

环境要求：macOS 13+、Xcode Command Line Tools、Swift 6.2。

```bash
swift build
```

## 快速上手（源码构建）

1. 启动应用：

```bash
swift run VibeBarApp
```

2. 启动 Agent（推荐，用于接收插件事件）：

```bash
swift run vibebar-agent --verbose
```

3. 为 Claude/OpenCode 安装本地插件：

```bash
bash scripts/install/setup-local-plugins.sh
```

4. 安装 GitHub Copilot Hooks 插件（如使用 Copilot）：

打开 **VibeBar 设置 → 插件 → GitHub Copilot → 安装**，VibeBar 会自动将 `hooks.json` 部署到当前所有运行中的 Copilot 项目目录。

5. 通过包装器运行 Codex（推荐方式）：

```bash
swift run vibebar codex -- --model gpt-5-codex
```

6. 通过包装器运行 Aider（推荐方式）：

```bash
swift run vibebar aider -- --model sonnet
```

7. 可选：将 Aider 通知转发到 VibeBar 状态更新：

```bash
aider --notifications --notifications-command "vibebar notify aider awaiting_input"
```

8. 通过包装器运行 Gemini CLI：

```bash
swift run vibebar gemini -p "explain this codebase"
```

对于 Gemini 提示/无头调用（`-p`、`--prompt`、`--stdin` 或非 TTY stdin），`vibebar` 会自动添加 `--output-format stream-json`（除非您已提供 `--output-format`）。

Gemini hooks 集成示例（`.gemini/settings.json`）：

```json
{
  "hooks": {
    "SessionStart": [{
      "matcher": "*",
      "hooks": [{ "type": "command", "command": "vibebar notify gemini session_start session_id=$GEMINI_SESSION_ID" }]
    }],
    "AfterAgent": [{
      "matcher": "*",
      "hooks": [{ "type": "command", "command": "vibebar notify gemini after_agent session_id=$GEMINI_SESSION_ID" }]
    }],
    "SessionEnd": [{
      "matcher": "*",
      "hooks": [{ "type": "command", "command": "vibebar notify gemini session_end session_id=$GEMINI_SESSION_ID" }]
    }]
  }
}
```

9. 可选兜底：在插件不可用时，通过包装器运行 Claude/OpenCode：

```bash
swift run vibebar claude
swift run vibebar opencode
```

插件文档：

- `plugins/README.md`
- `plugins/claude-vibebar-plugin/README.md`
- `plugins/opencode-vibebar-plugin/README.md`
- `plugins/copilot-vibebar-hooks/README.md`

## 开发常用命令

```bash
# 构建
swift build
swift build -c release

# 运行
swift run VibeBarApp
swift run vibebar-agent --verbose
swift run vibebar codex

# 测试（占位）
swift test
```

打包 universal `.dmg`：

```bash
bash scripts/build/package-app.sh
```

## 常见问题排查

- **菜单栏没有图标**：确认当前是本地 macOS GUI 会话，而非无头模式或 SSH 连接。
- **会话残留**：点击菜单中的 **Purge Stale** 清理，并检查上方的会话文件路径。
- **收不到插件事件**：确认 `vibebar-agent` 已运行，并查看 Socket 路径：

```bash
swift run vibebar-agent --print-socket-path
```

## 已知局限

- 未安装插件时，「等待输入」状态的检测依赖启发式规则，准确度有限。
- Codex 目前暂无插件事件通道。
- Aider 目前暂无原生插件事件通道；使用 `vibebar notify` 通过 `--notifications-command` 可获得更好的等待输入检测。
- Gemini CLI 转录解析仅作为辅助；它增强 hooks/进程检测，不应被视为主要实时数据源。
- GitHub Copilot Hooks 是 per-repo 的：每个项目的 `.github/hooks/` 目录下需有 `hooks.json`。VibeBar 在点击**安装**时会自动部署，但安装后新打开的项目需再次点击**安装**，或手动复制该文件。
- 自动化测试覆盖还比较薄弱。

## 致谢

本项目受到 [ccusage](https://github.com/ryoppippi/ccusage) 的启发。感谢 [@ryoppippi](https://github.com/ryoppippi) 的出色创意和实现。
