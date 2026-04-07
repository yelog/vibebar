# Session Naming In Lists Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 让 VibeBar 所有已支持 Agent Client 的 session 列表首行统一显示 session 名，而不是 `pid`，并在长标题下保持右侧终端 Tag 可见。

**Architecture:** 在 `SessionSnapshot` 增加标题来源标记，统一 `title/currentTask` 的合并优先级；补齐 Codex、Gemini、plugin 事件与 wrapper 的默认命名来源；最后收敛到 `SessionDisplayFormatter` 和两个 UI 入口的统一展示规则。

**Tech Stack:** Swift 6.2、Swift Testing、SwiftUI、AppKit、VibeBarCore session detectors、VibeBarAgent、VibeBarCLI

---

### Task 1: Extend Session Title Model

**Files:**
- Modify: `Sources/VibeBarCore/Models.swift`
- Test: `Tests/VibeBarAppTests/AppModelTests.swift`

**Step 1: Write the failing test**

在 `AppModelTests` 中增加一个测试，构造 `derived` plugin title 与 `explicit` detected title，断言合并后保留 `explicit` 标题。

**Step 2: Run test to verify it fails**

Run: `swift test --filter mergeDetectedDetailsPrefersExplicitSessionNameOverDerivedName`
Expected: FAIL，因为当前模型没有 title source，也不会覆盖较低质量标题。

**Step 3: Write minimal implementation**

在 `SessionSnapshot` 中新增 `SessionTitleSource` 和 `titleSource` 字段，并在 `MonitorViewModel.mergeDetectedDetails` 中按标题质量合并。

**Step 4: Run test to verify it passes**

Run: `swift test --filter mergeDetectedDetailsPrefersExplicitSessionNameOverDerivedName`
Expected: PASS

### Task 2: Fix Cross-Client Name Extraction

**Files:**
- Modify: `Sources/VibeBarCore/CodexSessionDetector.swift`
- Modify: `Sources/VibeBarCore/GeminiTranscriptDetector.swift`
- Modify: `Sources/VibeBarAgent/main.swift`
- Modify: `Sources/VibeBarCLI/main.swift`
- Test: `Tests/VibeBarCoreTests/CodexSessionDetectorTests.swift`
- Test: `Tests/VibeBarCoreTests/GeminiTranscriptDetectorTests.swift`

**Step 1: Write the failing tests**

- Codex：新增未重命名 session 时首行标题取第一条 user message 的测试
- Gemini：新增 transcript 第一条/最近一条 user message 提取测试

**Step 2: Run tests to verify they fail**

Run: `swift test --filter CodexSessionDetectorTests`
Run: `swift test --filter GeminiTranscriptDetectorTests`
Expected: FAIL，因为当前 Codex 用最后一条 user message，Gemini 不提取标题。

**Step 3: Write minimal implementation**

- Codex rollout summary 同时记录 `firstUserMessage` 和 `lastUserMessage`
- Gemini transcript parser 提取首条与最近一条 user message
- `vibebar-agent` 在缺失显式标题时，从 prompt/message 固化 `derived` 标题
- `vibebar` wrapper 尽量从首个 prompt 参数或首个用户输入固化 `derived` 标题

**Step 4: Run tests to verify they pass**

Run: `swift test --filter CodexSessionDetectorTests`
Run: `swift test --filter GeminiTranscriptDetectorTests`
Expected: PASS

### Task 3: Remove PID Fallback From Display Formatter

**Files:**
- Modify: `Sources/VibeBarApp/SessionDisplayFormatter.swift`
- Modify: `Sources/VibeBarCore/L10nStrings.swift`
- Test: `Tests/VibeBarAppTests/SessionDisplayFormatterTests.swift`

**Step 1: Write the failing tests**

增加以下断言：

- `primaryText` 不再回退到 `pid`
- 无 title/currentTask 时显示 `未命名会话`
- `secondaryText` 不再拼接 `pid`

**Step 2: Run test to verify it fails**

Run: `swift test --filter SessionDisplayFormatterTests`
Expected: FAIL，因为当前 formatter 仍输出 `tool + pid`。

**Step 3: Write minimal implementation**

- 新增统一 session 名解析
- 增加 `未命名会话` 本地化
- 把 secondary summary 改成无 `pid` 的辅助信息

**Step 4: Run test to verify it passes**

Run: `swift test --filter SessionDisplayFormatterTests`
Expected: PASS

### Task 4: Update Session Row UI

**Files:**
- Modify: `Sources/VibeBarApp/NotchContentView.swift`
- Modify: `Sources/VibeBarApp/MenuContentView.swift`
- Modify: `Sources/VibeBarApp/StatusItemController.swift`

**Step 1: Implement UI updates**

- Notch 列表首行改为 session 名，并确保右侧 Tag 不被压缩
- MenuContentView 去掉 `pid` 文案，改用 formatter
- AppKit menu row 继续保留 badge 预留宽度，确保标题尾部省略

**Step 2: Build to verify**

Run: `swift test`
Expected: 全部通过

### Task 5: Final Verification

**Files:**
- Review only

**Step 1: Run focused test suite**

Run: `swift test --filter AppModelTests`
Run: `swift test --filter SessionDisplayFormatterTests`
Run: `swift test --filter CodexSessionDetectorTests`
Run: `swift test --filter GeminiTranscriptDetectorTests`

**Step 2: Run full test suite**

Run: `swift test`
Expected: PASS
