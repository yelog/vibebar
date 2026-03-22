# Startup Update Check Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 修复 VibeBar 在开机启动后的后台更新检查失败误弹窗问题，只在用户手动检查失败时提示。

**Architecture:** 在 `UpdateChecker` 中记录当前更新检查来源，利用 Sparkle 现有 delegate 生命周期控制错误提示范围。应用不再在启动后主动触发额外后台检查，而是仅配置 Sparkle 自己的自动检查调度。

**Tech Stack:** Swift 6.2, AppKit, Sparkle 2.x, Swift Package Manager

---

### Task 1: 记录更新检查来源并限制失败弹窗

**Files:**
- Modify: `Sources/VibeBarApp/UpdateChecker.swift`

**Step 1: 添加检查来源状态**

在 `UpdateChecker` 内增加枚举和状态字段，区分手动检查与后台检查。

**Step 2: 在检查入口设置来源**

更新 `checkForUpdates(silent:)` 与 `checkForUpdatesWithUI()`，在触发 Sparkle 检查前写入当前来源。

**Step 3: 在失败回调中按来源处理**

保留对 `SUNoUpdateError` 和取消安装错误的忽略逻辑；后台失败只记日志，手动失败才弹出错误框。

**Step 4: 在更新周期结束后清理状态**

在 `updaterDidNotFindUpdate` 与 `didFinishUpdateCycleForUpdateCheck` 中重置来源状态，避免串状态。

**Step 5: 构建验证**

Run: `swift build --target VibeBarApp`
Expected: BUILD SUCCEEDED

### Task 2: 移除应用层额外的启动后台检查

**Files:**
- Modify: `Sources/VibeBarApp/UpdateChecker.swift`
- Modify: `Sources/VibeBarApp/AppDelegate.swift`

**Step 1: 删除自建启动检查逻辑**

移除 `startAutoCheckIfNeeded()` 中的延迟触发和自建定时器。

**Step 2: 删除启动调用点**

在 `AppDelegate.applicationDidFinishLaunching` 中移除 `startAutoCheckIfNeeded()` 调用。

**Step 3: 保留 Sparkle 配置**

仅保留 `initialize()` 中对 `automaticallyChecksForUpdates` 和 `updateCheckInterval` 的配置，让 Sparkle 自己调度后台检查。

**Step 4: 构建验证**

Run: `swift build --target VibeBarApp`
Expected: BUILD SUCCEEDED

### Task 3: 手动回归验证

**Files:**
- None

**Step 1: 验证手动检查**

在应用设置页点击“检查更新”，确认正常情况下不报错；如果人为制造网络错误，仍会出现失败弹窗。

**Step 2: 验证后台检查**

开启自动检查和开机启动后重启系统，确认后台检查失败不会弹窗。

**Step 3: 记录结果**

在交付说明中明确：已完成编译验证；开机启动场景需在真实登录环境下人工复测。
