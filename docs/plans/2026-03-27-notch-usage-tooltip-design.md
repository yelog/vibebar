# Notch Usage Tooltip Design

**Date:** 2026-03-27

**Status:** Confirmed

## Summary

本次设计统一 VibeBar 刘海展开面板中的 token usage 图表 tooltip 表现，让它与菜单栏下拉中的 usage 图表保持同一套 detached 浮层效果。

核心目标：

1. 刘海下拉里的 bar chart / line chart hover tooltip 改为与菜单栏下拉完全一致的独立浮层表现。
2. tooltip 继续显示在图表上方，而不是挤占卡片内部布局空间。
3. 复用现有 `UsageMenuSectionView` 与 `UsageChartTooltipController`，避免再维护一套刘海专用 tooltip 样式或定位逻辑。
4. 改动范围只覆盖刘海 usage 卡片，不连带修改设置页预览或热力图 hover。

## Goals

- 统一刘海下拉和菜单栏下拉的 usage chart tooltip 视觉与交互。
- 保持 tooltip 悬浮在图表上方的 detached 效果。
- 复用现有菜单栏实现，减少分叉逻辑。
- 在刘海面板收起、切换或 hover 结束时稳定隐藏 tooltip，避免残留。

## Non-Goals

- 不修改设置页 `Usage` 预览的 tooltip 行为。
- 不调整 heatmap tooltip 的实现。
- 不重做 `UsageMenuSectionView` 的图表、配色或 hover 命中逻辑。
- 不改变刘海面板的动画、尺寸或整体布局。

## Current State

- 菜单栏下拉中的 usage 卡片由 [UsageMenuSectionView.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/UsageMenuSectionView.swift) 渲染，并通过 `onChartHoverChange` 将 hover 状态传回宿主。
- 菜单栏宿主 [StatusItemController.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/StatusItemController.swift) 会接住该状态，再调用 `UsageChartTooltipController` 以独立 `NSPanel` 形式把 tooltip 显示在图表上方。
- 刘海展开面板由 [NotchDisplayController.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/NotchDisplayController.swift) 承载，其内容视图 [NotchContentView.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/NotchContentView.swift) 里虽然同样嵌入了 `UsageMenuSectionView`，但没有接 `onChartHoverChange`。
- 因为刘海场景没有 detached tooltip 宿主链路，当前只能使用 `UsageMenuSectionView` 的默认内部 overlay 行为，所以表现和菜单栏下拉不一致。

## Root Cause

问题不在 tooltip 样式本身，而在宿主接线不完整：

1. `UsageMenuSectionView` 只有在收到 `onChartHoverChange` 时才会禁用内部 overlay，并把 hover 状态上抛。
2. 菜单栏下拉已经提供了这条回调链路，刘海展开面板没有。
3. `UsageChartTooltipController` 当前只在菜单栏宿主里被调用，因此刘海面板没有独立浮层可用。
4. 刘海展开面板收起时也没有与 usage tooltip 的显式清理关系，继续扩展时需要一并补上。

## Chosen Approach

采用“复用现有 detached tooltip 控制器，为刘海面板补齐同样的 hover 上抛链路”的方案。

### Shared Tooltip Flow

- 保持 [UsageMenuSectionView.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/UsageMenuSectionView.swift) 现有机制不变：
  - 传入 `onChartHoverChange` 时，禁用内部 chart tooltip overlay。
  - bar / line chart hover 时上抛 `UsageMenuChartHoverState`。
- 刘海 usage 卡片也改为走这条机制，而不是新增第三套 tooltip 逻辑。

### Host Responsibilities

- [NotchContentView.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/NotchContentView.swift) 增加一个 usage chart hover 回调参数，并把它透传给内部 `UsageMenuSectionView`。
- [NotchDisplayController.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/NotchDisplayController.swift) 作为刘海宿主，新增对应回调出口，并使用 `expandedHostingView` 作为 tooltip 锚定视图。
- [StatusItemController.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/StatusItemController.swift) 继续作为统一入口协调器，负责把刘海 hover 状态交给现有 `UsageChartTooltipController`，并在模式切换、刘海收起或面板隐藏时主动 `hide()`。

### Positioning

- tooltip 定位仍基于 `UsageMenuChartHoverState.bucketFrame` 与 `chartFrame`。
- 不新增刘海专用坐标算法，只是把 `from view:` 从菜单栏 usage hosting view 切换为刘海展开面板的 `expandedHostingView`。
- 这样可以继续使用同一套横向夹紧与“显示在图表上方”的垂直偏移策略。

### Lifecycle

- 刘海面板处于展开态且有有效 hover 状态时显示 detached tooltip。
- 鼠标移出图表、切换到 heatmap、面板收起、入口宿主从刘海切回菜单栏时，都必须隐藏 tooltip。
- 入口切换时仍由统一协调器做清理，避免在刘海与菜单栏之间残留旧浮层。

## Alternatives Considered

### 1. 在刘海面板内部继续使用 SwiftUI overlay 模拟

- 优点：不需要穿透到 AppKit 宿主层。
- 缺点：会继续保留菜单栏和刘海两套 tooltip 机制，后续样式或定位修复仍要双修。

### 2. 抽象全新的通用 tooltip host

- 优点：长期结构更整洁。
- 缺点：超出本次范围，改动会扩大到设置页预览和其他宿主边界，不符合当前最小修复目标。

## Validation

修复后需要满足：

1. 刘海展开面板中的 bar chart / line chart hover 时，tooltip 样式与菜单栏下拉一致。
2. tooltip 显示在图表上方，不挤占 usage 卡片正文布局。
3. tooltip 在图表左右边缘会正确夹紧，不会被面板裁掉或明显偏移。
4. 切到 heatmap、鼠标移出图表、收起刘海面板或切回菜单栏模式时，tooltip 会立即消失。
5. 菜单栏下拉里的现有 usage tooltip 行为不回归。
6. 设置页 `Usage` 预览的 tooltip 行为保持不变。

## Risks

- 如果刘海场景使用的宿主 view 不是 `expandedHostingView` 的正确坐标空间，tooltip 可能会出现水平或垂直偏移。
- 如果只补 show 逻辑而遗漏面板收起时的 hide 清理，tooltip 可能在刘海面板关闭后残留在屏幕上。
- 刘海展开面板的强制 dark appearance 与 tooltip 浮层共享时，需要人工确认不会出现层级或阴影异常。
