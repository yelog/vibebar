# @vibebar/claude-plugin

Claude Code 插件（Hooks 驱动），把会话状态推送到本机 `vibebar-agent`。

## 目录结构

- `.claude-plugin/plugin.json`: 插件元数据
- `hooks/hooks.json`: Hook 配置
- `scripts/emit.js`: Hook 事件 -> VibeBar 事件转换与上报

## 本地验证

```bash
# 只在当前命令启用插件
claude --plugin-dir /ABSOLUTE/PATH/TO/VibeBar/plugins/claude-vibebar-plugin
```

## 安装到 Claude Code

```bash
claude plugin install /ABSOLUTE/PATH/TO/VibeBar/plugins/claude-vibebar-plugin
claude plugin enable vibebar-claude
```

## 环境变量

- `VIBEBAR_AGENT_SOCKET`: 自定义 agent socket 路径

## 前置

先启动 agent：

```bash
swift run vibebar-agent --verbose
```
