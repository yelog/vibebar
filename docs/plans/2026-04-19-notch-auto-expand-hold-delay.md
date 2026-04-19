# Notch Auto Expand Hold Delay Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 让状态变更触发的刘海自动展开在鼠标未进入热区时至少保持 3 秒，再恢复现有自动收起逻辑。

**Architecture:** 在 `NotchDisplayController` 内为“状态变更自动展开”增加一个一次性的保留期上下文，而不是修改全局 hover 状态机。保留期负责阻止立即收起，并在到期时重新评估鼠标位置，从而把这次需求限制在自动展开链路内。

**Tech Stack:** Swift 6.2, AppKit, SwiftUI, Foundation, Swift Testing

---

### Task 1: 为自动展开保留期补可测试的时序辅助

**Files:**
- Create: `Tests/VibeBarAppTests/NotchAutoExpandHoldTests.swift`
- Modify: `Sources/VibeBarApp/NotchDisplayController.swift`

**Step 1: Write the failing test**

- 覆盖“开始保留期后，3 秒内不允许自动收起”。
- 覆盖“保留期结束后恢复允许自动收起”。

**Step 2: Run test to verify it fails**

Run: `swift test --filter NotchAutoExpandHoldTests`
Expected: FAIL because there is no helper or hold-window logic to assert against.

**Step 3: Write minimal implementation**

- 在 `NotchDisplayController` 中增加一个最小的可测试时序辅助，负责计算保留期是否仍有效。
- 保持该辅助仅服务于 controller，不扩散到其他层。

**Step 4: Run test to verify it passes**

Run: `swift test --filter NotchAutoExpandHoldTests`
Expected: PASS

### Task 2: 将保留期接入状态变更自动展开链路

**Files:**
- Modify: `Sources/VibeBarApp/NotchDisplayController.swift`

**Step 1: Start hold window on auto expand**

- 在 `expandForStateChange(payload:focusedSessionID:)` 中设置 `autoExpandHoldUntil = now + 3s`。
- 安排一个到期后的重新检查 work item。

**Step 2: Prevent immediate auto-collapse during hold**

- 在 `reconcilePointerPresence()` 或收起调度前判断保留期。
- 若仍在保留期内，忽略这次 `pointerExitedAllZones` 导致的收起。

**Step 3: Re-evaluate after hold expires**

- 到期后重新检查鼠标是否仍在面板区域。
- 若仍不在，则进入现有收起判定；若已进入，则继续交给 hover 逻辑。

**Step 4: Clear hold state when panel is dismissed**

- 在 `collapseImmediately()`、`hide()`、以及其他主动收起路径中清理 hold work item 和截止时间。

### Task 3: 验证交互回归

**Files:**
- Modify: none

**Step 1: Run targeted tests**

Run: `swift test --filter NotchAutoExpandHoldTests`
Expected: PASS

**Step 2: Run app test suite**

Run: `swift test`
Expected: PASS

**Step 3: Build package**

Run: `swift build`
Expected: PASS

**Step 4: Manual verification**

- 触发 `running -> awaitingInput`，确认刘海自动展开并至少停留 3 秒。
- 触发 `running -> idle`，确认行为一致。
- 自动展开后鼠标不动，确认不会在 200ms 内收起。
- 自动展开后 3 秒内把鼠标移入面板，确认面板继续保持展开。
- 点击 Session，确认仍直接跳转终端并收起。
- 普通 hover 展开/收起，确认体感不变。
