# Codex Session Name Semantics Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 让 Codex session 仅在存在显式 `session name` 时显示标题，避免把最后一次用户输入误当成第一行会话名。

**Architecture:** 收紧 Codex 数据语义，让 `title` 只承载显式命名；把用户输入稳定放入 `lastUserMessage`，把 agent 进度放入 `runningSummary/currentTask`。UI 已经支持三行展示，因此重点是 detector、hook 聚合和测试收口。

**Tech Stack:** Swift 6.2、Swift Testing、SwiftUI、AppKit、VibeBarCore、VibeBarAgent

---

### Task 1: Tighten Codex Detector Title Semantics

**Files:**
- Modify: `Sources/VibeBarCore/CodexSessionDetector.swift`
- Test: `Tests/VibeBarCoreTests/CodexSessionDetectorTests.swift`

**Step 1: Write the failing test**

新增测试，断言没有 `thread_name` 的 Codex session 保持 `title == nil`，同时 `lastUserMessage/currentTask` 仍可用。

**Step 2: Run test to verify it fails**

Run: `swift test --filter codexSessionDetectorUsesFirstUserMessageAsDerivedSessionName`
Expected: FAIL，因为当前 detector 仍会把 user message 写进 `title`。

**Step 3: Write minimal implementation**

移除 Codex detector 的 derived title 回退，仅保留显式 `thread_name` 作为 `title`。

**Step 4: Run test to verify it passes**

Run: `swift test --filter CodexSessionDetectorTests`
Expected: PASS

### Task 2: Tighten Codex Hook Snapshot Semantics

**Files:**
- Modify: `Sources/VibeBarAgent/main.swift`
- Test: `Tests/VibeBarAppTests/AppModelTests.swift`

**Step 1: Write the failing test**

新增测试，断言 Codex hook/plugin session 在只有 prompt、没有显式 session name 时，合并 detector 结果后第一行来自显式 title 或最终回退为未命名，而不是 prompt。

**Step 2: Run test to verify it fails**

Run: `swift test --filter AppModelTests`
Expected: FAIL，因为当前 hook 仍可能把 prompt/message 固化成 `title`。

**Step 3: Write minimal implementation**

限制 `resolveTitle` 对 Codex 只读取显式 title keys，不再从 `prompt/message` 生成 derived title。

**Step 4: Run test to verify it passes**

Run: `swift test --filter AppModelTests`
Expected: PASS

### Task 3: Lock Display To Three Distinct Codex Rows

**Files:**
- Modify: `Sources/VibeBarApp/SessionDisplayFormatter.swift`
- Test: `Tests/VibeBarAppTests/SessionDisplayFormatterTests.swift`

**Step 1: Write the failing test**

新增测试，断言无显式标题的 Codex session 第一行显示 `未命名会话`，第二行显示 `lastUserMessage`，第三行显示 `runningSummary/currentTask`。

**Step 2: Run test to verify it fails**

Run: `swift test --filter SessionDisplayFormatterTests`
Expected: FAIL，如果仍有标题回退混入第一行。

**Step 3: Write minimal implementation**

只在 Codex 上收紧 `sessionName` 回退规则，避免把 prompt/currentTask 误提升为标题；保持其它工具现有行为不变。

**Step 4: Run test to verify it passes**

Run: `swift test --filter SessionDisplayFormatterTests`
Expected: PASS

### Task 4: Focused Verification

**Files:**
- Review only

**Step 1: Run focused test suite**

Run: `swift test --filter CodexSessionDetectorTests`
Run: `swift test --filter AppModelTests`
Run: `swift test --filter SessionDisplayFormatterTests`

**Step 2: Run broader suite if needed**

Run: `swift test`
Expected: PASS or only unrelated pre-existing failures
