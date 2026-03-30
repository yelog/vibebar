# Notch Pure Black Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 将 VibeBar 刘海模式相关自绘表面统一改为绝对纯黑，去掉高光、描边和阴影，尽量贴近真实刘海观感。

**Architecture:** 保持现有刘海面板结构、布局和交互不变，只收敛视觉样式参数与面板宿主的阴影配置。核心改动集中在 `NotchPanelStyle` 的颜色常量和 `NotchDisplayController` 的 `NSPanel` 初始化参数。

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, Swift Package Manager

---

### Task 1: 写入纯黑设计与实现计划

**Files:**
- Create: `docs/plans/2026-03-30-notch-pure-black-design.md`
- Create: `docs/plans/2026-03-30-notch-pure-black.md`

**Step 1: 记录用户确认的视觉目标**

写清本次目标是“绝对纯黑”，而不是“更接近纯黑”。

**Step 2: 记录实现边界**

明确本次只改刘海样式和阴影，不改几何、动画和布局。

**Step 3: 记录验收标准**

写清纯黑填充、无高光、无描边、无阴影，以及构建通过这几类验证点。

### Task 2: 收敛刘海样式常量为纯黑

**Files:**
- Modify: `Sources/VibeBarApp/NotchPanelStyle.swift`

**Step 1: 将背景填充改为纯黑**

把当前深灰 `fillColor` 改为 `Color.black`。

**Step 2: 去掉高光和描边**

将 `strokeColor` 改为透明，将 `topHighlight` 改为全透明渐变，保留现有使用结构，避免额外改动调用方。

**Step 3: 去掉 SwiftUI 阴影颜色**

将 `shadowColor` 改为透明，确保 `NotchContentView` 现有 `.shadow(...)` 不再产生可见投影。

### Task 3: 关闭展开态面板系统阴影

**Files:**
- Modify: `Sources/VibeBarApp/NotchDisplayController.swift`

**Step 1: 关闭 expandedPanel 的 `NSPanel` 阴影**

将展开态面板初始化从 `hasShadow: true` 改为 `hasShadow: false`，避免系统窗口阴影继续造成黑边发灰。

### Task 4: 构建验证

**Files:**
- None

**Step 1: 运行目标构建**

Run: `swift build --target VibeBarApp`
Expected: BUILD SUCCEEDED

**Step 2: 记录人工验证点**

最终说明中明确需要真机确认：
- 顶盖与真实刘海的色差已明显缩小
- 展开态背景和收起态右侧小块都是纯黑
- 展开态不再有可见高光、描边和外阴影
