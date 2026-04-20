# Claude Retry Summary Design

**Goal:** 修复 Claude 会话列表在只有最后一条用户输入时出现重复副标题的问题，并在 Claude transcript 含有重试系统事件时展示可读的运行摘要。

**Architecture:** 保持 `ClaudeTranscriptDetector` 继续以 transcript 作为 Claude 的补充数据源，但额外解析 `system` 行里的重试字段 `retryInMs` / `retryAttempt` / `maxRetries`，把它们转换成 `runningSummary`。展示层不再把与 `lastUserMessage` 相同的 `runningSummary` / `currentTask` 当作独立第三行，从而避免出现两行相同的 `hello`。

**Scope:**
- 修改 `ClaudeTranscriptDetector` 的 transcript 解析逻辑
- 为 Claude 重试摘要增加本地化字符串
- 调整会话展示层对重复副标题的去重逻辑
- 增加 `ClaudeTranscriptDetectorTests` 与 `SessionCompactDetailLineBuilderTests` 回归测试

**Approaches Considered:**

### Approach A: 从 Claude transcript 的 system retry 字段生成运行摘要

优点：
- 基于现有数据源，不需要抓取终端屏幕内容
- `retryInMs` / `retryAttempt` / `maxRetries` 是结构化字段，稳定性高
- 能直接覆盖截图中的 `Retrying in 2s` 类场景

缺点：
- 无法复原 Claude UI 内部那组随机思考词，例如精确的 `Germinating...`
- 只能覆盖 transcript 确实落盘的系统事件

### Approach B: 从 PTY / 终端可见内容直接抓取 `Germinating...`

优点：
- 最接近终端上用户真正看到的文案

缺点：
- 需要解析 ANSI 重绘与临时屏幕状态，脆弱且维护成本高
- 与当前 plugin / transcript 检测架构不一致
- 很难保证多终端和多主题下的稳定性

### Approach C: 只做展示层去重，不补 Claude 重试摘要

优点：
- 改动最小
- 能立即消除重复 `hello`

缺点：
- 仍缺少 Claude 的运行中上下文，用户只能看到最后一条输入
- 不能改善“正在处理什么”的可见性

**Recommendation:** 选择 Approach A，并叠加展示层去重。这样既能解决当前重复 `hello` 的问题，也能在 Claude transcript 提供系统重试信息时展示真实的进行中摘要，而且不引入终端抓屏这类高脆弱度方案。

**Validation:**
- Claude transcript 含 `system` 重试事件时，`SessionSnapshot.runningSummary` 应包含重试倒计时与重试次数
- 有 `lastUserMessage` 且 `currentTask` 与之相同、但没有独立 `runningSummary` 时，第三行应回退为目录而不是重复用户输入
- 现有带独立 `runningSummary` 的会话展示保持不变
- `swift test --filter ClaudeTranscriptDetectorTests`
- `swift test --filter SessionCompactDetailLineBuilderTests`
- `swift build`
