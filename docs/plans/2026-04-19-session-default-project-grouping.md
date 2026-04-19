# Session Default Project Grouping Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 让 Session 分组在首次使用时默认按项目分类，同时保留已有用户和旧版本迁移用户的分组偏好。

**Architecture:** 修改 `AppSettings` 的分组模式加载逻辑，把“默认值”与“旧键迁移”拆开处理。只有当旧键真实存在时才执行旧设置迁移，否则直接回退到 `.project`，并用轻量单测覆盖四条关键路径。

**Tech Stack:** Swift 6.2, Foundation, Swift Testing, SwiftUI/AppKit settings model

---

### Task 1: 为默认值与迁移逻辑补测试

**Files:**
- Create: `Tests/VibeBarAppTests/AppSettingsTests.swift`
- Modify: `Sources/VibeBarApp/AppSettings.swift`

**Step 1: Write the failing test**

- 覆盖无配置默认 `.project`
- 覆盖旧键 `true -> .tool`
- 覆盖旧键 `false -> .none`
- 覆盖新键优先于旧键

**Step 2: Run test to verify it fails**

Run: `swift test --filter AppSettingsTests`
Expected: FAIL because `loadSessionGroupingModeWithMigration` cannot be injected with isolated `UserDefaults`, and fresh defaults still resolve to tool grouping.

**Step 3: Write minimal implementation**

- 允许 `loadSessionGroupingModeWithMigration(userDefaults:)` 接收注入的 `UserDefaults`
- 仅当 `groupSessionsByTool` 真实存在时才迁移旧键
- 缺少两个键时写入 `.project`
- 移除 `register(defaults:)` 中对旧键的默认注册

**Step 4: Run test to verify it passes**

Run: `swift test --filter AppSettingsTests`
Expected: PASS

### Task 2: 验证应用级回归

**Files:**
- Modify: none

**Step 1: Build app target**

Run: `swift build`
Expected: PASS

**Step 2: Run targeted session presentation tests**

Run: `swift test --filter SessionListPresentationTests`
Expected: PASS

**Step 3: Manual verification**

- 清空相关偏好后启动应用，Session 默认显示按项目分组
- 已有用户若之前选过按工具或不分组，升级后保持原样
