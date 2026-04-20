# Claude Retry Summary Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 让 Claude 会话在存在 transcript 重试系统事件时显示“多久后重试”的运行摘要，并避免列表里把最后一条用户输入重复显示两次。

**Architecture:** 在 `ClaudeTranscriptDetector` 中为 transcript `system` 行增加受限解析，只提取带 `retryInMs` / `retryAttempt` / `maxRetries` 的重试事件，并在其仍代表当前运行态时写入 `runningSummary`。展示层继续优先显示 `lastUserMessage`，但若 `runningSummary` 或 `currentTask` 与用户输入重复，则直接抑制该摘要，让第三行回退为目录。补充本地化键与两组回归测试。

**Tech Stack:** Swift 6.2, Swift Testing, VibeBarCore, VibeBarApp

---

### Task 1: 为 Claude transcript 增加重试摘要解析

**Files:**
- Modify: `Sources/VibeBarCore/ClaudeTranscriptDetector.swift`

**Step 1:** 扩展 `TranscriptInfo`，让 detector 能返回 `runningSummary`。

**Step 2:** 在 `parseTranscript` 中识别 Claude transcript 的 `system` 行，提取 `retryInMs`、`retryAttempt`、`maxRetries`。

**Step 3:** 仅当该重试事件仍是当前最新运行信号时，把它转换成 `runningSummary`，避免把历史重试摘要遗留到已结束轮次。

**Step 4:** 当 detector 能得到 `runningSummary` 时，让 `currentTask` 优先使用该摘要，而不是继续回退到最后一条用户消息。

### Task 2: 为重试摘要补充本地化字符串

**Files:**
- Modify: `Sources/VibeBarCore/L10nStrings.swift`

**Step 1:** 新增 Claude 重试摘要格式化 key。

**Step 2:** 为中英日韩补充对应翻译，格式统一为“重试倒计时 + 当前重试次数/最大次数”。

### Task 3: 在展示层抑制重复副标题

**Files:**
- Modify: `Sources/VibeBarApp/SessionDisplayFormatter.swift`

**Step 1:** 调整 `runningSummaryText(for:)`，当候选摘要与 `sessionName` 或 `lastUserMessage` 相同的时候返回 `nil`。

**Step 2:** 保持现有 Codex 低信号标签抑制逻辑不变，避免扩大影响面。

### Task 4: 增加回归测试

**Files:**
- Modify: `Tests/VibeBarCoreTests/ClaudeTranscriptDetectorTests.swift`
- Modify: `Tests/VibeBarAppTests/SessionCompactDetailLineBuilderTests.swift`

**Step 1:** 新增 detector 测试，验证 Claude transcript 的 `system` retry 事件会产生 `runningSummary`。

**Step 2:** 新增列表构建测试，验证当 `currentTask == lastUserMessage` 且没有独立 `runningSummary` 时，第三行不再重复用户输入。

### Task 5: 运行验证

**Files:**
- Modify: `none`

**Step 1:** 运行 `swift test --filter ClaudeTranscriptDetectorTests`。

**Step 2:** 运行 `swift test --filter SessionCompactDetailLineBuilderTests`。

**Step 3:** 若两组定向测试通过，再运行 `swift build`。

**Step 4:** 记录仍无法精确显示 `Germinating...` 的原因：现有 transcript 不暴露该 UI 文案，只能显示结构化 retry 摘要。
