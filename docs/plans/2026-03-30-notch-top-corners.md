# Notch Top Corners Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 将刘海展开面板顶部从标准圆角改为“顶部直边 + 两侧弧肩”的原生刘海风格轮廓，同时保持现有交互、布局和纯黑视觉不变。

**Architecture:** 保留现有 `NotchDisplayController + NotchContentView + NotchCollapsedView` 单 panel 架构，不改窗口位置、热区或动画。通过在 `NotchPanelStyle` 中新增顶部几何参数，并让展开主体与 bridge 顶盖共用同一套顶部 path 规则，实现统一的顶部轮廓。

**Tech Stack:** Swift 6.2, AppKit, SwiftUI, Swift Package Manager

---

### Task 1: 增加顶部几何样式常量

**Files:**
- Modify: `Sources/VibeBarApp/NotchPanelStyle.swift`

**Step 1: 定义顶部轮廓参数**

新增 `bottomCornerRadius`、`topCornerStraightDepth`、`topShoulderDepth`、`topShoulderInset` 常量，表达底部圆角和顶部弧肩几何。

**Step 2: 保留现有纯黑视觉参数**

不要改动 `fillColor`、`strokeColor`、`shadowColor` 和 `topHighlight` 的纯黑方案，避免需求扩散成新的表面风格调整。

### Task 2: 提取共享的顶部轮廓 path 逻辑

**Files:**
- Modify: `Sources/VibeBarApp/NotchContentView.swift`
- Modify: `Sources/VibeBarApp/NotchCollapsedView.swift`

**Step 1: 设计统一的顶部 path 规则**

把顶部轮廓抽象成一套共享几何规则：

- 顶边保持直线
- 顶部左右两侧保留短直角段
- 侧边上方通过弧肩曲线过渡到正常侧边
- 底部保留当前圆角

**Step 2: 避免两份 shape 几何漂移**

实现方式可以是提取共享 shape、共享 path builder，或在两个 shape 中复用同一辅助函数；关键是不能让 bridge 与主体分别维护两套不同参数。

### Task 3: 改造展开态主体 shape

**Files:**
- Modify: `Sources/VibeBarApp/NotchContentView.swift`

**Step 1: 替换 `NotchExpandedPanelShape` 顶部轮廓**

将 [NotchContentView.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/NotchContentView.swift#L411) 现有标准四角圆角 path 改为新顶部轮廓。

**Step 2: 保持下半部边界不变**

底部两个圆角继续使用当前半径，避免影响正文视觉包裹感和命中范围。

**Step 3: 复用现有背景、描边和高光调用结构**

保留 `panelBackground` 既有 fill/overlay 结构，只替换 shape 几何，不改视图层级。

### Task 4: 改造 bridge 顶盖 shape

**Files:**
- Modify: `Sources/VibeBarApp/NotchCollapsedView.swift`

**Step 1: 替换 `NotchBridgePanelShape` 顶部轮廓**

将 [NotchCollapsedView.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/NotchCollapsedView.swift#L146) 的顶部 path 改为与主体一致的直边加弧肩方案。

**Step 2: 保持 bridge 高度与图标定位不变**

不要改 `Presentation.bridge`、`visibleHeight`、`surfaceX`、图标 offset 或其它布局参数，确保动画与入口位置不回归。

### Task 5: 构建与人工验收

**Files:**
- None

**Step 1: 编译验证**

Run: `swift build --target VibeBarApp`
Expected: BUILD SUCCEEDED

**Step 2: 真机视觉验证**

确认以下结果：

- 顶部两个角不再是卡片圆角
- 顶边保持直线
- 两侧过渡柔和但不塌陷
- bridge 与主体连接处无缝
- 展开/收起动画与 hover 逻辑不回归

**Step 3: 如有必要微调参数**

若首版弧肩过渡偏硬或偏软，仅回到 `NotchPanelStyle` 调整顶部几何常量，不再修改 shape 结构。
