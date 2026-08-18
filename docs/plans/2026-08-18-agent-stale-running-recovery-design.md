# Agent Stale Running Recovery Design

**日期：** 2026-08-18

## 问题

OpenCode 任务已经生成最终 assistant 消息后，VibeBar 仍可能持续显示 `running`。

现场证据表明问题来自一条级联故障链：

- OpenCode 插件每 15 秒向 `vibebar-agent` 发送 heartbeat。
- Agent 处理每个事件时都会构建完整进程快照，用于补充终端上下文。
- 进程快照依赖 `ps -axo ... args=`；当系统进程参数很多时，子进程可能超时。
- `DetectorSupport.ProcessExecution` 在读取输出后调用 `waitUntilExit()`，超时路径可能留下永久阻塞的后台任务。
- Dispatch 工作线程耗尽后，Agent 不再及时消费 socket 连接和事件。
- AppModel 只要发现插件会话 PID 仍然存活，就永久保留最后一次插件状态。因此最后落盘的 `running` 不会自行恢复。

## 目标

- 子进程超时不能泄漏线程或文件描述符。
- heartbeat 处理不再重复执行全量进程扫描。
- OpenCode 最终 assistant 消息可以直接结束运行态。
- 插件事件链路中断后，VibeBar 可以通过可靠的 OpenCode 状态源恢复为 `idle`。
- 不使用单纯的短 TTL 把正常长任务误判为空闲。

## 备选方案

1. 只修 OpenCode 插件，根据 assistant `finish` 设置 `idle`。
   - 优点：改动小，能覆盖正常完成路径。
   - 缺点：Agent 线程泄漏仍会影响所有工具；完成事件也可能无法送达。
2. 只修进程执行器和 Agent 热路径。
   - 优点：解决主要基础设施故障。
   - 缺点：状态源中断后仍缺少业务层自愈能力。
3. 同时修复进程执行、事件热路径和 OpenCode 状态自愈。
   - 优点：消除根因，并为状态源故障提供可靠兜底。
   - 缺点：涉及 Core、Agent、App 和插件，但每层改动都可以保持局部且可测试。

## 决策

采用方案 3。

## 设计

### 1. 保证子进程执行收敛

调整 `DetectorSupport.ProcessExecution`：

- stdout 继续并发排空，避免管道容量导致子进程阻塞。
- stderr 不再连接到无人读取的 `Pipe`。
- stdout 到达 EOF 后不再调用可能永久等待的 `waitUntilExit()`。
- 超时后先 terminate，再在宽限期后 kill；读取任务必须在管道关闭后结束。
- 加入超时回归测试，确认多次超时不会持续占用工作线程。

### 2. 移除 heartbeat 热路径中的全量进程扫描

Agent 解析终端上下文时按以下优先级工作：

1. 使用事件 metadata 中的 `_tty`、终端环境变量和 bundle identifier。
2. 与已经落盘的 `terminalContext` 合并。
3. 只有首次事件、metadata 不能解析出有效上下文时，才查询进程链。

OpenCode 插件已经发送 Kitty、Ghostty、WezTerm、tmux 和 zellij 所需信息，因此正常 heartbeat 不需要调用 `ps`。

### 3. 使用 assistant finish 补充 OpenCode 完成信号

OpenCode 插件处理 `message.updated` 时：

- 保存 message role。
- assistant 的 `finish=tool-calls` 表示仍会继续执行，保持 `running`。
- assistant 出现其他非空 finish 值时，若没有待处理交互，则发送 `idle`。
- 有待处理交互时继续保持 `awaiting_input`。

`session.status=idle` 和 `session.idle` 仍然保留，不依赖单一事件类型。

### 4. 对过期 running 做可靠校正

插件 session 的 PID 存活仅表示 OpenCode shell 仍然打开，不代表模型仍在生成。

当插件 session 为 `running` 且 heartbeat 已经过期时：

- 如果同 PID 的 HTTP detector 明确返回 `idle`，采用该状态。
- SQLite fallback 读取最近 assistant message 的 `finish`；明确终态时返回 `idle`。
- 无可靠终态证据时保留 `running`，避免仅凭 TTL 或瞬时 CPU 使用率误判长任务。
- `awaiting_input` 继续由 pending interaction 状态保护。

### 5. 恢复与兼容

- 当前已卡住的 Agent 需要重启一次，释放已有阻塞线程和 socket。
- 不修改 SessionSnapshot 持久化格式。
- 不改变 Claude、Codex 等工具的状态优先级。
- SQLite 查询失败时退回现有启发式，不影响 OpenCode 启动。

## 测试策略

- 为进程执行器增加成功、超时和连续超时测试。
- 为 Agent 终端上下文解析增加“已有上下文的 heartbeat 不扫描进程”测试。
- 为 OpenCode 插件增加 `finish=tool-calls`、`finish=stop` 和 pending interaction 测试。
- 为 SQLite detector 增加最终 assistant message 终态测试。
- 为 AppModel 合并增加 stale plugin running 被可靠 idle 信号校正的测试。
- 运行 `swift test` 和 `node --test plugins/opencode-vibebar-plugin/index.test.js`。
- 本机重启 Agent 后连续观察 heartbeat，确认线程数、socket 数和 session 文件更新时间稳定。

## 非目标

- 不通过降低 heartbeat 频率掩盖资源泄漏。
- 不把所有 PID 存活的 OpenCode 会话都显示为运行中。
- 不使用固定 TTL 无条件结束长任务。
