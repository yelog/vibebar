# Notch Focused Hover Reveal Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 让状态变化自动展开的聚焦刘海在鼠标移入时立即切回完整窗口内容。

**Architecture:** 保留 `NotchDisplayController` 当前的“自动展开 + focusedSessionID + hold window”结构，只补上一条“用户接管聚焦态”的切换路径。鼠标进入窗口时由控制器清理聚焦状态，并在已展开态下重新测量完整面板尺寸与内容，避免修改 hover 状态机。

**Tech Stack:** Swift 6.2, AppKit, SwiftUI, Foundation, Swift Testing

---

### Task 1: 提炼聚焦态切换的最小状态辅助

**Files:**
- Modify: `Sources/VibeBarApp/NotchDisplayController.swift`
- Create: `Tests/VibeBarAppTests/NotchAutoExpandFocusStateTests.swift`

**Step 1: Write the failing test**

- 覆盖“开始聚焦态后可读出 focused session id”。
- 覆盖“reveal full panel 后清空 focused session id”。

**Step 2: Run test to verify it fails**

Run: `swift test --filter NotchAutoExpandFocusStateTests`
Expected: FAIL because there is no focused-state helper to assert against.

**Step 3: Write minimal implementation**

- 在 `NotchDisplayController.swift` 中增加一个最小状态辅助，负责保存和清理聚焦 session id。
- 让 controller 用这个辅助替代裸 `focusedSessionID` 管理。

**Step 4: Run test to verify it passes**

Run: `swift test --filter NotchAutoExpandFocusStateTests`
Expected: PASS

### Task 2: 在鼠标进入时切回完整窗口

**Files:**
- Modify: `Sources/VibeBarApp/NotchDisplayController.swift`

**Step 1: Add focused-to-full reveal helper**

- 增加一个私有 helper：当当前仍处于聚焦态时，清理聚焦信息并清理 hold。
- 如果 panel 当前已经是 `.expanded`，立即重新测量内容并更新 frame。

**Step 2: Trigger reveal on pointer enter**

- 在 `reconcilePointerPresence()` 的 `pointerInHotZone` 分支中，优先执行聚焦态退出逻辑。
- 然后继续沿用现有 `.pointerEnteredHotZone` 逻辑。

**Step 3: Preserve existing behaviors**

- 不改变状态变化自动展开的首次聚焦显示。
- 不改变 3 秒保留期在“未鼠标接管”场景下的行为。
- 不改变普通 hover 展开/收起与通知点击展开。

### Task 3: 验证回归

**Files:**
- Modify: none

**Step 1: Run targeted tests**

Run: `swift test --filter NotchAutoExpandFocusStateTests`
Expected: PASS

**Step 2: Run related tests**

Run: `swift test --filter NotchAutoExpandHoldTests`
Expected: PASS

**Step 3: Run full test suite**

Run: `swift test`
Expected: PASS

**Step 4: Build package**

Run: `swift build`
Expected: PASS

**Step 5: Manual verification**

- 触发 `running -> awaitingInput` 或 `running -> idle`，确认先显示单个 Session。
- 鼠标移入已展开窗口，确认立即切换成完整窗口。
- 切换后移出窗口，确认仍按现有 hover 逻辑收起。
- 不触发状态变化时，普通 hover 行为保持不变。
