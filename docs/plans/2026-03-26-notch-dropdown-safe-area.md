# Notch Dropdown Safe Area Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 修复刘海模式展开面板顶部正文被刘海遮挡以及底部 usage 内容被裁切的问题，同时保留当前与刘海连成一体的顶盖视觉和 hover 展开交互。

**Architecture:** 保持 `NotchDisplayController` 的窗口锚点、bridge 顶盖和动画逻辑不变，但让它同时负责顶部安全高度和屏幕可用高度预算。`NotchContentView` 将顶部安全区与正文层拆成明确结构，让正文统一从安全起点以下开始布局，并让 `NSHostingView.fittingSize` 反映真实内容高度。

**Tech Stack:** Swift 6.2, AppKit, SwiftUI, Swift Package Manager

---

### Task 1: 明确展开内容的顶部安全高度语义

**Files:**
- Modify: `Sources/VibeBarApp/NotchDisplayController.swift`
- Modify: `Sources/VibeBarApp/NotchContentView.swift`

**Step 1: 收敛安全高度命名**

把 `NotchDisplayController` 传给 `NotchContentView` 的 `topPlaceholderHeight` 改成表达真实语义的字段，例如 `contentTopInset`。

**Step 2: 统一安全高度来源**

在 `NotchDisplayController` 中继续基于当前 `notchFrame.height` 计算顶部安全高度，并保证该值在无几何缓存时仍有稳定兜底。

**Step 3: 构建验证**

Run: `swift build --target VibeBarApp`
Expected: BUILD SUCCEEDED

### Task 2: 拆分展开面板的顶部安全区与正文层

**Files:**
- Modify: `Sources/VibeBarApp/NotchContentView.swift`

**Step 1: 建立显式顶部安全区**

让 `NotchContentView` 使用明确的顶部安全区容器表达“刘海下方留白”，而不是只依赖外层 `padding`。

**Step 2: 引入内容容器**

把 `header`、`sessionsSection`、`UsageMenuSectionView` 和 `footer` 放入单独的正文容器，并让正文容器整体从 `contentTopInset` 以下开始排版。

**Step 3: 保持背景层完整**

保留现有 `NotchExpandedPanelShape` 背景、描边和顶部高光，让黑色一体化顶盖继续覆盖整个面板。

**Step 4: 构建验证**

Run: `swift build --target VibeBarApp`
Expected: BUILD SUCCEEDED

### Task 3: 让展开面板高度跟随当前屏幕可用空间

**Files:**
- Modify: `Sources/VibeBarApp/NotchDisplayController.swift`

**Step 1: 计算真实高度上限**

基于当前主屏 `visibleFrame` 与刘海底边位置，计算展开面板在当前屏幕上允许占用的最大高度，而不是固定写死 `560`。

**Step 2: 合并内容高度与屏幕高度预算**

让展开面板最终高度取 `fittingSize.height` 与屏幕可用高度上限的较小值，保证底部 usage 文本不会被无意义截断。

**Step 3: 构建验证**

Run: `swift build --target VibeBarApp`
Expected: BUILD SUCCEEDED

### Task 4: 回归验证刘海展开视觉与交互

**Files:**
- None

**Step 1: 验证顶部正文避让**

运行应用并展开刘海面板，确认 `VibeBar` 标题、更新时间和首行会话内容都完整显示在刘海下方。

**Step 2: 验证 bridge 连续性**

确认顶盖、描边、高光与 bridge 仍然连续，没有出现空隙、错位或裁切。

**Step 3: 验证内容高度变化**

在有 usage 区和无 usage 区两种状态下展开面板，确认正文起点一致，不因内容多寡顶回刘海区域。

**Step 4: 验证底部 usage 文本**

确认 usage 卡片底部 `total tokens` 和日期范围文本完整显示，没有被面板底边裁切。

**Step 5: 验证交互未回归**

确认 hover 展开、离开收起和热区桥接行为与修复前一致。

**Step 6: 记录交付说明**

在最终说明中明确：已完成 `swift build --target VibeBarApp` 构建验证；刘海场景需在真机界面继续人工确认。
