# OpenCode Awaiting Input Reliability Design

**日期：** 2026-04-23

**问题**

OpenCode 在出现选项时，VibeBar 有时既不展示选项，也不会切换到 `awaiting_input`。根因有两类：

1. `question.asked` / `permission.asked` 主要依赖 `interaction_request` 驱动 UI，插件没有同步发送显式 `awaiting_input` 状态事件。
2. 插件在等待用户选择期间，仍可能被后续 assistant 文本、`busy/retry`、heartbeat 相关进度误判为“已恢复运行”，提前发出 `running`，导致 agent/App 清掉 pending interaction。

**目标**

- OpenCode 一旦出现待用户选择的 interaction，VibeBar 必须稳定进入 `awaiting_input`。
- 在收到显式确认前，后续普通进度事件不能清除等待态。
- 只有显式 `interaction ack` 或 OpenCode 的 `question.replied` / `permission.replied` 才能结束等待态。
- 尽量把状态机收口在 OpenCode 插件，避免把补丁逻辑分散到 agent/App。

**备选方案**

1. 插件显式管理等待态，作为唯一真实来源。
   - 优点：状态源单一，和 OpenCode 原始交互最接近。
   - 缺点：需要修改插件状态机与测试。
2. 仅在 agent/App 侧把 pending interaction 做成 sticky。
   - 优点：JS 改动少。
   - 缺点：插件与 UI 状态会分裂，后续更难维护。
3. 只补发 `awaiting_input` 事件，不调整清理逻辑。
   - 优点：改动最小。
   - 缺点：无法解决“选项出现后又被误清”的核心问题。

**决策**

采用方案 1：由 OpenCode 插件统一驱动等待态生命周期。

**设计**

### 1. 插件进入等待态时显式发事件

在 `question.asked` / `permission.asked` 分支中：

- 构造 interaction 后立即发 `status_changed(awaiting_input)`。
- 再把 interaction 入队并发送给 agent。

这样即使后续 UI hydration 稍有延迟，session 文件也会先进入 `awaiting_input`，避免界面继续显示 `running`。

### 2. 插件等待态期间禁止被普通进度恢复

当存在 `activeInteraction` 或 `interactionQueue` 时：

- `message.part.updated` 不允许调用 `markRunningFromProgress()` 将状态恢复为 `running`。
- `session.status = busy/retry` 也不允许把 pending interaction 当作“已外部恢复”。
- heartbeat 继续保留，但不改变等待态。

即：等待态只接受显式交互确认，不接受推断式恢复。

### 3. 显式确认后再退出等待态

退出等待态仅允许通过以下路径：

- agent 回传无 decision 的 `interaction_response` ack
- OpenCode 发出 `question.replied`
- OpenCode 发出 `question.rejected`
- OpenCode 发出 `permission.replied`

这些路径里再执行：

- `removeInteractionID()`
- 清空 active item / 继续处理队列
- 发出 `status_changed(running)`

### 4. Agent/App 保持现有 hydration 结构

Swift 侧不引入新的等待态状态机，只维持现有职责：

- agent 负责落盘 session 和 interaction
- App 负责从 interaction store hydrate `awaiting_input`
- 现有 OpenCode pending merge/resume 逻辑继续保留，作为防御性兜底

本次不把核心修复放在 agent/App，以免出现“插件说 running，但 UI 强行 awaiting”的双重真相。

**测试策略**

### 插件测试

补充 OpenCode 插件交互状态机回归：

- `question.asked` 时发出 `awaiting_input`
- `question.asked -> message.part.updated` 不应提前发 `running`
- `question.asked -> session.status busy` 不应提前发 `running`
- 收到显式 ack / replied 后才发 `running`
- 多个 interaction 排队时，前一个未确认前不能被后续进度冲掉

### Swift 测试

补一到两个回归测试，确认：

- 当 plugin session 仍为 `awaitingInput` 且 interaction 仍存在时，App 不会因为普通进度误清展示
- 现有 OpenCode merge grace 逻辑仍只在明确恢复时才清 pending

**非目标**

- 不修改 OpenCode HTTP/SQLite fallback 的状态语义
- 不改 VibeBar 菜单/Notch 的交互 UI 结构
- 不引入新的后台守护进程或 socket 协议

**备注**

按当前会话约束，本设计文档只写入工作区，不自动创建 git commit。
