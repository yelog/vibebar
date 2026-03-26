# Notch Corner Join Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 修复刘海折叠态右侧扩展块与系统刘海右下角之间的空隙，同时保持现有折叠态交互与视觉结构。

**Architecture:** 保留现有折叠态窗口布局，不引入新窗口或新状态。通过给右侧扩展块增加左下角拼接曲线，并将可视形状向左补偿一小段宽度，填平系统刘海圆角留下的缺口。

**Tech Stack:** Swift 6.2, AppKit, SwiftUI, Swift Package Manager

---

### Task 1: 增加折叠态拼接几何配置

**Files:**
- Modify: `Sources/VibeBarApp/NotchPanelStyle.swift`

**Step 1: 添加拼接半径配置**

新增折叠态专用的 `collapsedJoinRadius`，用于控制扩展块向刘海内侧补偿的距离。

**Step 2: 保持样式可调**

让拼接半径与现有圆角样式并列，后续需要微调时只改样式常量。

### Task 2: 改造折叠态扩展块形状与偏移

**Files:**
- Modify: `Sources/VibeBarApp/NotchCollapsedView.swift`

**Step 1: 扩展折叠态可视宽度**

让扩展块 frame 包含拼接补偿宽度，并向左偏移相同距离，保证右边界不变。

**Step 2: 改造扩展块形状**

为 `NotchRightExtensionShape` 增加左下角拼接曲线，使底部能够自然补进刘海右下圆角的空隙。

**Step 3: 复用现有填充与描边**

保留当前 fill、highlight 和 stroke 层次，避免需求扩大成新的视觉重设计。

### Task 3: 构建验证

**Files:**
- None

**Step 1: 编译验证**

Run: `swift build --target VibeBarApp`
Expected: BUILD SUCCEEDED

**Step 2: 手工视觉验证**

确认折叠态右下接缝不再露底，同时展开态桥接背景与 hover 逻辑不变。
