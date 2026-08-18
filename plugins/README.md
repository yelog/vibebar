# Plugins Monorepo Layout

本仓库采用 monorepo 管理插件：

- `plugins/opencode-vibebar-plugin`: OpenCode 插件（npm 发布）
- `plugins/claude-vibebar-plugin`: Claude Code 插件（Claude marketplace/source 分发）
- `plugins/pi-vibebar-extension`: Pi / Oh My Pi 共享扩展（由 VibeBar 安装器复制到 `~/.pi/agent/extensions/vibebar` 与 `~/.omp/agent/extensions/vibebar`）

## 本地安装

```bash
bash scripts/install/setup-local-plugins.sh
```

## 发布

OpenCode（npm）：

```bash
bash scripts/release/publish-opencode-plugin.sh
```

Claude（打包产物）：

```bash
bash scripts/release/package-claude-plugin.sh
```
