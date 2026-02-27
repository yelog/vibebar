# VibeBar

[English](README.md) · **[中文](README_zh.md)** · [日本語](README_ja.md) · [한국어](README_ko.md)

VibeBar 是一款轻量级 macOS 菜单栏应用，可实时监控 **Claude Code**、**Codex**、**OpenCode**、**GitHub Copilot** 的 TUI 会话状态。

<img src="docs/images/vibebar.png" alt="VibeBar 截图" width="600" />

支持多种图标样式和配色方案，可以在设置中按喜好调整。

<img src="docs/images/vibebar-setting.png" alt="VibeBar 设置截图" width="600" />

## 接入方式（重要）

- **Claude Code**：推荐安装 VibeBar 插件。
- **OpenCode**：推荐安装 VibeBar 插件。
- **GitHub Copilot**：推荐安装 VibeBar Hooks 插件，在 **设置 → 插件 → GitHub Copilot → 安装** 中操作。VibeBar 会自动将 `.github/hooks/hooks.json` 部署到当前所有运行中的 Copilot 会话项目目录。安装后新打开的项目需再次点击**安装**，或手动复制 hooks 文件。
- **Codex**：推荐使用 `vibebar` 包装器，因为 Codex 目前没有插件体系。
- `vibebar` 包装器同样支持 `claude` / `opencode` / `copilot`，但这些工具首选插件方式。

## 功能特性

- 菜单栏实时显示多个会话和工具的运行状态。
- 会话状态：`running`（运行中）、`awaiting_input`（等待输入）、`idle`（空闲）、`stopped`（已停止）、`unknown`（未知）。
- 三路数据通道保障可靠性：
  - PTY 包装器（`vibebar`）
  - 本地插件事件，通过 `vibebar-agent` 传递
  - `ps` 进程扫描兜底
- 应用内管理 Claude Code、OpenCode 和 GitHub Copilot 插件（安装、卸载、更新）。
- 应用内管理 `vibebar` 包装器命令。
- 多种图标样式、配色主题，支持开机启动和自动更新检查。
- 多语言界面（`English`、`中文`、`日本語`、`한국어`）。

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

### 方式二：从源码构建

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

6. 可选兜底：在插件不可用时，通过包装器运行 Claude/OpenCode：

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
- GitHub Copilot Hooks 是 per-repo 的：每个项目的 `.github/hooks/` 目录下需有 `hooks.json`。VibeBar 在点击**安装**时会自动部署，但安装后新打开的项目需再次点击**安装**，或手动复制该文件。
- 自动化测试覆盖还比较薄弱。
