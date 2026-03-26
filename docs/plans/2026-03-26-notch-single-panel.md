# Notch Single Panel Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 把刘海展开态收敛为单一 panel，消除顶部黑色遮罩与下拉内容的动画不同步问题。

**Architecture:** 保留 `collapsedPanel` 作为收起态入口，但在展开态只使用 `expandedPanel`。`NotchContentView` 负责渲染 bridge 顶盖和正文内容，`NotchDisplayController` 负责在展开/收起边界切换两个 panel 的可见性。

**Tech Stack:** Swift 6.2, AppKit, SwiftUI, Swift Package Manager

---

### Task 1: 给展开内容补上 bridge 顶盖

**Files:**
- Modify: `Sources/VibeBarApp/NotchContentView.swift`

**Step 1: 引入顶盖输入**

让 `NotchContentView` 接收当前 summary 和 bridge presentation，用于在展开 panel 内直接渲染顶部顶盖。

**Step 2: 在顶部绘制 bridge**

把 `NotchCollapsedView` 的 `bridge` 表现嵌入展开视图顶部，保持图标位置和黑色顶盖样式一致。

**Step 3: 构建验证**

Run: `swift build --target VibeBarApp`
Expected: BUILD SUCCEEDED

### Task 2: 收敛展开/收起动画的 panel 所有权

**Files:**
- Modify: `Sources/VibeBarApp/NotchDisplayController.swift`

**Step 1: 展开态隐藏 collapsedPanel**

在 `expandedPanel` 开始承担展开动画后，移除 `collapsedPanel` 的展开态存在感。

**Step 2: 收起时只动画 expandedPanel**

让 `collapsedPanel` 等待收起完成后再恢复，避免两个窗口同时演不同步。

**Step 3: 更新刷新路径**

在展开态刷新 UI 时，只更新 `expandedPanel` 的位置和内容，不再把 `collapsedPanel` 切成 bridge 形态。

**Step 4: 构建验证**

Run: `swift build --target VibeBarApp`
Expected: BUILD SUCCEEDED

### Task 3: 回归验证

**Files:**
- None

**Step 1: 验证展开**

确认展开过程中只看到一个整体窗口扩展，不再有单独顶盖残留。

**Step 2: 验证收起**

确认下拉框收起后，顶部黑色遮罩不会额外停留。

**Step 3: 验证视觉连续性**

确认刘海顶盖、图标位置、正文安全区和 usage 区均保持正确。
