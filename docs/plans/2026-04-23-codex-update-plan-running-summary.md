# Codex Update Plan Running Summary Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 让 Codex 会话在项目分组下也能稳定显示第三行“正在进行中的计划步骤”，避免 rollout 已有高信号任务信息但列表仍为空白。

**Architecture:** 保持现有三行 UI 和合并逻辑不变，只在 `CodexSessionDetector` 中从 rollout 的 `update_plan` 工具调用里提取 `in_progress` 步骤，并写入 `SessionSnapshot.runningSummary`。这样显示层继续消费现有字段，风险最小，且不会把工具名或标题误当成运行内容。

**Tech Stack:** Swift 6.2, Foundation, Testing

---

### Task 1: 为 Codex rollout 提取计划中的进行中步骤

**Files:**
- Modify: `Sources/VibeBarCore/CodexSessionDetector.swift`
- Test: `Tests/VibeBarCoreTests/CodexSessionDetectorTests.swift`

**Step 1: Write the failing test**

Add a detector test fixture with a rollout containing:

```json
{"timestamp":"2026-04-04T12:00:02Z","type":"response_item","payload":{"type":"function_call","name":"update_plan","arguments":"{\"plan\":[{\"step\":\"梳理链路\",\"status\":\"completed\"},{\"step\":\"补齐第三行摘要\",\"status\":\"in_progress\"},{\"step\":\"回归测试\",\"status\":\"pending\"}]}","call_id":"call-plan"}}
```

Assert:

```swift
#expect(session.runningSummary == "补齐第三行摘要")
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter codexSessionDetectorExtractsRunningSummaryFromUpdatePlan`
Expected: FAIL because `runningSummary` is currently `nil`

**Step 3: Write minimal implementation**

In `CodexSessionDetector.RolloutSummary`, add a `runningSummary: String?` field.

In `summarizeRollout(fileURL:)`:

```swift
if entryType == "response_item",
   let responseType = payload?["type"] as? String,
   responseType == "function_call",
   (payload?["name"] as? String) == "update_plan" {
    current.runningSummary = extractInProgressPlanStep(from: payload?["arguments"] as? String) ?? current.runningSummary
}
```

Add a small helper that:

```swift
private func extractInProgressPlanStep(from rawArguments: String?) -> String? {
    guard let rawArguments,
          let data = rawArguments.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let plan = json["plan"] as? [[String: Any]] else {
        return nil
    }

    for item in plan {
        guard (item["status"] as? String) == "in_progress",
              let step = normalized(item["step"] as? String) else {
            continue
        }
        return step
    }
    return nil
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter codexSessionDetectorExtractsRunningSummaryFromUpdatePlan`
Expected: PASS

### Task 2: 将提取结果写入会话快照

**Files:**
- Modify: `Sources/VibeBarCore/CodexSessionDetector.swift`
- Test: `Tests/VibeBarCoreTests/CodexSessionDetectorTests.swift`

**Step 1: Write the failing test**

If Task 1 only proves rollout summary extraction indirectly, add or extend the detector assertion so the final `SessionSnapshot` includes the same summary after `makeSessionSnapshot(...)`.

Assert:

```swift
#expect(session.runningSummary == "补齐第三行摘要")
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter codexSessionDetectorParsesRunningSummaryIntoSnapshot`
Expected: FAIL if the rollout summary is not copied into the snapshot constructor

**Step 3: Write minimal implementation**

Update `makeSessionSnapshot(...)` to pass the rollout-derived summary into `SessionSnapshot`:

```swift
runningSummary: rollout?.runningSummary,
```

Keep all existing title, last user message, and status behavior unchanged.

**Step 4: Run test to verify it passes**

Run: `swift test --filter codexSessionDetectorParsesRunningSummaryIntoSnapshot`
Expected: PASS

### Task 3: 覆盖无效和无进行中步骤的回退场景

**Files:**
- Modify: `Tests/VibeBarCoreTests/CodexSessionDetectorTests.swift`

**Step 1: Write the failing tests**

Add two tests:

```swift
@Test func codexSessionDetectorIgnoresUpdatePlanWithoutInProgressStep() async throws
@Test func codexSessionDetectorIgnoresInvalidUpdatePlanArguments() async throws
```

Assert:

```swift
#expect(session.runningSummary == nil)
#expect(session.status == .running)
#expect(session.lastUserMessage == "修复状态检测")
```

**Step 2: Run tests to verify they fail**

Run: `swift test --filter CodexSessionDetectorTests`
Expected: FAIL until fallback behavior is implemented or verified

**Step 3: Write minimal implementation**

Make the parser strictly best-effort:

```swift
guard let data = rawArguments.data(using: .utf8) else { return nil }
guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
```

Do not synthesize summaries from `completed` or `pending` steps.

**Step 4: Run tests to verify they pass**

Run: `swift test --filter CodexSessionDetectorTests`
Expected: PASS

### Task 4: Run build-level verification

**Files:**
- None

**Step 1: Run targeted detector tests**

Run: `swift test --filter CodexSessionDetectorTests`
Expected: PASS

**Step 2: Run full build**

Run: `swift build`
Expected: BUILD SUCCEEDED

**Step 3: Verify no display-layer changes are needed**

Confirm the existing flow still applies:

- `Sources/VibeBarApp/SessionDisplayFormatter.swift`
- `Sources/VibeBarApp/SessionSupplementalLineSupport.swift`

Expected: no code changes required because row 3 already renders `runningSummary`

**Step 4: Summarize validation and remaining risk**

Document that this plan only covers rollout-based `update_plan` extraction. Hook-only summary extraction remains out of scope.
