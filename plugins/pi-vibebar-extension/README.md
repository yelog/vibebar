# Pi / Oh My Pi VibeBar Extension

面向 Pi 与 Oh My Pi (OMP) 的 VibeBar 状态上报扩展。

## 工作原理

扩展监听 Pi/OMP 的运行生命周期事件（`session_start`、`input`、`agent_start`、
`message_update`、`tool_execution_start/update`、settled 事件、`session_shutdown`），
将状态与元数据编码为 VibeBar Agent 现有的 `AgentEvent` 协议，通过 Unix socket
发送给 `vibebar-agent`。

Pi 与 OMP 共用 `runtime.js`，仅入口适配器（`pi/index.ts`、`omp/index.ts`）不同：

- Pi：`settledEvent = "agent_settled"`
- OMP：`settledEvent = "session_stop"`

## 安装方式

**不要手动复制本目录。** 请在 VibeBar 设置页的 CLI 检测方法中安装扩展：

- Pi 安装到 `~/.pi/agent/extensions/vibebar/`
- OMP 安装到 `~/.omp/agent/extensions/vibebar/` 以及安装时已存在的
  `~/.omp/profiles/<name>/agent/extensions/vibebar/`

新建 OMP profile 后，请在设置页再次点击“更新”以同步新 profile。

## 卸载

在 VibeBar 设置页卸载。卸载只会删除带 `vibebar.json` 管理标记的目录，
不会影响用户自己的扩展。

## 事件发送

- `message_update` 以约 500ms 合并限流，摘要截断到 200 字符。
- Socket 不可用时静默失败，不影响 Pi/OMP 主进程。

## 本地测试

```bash
node --check plugins/pi-vibebar-extension/runtime.js
node --test plugins/pi-vibebar-extension/runtime.test.js
```
