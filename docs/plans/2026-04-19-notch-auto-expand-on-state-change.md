# Notch Auto Expand On State Change Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在刘海模式下，当 Session 从运行中变为等待中或空闲时自动展开刘海，并只展示触发状态变化的 Session，同时允许用户在设置中关闭此行为。

**Architecture:** 在 `StatusItemController` 现有状态转换检测链路上增加一个“自动展开刘海”的分支，并把一次性的 `focusedSessionID` 保存在 `NotchDisplayController` 中。视图层仅根据该可选 ID 切换为聚焦态渲染，从而避免引入新的面板或新的 Session 组件。

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, Foundation, Swift Testing

---

### Task 1: 增加设置开关与文案

**Files:**
- Modify: `Sources/VibeBarApp/AppSettings.swift`
- Modify: `Sources/VibeBarCore/L10nStrings.swift`
- Modify: `Sources/VibeBarApp/SettingsView.swift`

**Step 1: Add the failing test**

- 在 `AppSettingsTests` 中覆盖新开关默认值为 `true`。
- 覆盖用户显式保存 `false` 时读取为 `false`。

**Step 2: Run test to verify it fails**

Run: `swift test --filter AppSettingsTests`
Expected: FAIL because `AppSettings` 还没有新的设置项和可注入读取入口。

**Step 3: Write minimal implementation**

- 在 `AppSettings` 中增加 `notchAutoExpandOnStateChange` 并持久化。
- 为该设置提供可测试的默认值读取函数。
- 在 `L10nStrings` 中增加标题和说明文案。
- 在 `General > System` 中增加设置开关，并在刘海展示关闭时置灰。

**Step 4: Run test to verify it passes**

Run: `swift test --filter AppSettingsTests`
Expected: PASS

### Task 2: 为刘海增加聚焦态上下文

**Files:**
- Modify: `Sources/VibeBarApp/NotchDisplayController.swift`
- Modify: `Sources/VibeBarApp/NotchPanelViewState.swift`
- Modify: `Sources/VibeBarApp/NotchPanelRootView.swift`
- Modify: `Sources/VibeBarApp/NotchExpandedBodyView.swift`

**Step 1: Thread focused session state through the notch stack**

- 在 `NotchDisplayController` 中增加可选 `focusedSessionID`。
- 在 `NotchPanelViewState` 中增加对应字段并在 `update(...)` 中传递。
- 在 `NotchExpandedBodyView` 中根据 `focusedSessionID` 决定是否进入聚焦态。

**Step 2: Implement focused rendering**

- 聚焦态只渲染单个 Session。
- 聚焦态隐藏分组控件与 usage 区域。
- 如果找不到对应 Session，则回退到原有完整视图。

**Step 3: Clear focused state on collapse**

- 保证自动展开后的聚焦态不会污染后续用户手动 hover 展开。

### Task 3: 接入状态变更自动展开逻辑

**Files:**
- Modify: `Sources/VibeBarApp/StatusItemController.swift`

**Step 1: Reuse existing transition detection**

- 在 `notifyStateTransitionsIfNeeded(sessions:)` 中，在两类目标转换发生时判断：
  - 新开关开启
  - 当前入口模式为 `.notch`
  - 刘海当前未展开

**Step 2: Trigger focused notch expansion**

- 为 `NotchDisplayController` 增加新的自动展开方法。
- 传入当前 summary/sessions payload 和目标 session id。

**Step 3: Preserve existing behavior**

- 不影响现有通知发送。
- 不影响通知点击后的完整展开。
- 不影响菜单栏模式。

### Task 4: 验证回归

**Files:**
- Modify: `Tests/VibeBarAppTests/AppSettingsTests.swift`

**Step 1: Run targeted tests**

Run: `swift test --filter AppSettingsTests`
Expected: PASS

**Step 2: Build the project**

Run: `swift build`
Expected: PASS

**Step 3: Manual verification**

- 开启刘海模式并保持新开关开启。
- 制造 `running -> awaitingInput`，确认刘海自动展开且仅显示该 Session。
- 制造 `running -> idle`，确认刘海自动展开且仅显示该 Session。
- 点击该 Session，确认跳回终端。
- 收起后 hover 展开，确认恢复完整列表。
- 关闭新开关后重复转换，确认不再自动展开。
