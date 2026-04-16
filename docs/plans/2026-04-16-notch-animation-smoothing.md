# Notch Animation Smoothing Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 让 VibeBar 刘海模式的展开/收起更接近 CodeIsland 的内容层过渡体验，并避免动画期间的重复重建与重排。

**Architecture:** 保留现有单 `NSPanel` 架构，在 `NotchDisplayController` 中引入常驻状态对象和动画期间延迟刷新策略；在 `NotchPanelRootView` 中增加正文的 opacity / blur / offset / scale 过渡，使窗口 frame 动画和内容层动画协同工作。

**Tech Stack:** Swift 6.2, AppKit, SwiftUI, Swift Package Manager

---

### Task 1: 稳定刘海根视图宿主

**Files:**
- Create: `Sources/VibeBarApp/NotchPanelViewState.swift`
- Modify: `Sources/VibeBarApp/NotchDisplayController.swift`
- Modify: `Sources/VibeBarApp/NotchContentView.swift`

**Step 1: 建立常驻状态对象**

- 新建 `NotchPanelViewState`，集中保存根视图所需的 summary、sessions、layoutModel、panel 尺寸和回调。
- 改成 `ObservableObject + objectWillChange.send()` 的单次批量刷新。

**Step 2: 让 `NSHostingView` 只创建一次**

- `NotchDisplayController` 初始化时创建 `NotchPanelViewState` 和 `NotchHostingView<NotchPanelRootView>`。
- 删掉刷新路径里的 `rootView = ...` 重建。

**Step 3: 为兼容旧包装视图补齐适配**

- 让 `NotchContentView` 通过 `@StateObject` 包装新的状态对象，保证编译通过。

### Task 2: 给正文增加内容层过渡

**Files:**
- Modify: `Sources/VibeBarApp/NotchPanelLayoutModel.swift`
- Modify: `Sources/VibeBarApp/NotchPanelRootView.swift`
- Modify: `Sources/VibeBarApp/NotchAnimation.swift`
- Test: `Tests/VibeBarAppTests/NotchPanelLayoutModelTests.swift`

**Step 1: 扩展布局模型**

- 为不同 phase 增加 `surfaceOpacity`、`bodyOffsetY`、`bodyBlurRadius`、`bodyScale`。
- 保留现有命中与 frame 逻辑。

**Step 2: 在根视图里消费这些参数**

- 正文使用 `.opacity + .offset + .blur + .scaleEffect + .transition(.blurFade...)`。
- 背景与描边使用 `surfaceOpacity`。

**Step 3: 对齐动画 token**

- 将 `NotchAnimation.open/close` 节奏与 CodeIsland 统一，作为状态更新的统一动画曲线。

**Step 4: 补测试**

- 验证 expanding/collapsing 的 reveal 参数确实处于中间态，而不是 0/1 硬切。

### Task 3: 降低动画期间的重测量与重布局

**Files:**
- Modify: `Sources/VibeBarApp/NotchDisplayController.swift`

**Step 1: 动画中延迟刷新**

- 展开/收起期间收到新 payload 时，只保存数据并标记 `needsRefreshAfterTransition`。
- completion 再统一刷新。

**Step 2: 控制测量时机**

- 收起期间不重新测量正文高度。
- 展开开始和动画完成后再测量，折叠态常规刷新默认复用缓存。

**Step 3: 引入更稳的 HostingView**

- 借用 CodeIsland 的 deferred layout/updateConstraints 思路，减少动画期 SwiftUI/AppKit 相互触发造成的抖动。

### Task 4: 验证

**Files:**
- Test: `Tests/VibeBarAppTests/NotchPanelLayoutModelTests.swift`

**Step 1: 运行定向测试**

Run: `swift test --filter NotchPanelLayoutModelTests`

**Step 2: 运行 App target 构建**

Run: `swift build --target VibeBarApp`

**Step 3: 人工检查**

- 展开时观察正文是否柔和出现。
- 收起时观察正文是否先退出，再跟随壳体收回。
- 验证 hover 展开/收起与按钮点击未回归。
