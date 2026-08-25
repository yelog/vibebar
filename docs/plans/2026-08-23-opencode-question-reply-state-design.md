# OpenCode Question Reply State Design

**Date:** 2026-08-23

**Status:** Confirmed

## Goal

让用户在 VibeBar 中回答 OpenCode Question 后，答案完整、可靠地送达 OpenCode，并让 VibeBar 只在 OpenCode 确认处理后退出 `awaiting_input`，避免短暂显示 `running` 后再次回到等待状态。

## Findings

当前单问题回写链路可以工作。现场验证中，VibeBar 提交的 Question 选项被 OpenCode 日志记录为对应 request 的 `replied` 事件。因此 socket、agent、插件及基于真实 `serverUrl` 的 HTTP fallback 并非全部失效。

现有行为仍有两个结构性缺陷。

### Premature Local Resolution

`InteractionActionHandler.submit` 返回成功，只能证明 App 已把 `interaction_response` 写入 agent socket。它不能证明插件已经调用 OpenCode reply API，更不能证明 OpenCode 已解除 pending request。

`MonitorViewModel.resolveInteraction` 当前在 socket 提交成功后立即调用 `applyResolvedInteractionLocally`：

- 删除本地 pending interaction；
- 清除 `pendingInteractionID`；
- 把 session 从 `awaiting_input` 改为 `running`。

如果插件随后无法完成 OpenCode reply，它会重新排队并再次发送同一个 interaction。App 下一次刷新又会恢复 pending interaction，于是用户看到：

```text
awaiting_input -> running -> awaiting_input
```

这里的 `running` 是乐观状态，不代表 OpenCode 已经继续执行。

### Incomplete Question Representation

OpenCode 的一个 Question request 可以包含多个 question，并要求按原顺序提交 `answers: string[][]`。当前插件只读取 `properties.questions[0]`，只展示和提交第一个问题。

对于多问题 request，当前实现会生成不完整的 answers。即使网络请求成功，也不能保证 OpenCode 已完成整个 request。

## Decision

采用“真实确认状态机 + 完整 Question 模型”。

1. 插件完整转换 OpenCode request 中的所有 questions。
2. App 收集所有必填答案，并按稳定 prompt key 写入 decision metadata。
3. 插件按原始 question 顺序重建 `answers: string[][]`。
4. App 把 decision 写入 agent 后不再乐观删除 OpenCode interaction。
5. 只有插件确认 OpenCode reply 成功并发送 ack，或收到 OpenCode 的 `question.replied` / `question.rejected` 事件后，agent 才清理 pending interaction。
6. reply 失败时 interaction 保持 pending，session 保持 `awaiting_input`，允许用户重试。

## Data Model

继续复用现有 `PendingInteraction` 和 `InteractionPrompt`，不引入新的公共协议类型。

每个 OpenCode question 映射成一个 `InteractionPrompt`：

- `id`: 稳定的数组位置 key，例如 `question.0`；
- `title`: OpenCode question 的 header；
- `options`: 原始 options，option ID 在该 prompt 内稳定；
- `allowsFreeText`: 对应 OpenCode `custom` 或兼容旧事件中的 `text`；
- `allowsMultipleSelection`: 对应 OpenCode `multiple`；
- `metadata`: 保留原始 question index，供插件严格恢复顺序。

为保持当前单问题紧凑 UI，只有一个 question 时可以继续填充顶层 `title`、`message`、`options` 和 `allowsFreeText`。`prompts` 仍作为规范化的完整表示。

App 使用现有 metadata 约定回传答案：

```text
answer.question.0=<selected label or free text>
answer.question.1=<selected values>
```

多选答案需要使用无歧义的结构化编码，不能依靠显示文本中的逗号拆分。优先在 metadata 中保存 JSON 字符串数组，插件同时兼容单值字符串。

## State Flow

### Submission

```text
OpenCode question.asked
  -> plugin sends interaction_request
  -> agent persists pending interaction
  -> App displays awaiting_input
  -> user submits all answers
  -> App sends interaction_response to agent
  -> agent wakes the waiting plugin request
  -> App keeps the interaction pending
```

App 不再把 agent socket 写入成功解释为 OpenCode reply 成功。

### Confirmation

```text
plugin receives decision
  -> plugin validates and reconstructs all answers
  -> plugin calls ctx.client question API when available
  -> otherwise plugin calls the current serverUrl HTTP endpoint
  -> OpenCode accepts reply
  -> plugin sends ack-only interaction_response
  -> agent deletes persisted interaction and clears pendingInteractionID
  -> OpenCode progress events determine running or idle
```

`question.replied` 和 `question.rejected` 事件继续作为幂等确认路径。如果该事件先于 reply Promise 完成，插件必须只确认和清理一次。

### Failure

如果 SDK/HTTP reply 失败：

- 不发送成功 ack；
- 不删除 interaction；
- 不发送虚假的 `running`；
- 保持或重新发布 `awaiting_input`；
- 记录 request ID、使用的 transport 和安全的错误摘要；
- 允许同一 decision 自动重试或由用户再次提交。

## Transport Compatibility

插件优先使用运行时 `ctx.client.question.reply` / `reject`。旧插件 client 没有 question 分组 API 时，使用插件初始化时提供的真实 `serverUrl` 调用官方接口：

```text
POST /question/{requestID}/reply
POST /question/{requestID}/reject
```

reply body 为：

```json
{"answers":[["answer one"],["answer two"]]}
```

不得把默认 `127.0.0.1:4096` 作为主要路径；它只能是明确标记的最后兼容 fallback，因为 TUI server 可能使用不同端口。

HTTP 2xx 只表示 API 调用被接受。最终清理仍需通过插件 ack 或 OpenCode replied/rejected 事件完成。

## UI Behavior

提交后保持当前 interaction 可识别，但应防止重复快速点击。最小实现可以禁用答案控件并显示提交中状态；如果暂不新增显式 UI 状态，也必须保留 `awaiting_input`，直到收到真实确认。

失败后恢复可交互状态，并通过现有错误提示能力告知用户提交未被 OpenCode 接受。不能仅播放提示音后丢失上下文。

## Idempotency

插件以完整 VibeBar interaction ID 和 OpenCode request ID 去重：

- 重复 `question.asked` 不创建第二个活动项；
- decision 重试不得产生不同 answers；
- `question.replied`、reply Promise 成功和 ack 重复到达时只清理一次；
- late response 不得清除同 session 中更新的 interaction。

agent 必须继续按 request ID 路由响应，不能只按 session ID 确认。

## Scope

预计修改：

- `plugins/opencode-vibebar-plugin/index.js`
- `plugins/opencode-vibebar-plugin/index.test.js`
- `Sources/VibeBarApp/AppModel.swift`
- `Sources/VibeBarApp/SessionInteractionContentView.swift`
- 与 OpenCode interaction decision 和状态合并相关的测试

除非测试证明 agent 当前 ack 时序不满足设计，否则不扩大修改 `InteractionBrokerState` 或 socket 协议。

## Verification

自动测试至少覆盖：

- 单问题单选成功；
- 单问题自由文本成功；
- 单问题多选成功；
- 多问题按原顺序生成完整 answers；
- 新 SDK question API 路径；
- 旧 client + 真实 `serverUrl` HTTP fallback；
- reply 失败时不 ack、不切换 running、interaction 保持 pending；
- `question.replied` 先于 reply Promise 的竞态；
- 重复 `question.asked` 幂等；
- App 提交 decision 后不会乐观移除 OpenCode interaction；
- ack 后 interaction 被移除，后续真实状态可以进入 running 或 idle。

手工验收：

1. 在 OpenCode 触发一个单问题 request，从 VibeBar 选择答案，确认 OpenCode 立即继续。
2. 触发包含两个 question 的 request，在 VibeBar 完成所有答案，确认 OpenCode 收到完整二维 answers。
3. 临时制造 reply transport 失败，确认 VibeBar 始终保持等待且允许重试，不出现短暂 running。
4. 恢复 transport 后重试，确认只执行一次 reply，且 interaction 正常消失。
