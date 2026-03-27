# Notch Usage Tooltip Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 让刘海展开面板里的 usage 图表 tooltip 与菜单栏下拉复用同一套 detached 浮层效果，并稳定显示在图表上方。

**Architecture:** 保持 `UsageMenuSectionView` 现有 hover 状态模型和 `UsageChartTooltipController` 不变，只为刘海宿主补一条与菜单栏相同的 `onChartHoverChange -> AppKit host -> detached panel` 传递链路。`StatusItemController` 继续作为入口协调器统一负责 show/hide，`NotchDisplayController` 负责把刘海面板里的 hover 状态和宿主视图暴露出来。

**Tech Stack:** Swift 6.2, AppKit, SwiftUI, Swift Package Manager

---

### Task 1: 为刘海 usage 卡片补齐 hover 状态上抛链路

**Files:**
- Modify: `Sources/VibeBarApp/NotchContentView.swift`
- Modify: `Sources/VibeBarApp/NotchDisplayController.swift`

**Step 1: 扩展刘海内容视图参数**

给 `NotchContentView` 增加一个可选的 usage chart hover 回调参数，类型与 `UsageMenuSectionView` 的 `onChartHoverChange` 保持一致。

**Step 2: 透传到 usage 卡片**

在 `NotchContentView` 中把新的回调传给内部 `UsageMenuSectionView`，让 bar / line chart hover 时可以像菜单栏一样上抛 `UsageMenuChartHoverState`。

**Step 3: 在刘海宿主保留回调出口**

给 `NotchDisplayController` 增加对应的对外回调属性，并在 `refreshContent()` 和初始化默认 `rootView` 时把回调传入 `NotchContentView`。

**Step 4: 构建验证**

Run: `swift build --target VibeBarApp`
Expected: BUILD SUCCEEDED

### Task 2: 让入口协调器用现有 detached tooltip 控制器驱动刘海场景

**Files:**
- Modify: `Sources/VibeBarApp/StatusItemController.swift`
- Modify: `Sources/VibeBarApp/NotchDisplayController.swift`

**Step 1: 在状态栏协调器注册刘海 hover 回调**

在 `StatusItemController` 初始化 `notchController` 时补一个 usage hover 回调，把刘海面板里的 `UsageMenuChartHoverState?` 送回协调器。

**Step 2: 暴露刘海 tooltip 的宿主视图**

为 `NotchDisplayController` 提供一个安全的只读宿主视图访问入口，返回当前展开面板对应的 `expandedHostingView`，供 tooltip controller 进行坐标转换。

**Step 3: 复用现有 tooltip show/hide 逻辑**

在 `StatusItemController` 新增或抽出一个刘海专用 handler：
- 刘海面板展开中且 hover 有值时，调用 `UsageChartTooltipController.shared.show(...)`
- 宿主不可用、hover 为空或刘海未展开时，调用 `hide()`

**Step 4: 构建验证**

Run: `swift build --target VibeBarApp`
Expected: BUILD SUCCEEDED

### Task 3: 补齐刘海面板生命周期中的 tooltip 清理

**Files:**
- Modify: `Sources/VibeBarApp/StatusItemController.swift`
- Modify: `Sources/VibeBarApp/NotchDisplayController.swift`

**Step 1: 收起时清理 tooltip**

确保刘海面板收起、隐藏或入口模式切换时，现有 detached tooltip 会被立即隐藏。

**Step 2: 内容刷新时避免悬空引用**

在刘海面板内容重建或 payload 更新时，保证旧 hover 状态不会继续驱动一个指向失效宿主视图的 tooltip。

**Step 3: 构建验证**

Run: `swift build --target VibeBarApp`
Expected: BUILD SUCCEEDED

### Task 4: 人工验证刘海与菜单栏两条链路

**Files:**
- None

**Step 1: 验证刘海 bar chart**

运行应用，在刘海展开面板中 hover usage bar chart，确认 tooltip 显示在图表上方，样式与菜单栏一致。

**Step 2: 验证刘海 line chart**

切到 line chart 再次 hover，确认 detached tooltip 同样生效，左右边缘仍会正确夹紧。

**Step 3: 验证隐藏时机**

移出图表、切到 heatmap、收起刘海面板，确认 tooltip 都会立即消失，不残留在屏幕上。

**Step 4: 验证菜单栏未回归**

打开普通菜单栏下拉，确认原有 usage chart tooltip 仍正常显示在图表上方。

**Step 5: 记录交付说明**

在最终说明中明确：已完成 `swift build --target VibeBarApp` 构建验证；刘海场景的 hover/定位仍需要在真机界面继续人工确认。
