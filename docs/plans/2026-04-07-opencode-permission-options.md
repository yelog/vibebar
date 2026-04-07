# OpenCode Permission Options Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 让 VibeBar 对 OpenCode 权限请求按原始 `once / always / reject` 选项展示并正确回写。

**Architecture:** 由 OpenCode 插件把原始权限选项作为 `PendingInteraction.options` 透传到 App，App 统一按 `options` 渲染按钮并回传选中的 option id，插件再把 option id 映射成 OpenCode 的真实 reply。菜单栏额外修正行级点击拦截，避免吞掉按钮事件。

**Tech Stack:** JavaScript plugin bridge, SwiftUI/AppKit menu UI, Swift Testing

---

### Task 1: 记录 OpenCode 原始权限选项

**Files:**
- Modify: `plugins/opencode-vibebar-plugin/index.js`

**Step 1: 更新 permission interaction 构造**

- 在 `buildPermissionInteraction()` 中写入三个 options：
  - `once` / `Allow once`
  - `always` / `Allow always`
  - `reject` / `Reject`
- 在 `transport_context` 中保留 `opencode_request_id`

**Step 2: 更新 permission reply 映射**

- 在 `replyPermission()` 中优先读取 `decision.optionID`
- 精确映射到 OpenCode reply：
  - `once -> once`
  - `always -> always`
  - `reject -> reject`
- 对旧的 `allow/deny` 决策保留兼容回退

### Task 2: App 侧按原始 options 渲染

**Files:**
- Modify: `Sources/VibeBarApp/SessionDisplayFormatter.swift`
- Test: `Tests/VibeBarAppTests/SessionDisplayFormatterTests.swift`

**Step 1: 写显示层回归测试**

- 覆盖 permission interaction 自带 options 时，`interactionActions()` 返回原始 labels 与 option ids
- 覆盖旧 permission interaction 无 options 时，仍回退为“允许 / 拒绝”

**Step 2: 实现最小逻辑**

- `interaction.options` 非空时，直接映射为 action
- `decision.behavior` 使用 `.select`
- `decision.optionID` 使用原始 option id
- 按 option id 设置 primary/secondary 样式

### Task 3: 修复菜单栏按钮点击

**Files:**
- Modify: `Sources/VibeBarApp/StatusItemController.swift`

**Step 1: 调整 SessionMenuItemView 事件分发**

- 当点击发生在 `interactionStripView` 内部时，不触发行级 `onClick`
- 只在非交互区域点击时打开 session

### Task 4: 运行验证

**Files:**
- Test: `Tests/VibeBarAppTests/SessionDisplayFormatterTests.swift`

**Step 1: 跑定向 Swift 测试**

Run: `swift test --filter SessionDisplayFormatterTests`

Expected: PASS

**Step 2: 跑构建验证**

Run: `swift build`

Expected: `Build complete!`
