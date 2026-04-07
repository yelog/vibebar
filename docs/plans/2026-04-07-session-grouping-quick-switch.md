# Session Grouping Quick Switch Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在刘海下拉和原生菜单栏下拉的 session 区域头部加入可平铺点击的分组模式切换入口，并在 `不分组 / 按工具 / 按项目` 之间实时生效。

**Architecture:** 通过一个可复用的 SwiftUI 分组切换控件承载三段模式选择，在 SwiftUI 列表头部直接复用，在原生菜单中通过 `NSHostingView` 嵌入相同头部视图；点击后统一修改 `AppSettings.shared.sessionGroupingMode`，复用现有观察链路完成实时刷新。

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, Foundation

---

### Task 1: 写设计文档并定义复用控件

**Files:**
- Create: `docs/plans/2026-04-07-session-grouping-quick-switch-design.md`
- Create: `docs/plans/2026-04-07-session-grouping-quick-switch.md`
- Create: `Sources/VibeBarApp/SessionGroupingControls.swift`

**Step 1: 实现 SwiftUI 分组切换控件**

- 新增 `SessionGroupingModeSwitcher`
- 新增 `SessionSectionHeaderView`
- 支持紧凑尺寸和现有三种模式

### Task 2: 接入刘海下拉与备用 SwiftUI 菜单

**Files:**
- Modify: `Sources/VibeBarApp/NotchContentView.swift`
- Modify: `Sources/VibeBarApp/MenuContentView.swift`

**Step 1: 用统一头部替换静态文案**

- 左侧显示 `会话`
- 右侧显示三段切换
- 点击后立刻刷新列表

### Task 3: 接入原生菜单栏下拉

**Files:**
- Modify: `Sources/VibeBarApp/StatusItemController.swift`

**Step 1: 在 session 列表前加入自定义 header item**

- 使用 `NSHostingView` 嵌入 `SessionSectionHeaderView`
- 保持菜单打开状态下可切换
- 切换后依赖现有设置观察自动重建菜单

### Task 4: 验证

**Files:**
- Modify: none

**Step 1: 构建**

Run: `swift build`
Expected: PASS

**Step 2: 全量测试**

Run: `swift test`
Expected: PASS

**Step 3: 手工检查**

- 刘海下拉右上角出现三段选项
- 原生菜单 session 区域顶部出现相同切换入口
- 三种模式切换后列表即时变化
