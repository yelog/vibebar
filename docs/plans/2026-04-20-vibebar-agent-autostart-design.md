# VibeBar Agent Auto-Start Design

**日期：** 2026-04-20

**问题**

`swift run VibeBarApp` 以源码模式启动时不会自动拉起 `vibebar-agent`。OpenCode 插件虽然仍会把 `question.asked` / `permission.asked` 发往 `~/Library/Application Support/VibeBar/runtime/agent.sock`，但当本地只有一个遗留 socket 文件、没有真实 listener 时，请求会直接失败并被插件吞掉。此时 VibeBar 只能退回 OpenCode 的 HTTP/SQLite fallback，而该 fallback 当前只能给出 `running` / `idle`，因此会出现终端已显示选项、VibeBar 仍显示运行中的错误状态。

**目标**

- `swift run VibeBarApp` 与发布版 `.app` 都保证 `vibebar-agent` 可用。
- 遇到遗留且不可连接的 `agent.sock` 时自动自愈。
- 不修改 OpenCode 插件协议，不改变 SQLite fallback 的状态语义。

**方案**

1. 在 `VibeBarApp` 启动时统一执行“确保 agent 可用”流程，而不是只在发布模式执行。
2. 将 agent 检查与启动逻辑从 `AppDelegate` 中抽成独立协调器，方便单测。
3. 协调器按以下顺序判断：
   - 若存在可连接的 socket，认为 agent 可用，不重复启动。
   - 若存在 `vibebar-agent` 进程但 socket 不可连接，不做删除，避免误清理他人实例；仅记录失败并交由后续人工处理。
   - 若不存在存活进程，且 socket 文件存在但连接失败，则删除遗留 socket，再启动新的 agent。
   - 若既无进程也无 socket，直接启动新的 agent。
4. `AppDelegate` 只负责调用协调器并持有由当前 App 拉起的 agent `Process`，终止时仍只结束自己创建的子进程。

**实现边界**

- 不修改 `plugins/opencode-vibebar-plugin/index.js` 的发送/回复路径。
- 不修改 `OpenCodeHTTPDetector` 的 SQLite fallback。
- 不引入新的后台守护进程或 LaunchAgent。

**测试策略**

- 为协调器编写纯逻辑测试，覆盖：
  - 可连接 socket 时不启动。
  - 无进程 + 断开的遗留 socket 时会清理并启动。
  - 有进程 + 断开的 socket 时不清理、不启动。
  - 启动失败时返回失败结果，不崩溃 App。
- 维持现有 `AppDelegate` 行为最小化，避免 AppKit 生命周期测试。

**风险**

- `pgrep -f vibebar-agent` 只能判断进程名，无法证明该进程一定监听当前默认 socket；这次设计仍采用保守策略，优先避免误删真实实例的 socket。
- 源码模式与发布模式都自动确保 agent 可用后，若用户手工运行多个 App 实例，仍可能存在竞争，但现有 `pgrep + socket` 判定足以覆盖单机常规使用场景。
