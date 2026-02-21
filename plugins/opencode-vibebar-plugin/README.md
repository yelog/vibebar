# @vibebar/opencode-plugin

把 OpenCode 会话状态推送到本机 `vibebar-agent`。

## 安装（本地开发）

在 `~/.config/opencode/opencode.json` 或项目内 `.opencode/opencode.json` 添加：

```json
{
  "plugin": [
    "/ABSOLUTE/PATH/TO/VibeBar/plugins/opencode-vibebar-plugin"
  ]
}
```

## 安装（npm 包）

发布后可以直接写包名：

```json
{
  "plugin": [
    "@vibebar/opencode-plugin"
  ]
}
```

## 环境变量

- `VIBEBAR_AGENT_SOCKET`: 自定义 agent socket 路径
- `VIBEBAR_PLUGIN_HEARTBEAT_MS`: 心跳间隔（毫秒，默认 `15000`）

## 依赖前置

先启动 agent：

```bash
swift run vibebar-agent --verbose
```
