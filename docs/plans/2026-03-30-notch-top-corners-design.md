# Notch Top Corners Design

**Date:** 2026-03-30

**Status:** Confirmed

## Summary

本次设计调整 VibeBar 刘海展开面板顶部轮廓，让当前“卡片圆角”改为更接近原生刘海的“顶部直边 + 两侧柔和弧肩”：

1. 展开态下拉面板顶部两个角不再使用标准圆角。
2. 顶边保持直线感，两侧增加轻微弧形过渡，避免生硬的硬直角。
3. bridge 顶盖与展开主体使用一致的顶部轮廓语言，保持一体化。

## Goals

- 消除展开态顶部两个角的卡片圆角观感。
- 让顶部边缘更接近原生刘海上沿的视觉语言。
- 保持现有纯黑风格、单 panel 架构、hover 交互和正文布局不变。
- 将改动收敛在 shape path 与少量几何参数，降低回归风险。

## Non-Goals

- 不修改展开窗口 frame、锚点、热区判断或动画时序。
- 不调整正文排版、安全区、内容宽度或底部操作区。
- 不重做收起态右侧扩展块的几何，除非后续视觉验收明确要求统一。
- 不改变普通菜单栏模式的任何视觉。

## Current State

- 展开态主体背景由 [NotchContentView.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/NotchContentView.swift) 中的 `NotchExpandedPanelShape` 绘制。
- 该 shape 当前是标准四角圆角 path，顶部左右角也是典型卡片圆角，见 [NotchContentView.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/NotchContentView.swift#L411)。
- bridge 顶盖由 [NotchCollapsedView.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/NotchCollapsedView.swift) 中的 `NotchBridgePanelShape` 绘制，其顶部左右角同样使用标准圆角逻辑，见 [NotchCollapsedView.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/NotchCollapsedView.swift#L146)。
- 样式层目前只有统一 `cornerRadius`，没有专门表达“顶部直角段”和“弧肩”几何的参数，见 [NotchPanelStyle.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/NotchPanelStyle.swift#L3)。

## Root Cause

当前违和感不是颜色导致，而是顶部几何模型仍是“悬浮卡片”：

1. 顶部左右角直接使用标准圆角，导致面板上沿像一个普通圆角矩形。
2. bridge 顶盖和展开主体共用了同类圆角语言，因此顶部整体都偏向“卡片”而不是“刘海延展”。
3. 当前样式参数无法单独控制顶部肩部轮廓，导致只能在“完全圆角”和“完全直角”之间二选一。

## Chosen Approach

采用“重写顶部 path，保留下半部几何”的最小几何调整方案。

### Geometry Model

- 顶边改为完整直线，不再在顶部左右角直接进入圆角。
- 左右两侧各保留一小段直角深度，形成更接近原生刘海的顶部转折。
- 在顶部靠侧边的位置加入一段向内收的弧肩曲线，再接回正常侧边。
- 底部两个圆角继续保留当前半径，不改变面板下半部分的视觉与命中边界。

### Shared Shape Language

- `NotchExpandedPanelShape` 与 `NotchBridgePanelShape` 共用同一套顶部轮廓构造逻辑。
- 这样可保证展开主体与 bridge 顶盖连接处没有轮廓断层，也避免后续两份 path 分叉维护。

### Style Parameters

在 [NotchPanelStyle.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/NotchPanelStyle.swift) 新增顶部几何常量，统一调参：

- `bottomCornerRadius`
- `topCornerStraightDepth`
- `topShoulderDepth`
- `topShoulderInset`

推荐初始参数范围：

1. 顶部直角段深度：`2-3pt`
2. 弧肩过渡高度：`8-10pt`
3. 弧肩最大内收：`4-6pt`
4. 底部圆角：沿用当前 `11pt`

### Scope

- 修改 [NotchContentView.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/NotchContentView.swift) 中展开态主体 shape。
- 修改 [NotchCollapsedView.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/NotchCollapsedView.swift) 中 bridge 顶盖 shape。
- 修改 [NotchPanelStyle.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/NotchPanelStyle.swift) 增加顶部几何参数。
- 不改 `NotchDisplayController`、hover 状态机、内容布局和业务逻辑。

## Alternatives Considered

### 1. 直接在现有圆角 shape 上叠加遮罩或 overlay 补角

- 优点：看起来改动更少。
- 缺点：容易出现接缝、抗锯齿边和 bridge/主体轮廓不一致的问题，不适合当前一体化面板。

### 2. 顶部单独增加一层“肩部盖板”，主体 shape 保持不变

- 优点：顶部细节调节更自由。
- 缺点：会把几何分成两套，增加层级和维护成本，也更容易影响动画一致性。

### 3. 只把顶部改成纯直角，不做弧肩过渡

- 优点：实现最直接。
- 缺点：边缘会过硬，和你要求的“柔和一点，像原生刘海角”不一致。

## Validation

修复后需要满足：

1. 展开态顶部两个角不再呈现明显的圆角卡片感。
2. 顶边保持直线，不出现顶部内凹、波浪或明显折线。
3. 左右两侧过渡比硬直角更柔和，视觉接近原生刘海肩部。
4. bridge 顶盖与展开主体连接处没有 1px 缝隙、双边或错位。
5. 展开/收起动画、hover 热区、点击和内容布局保持不变。
6. `swift build --target VibeBarApp` 能通过。

## Risks

- 顶部弧肩过渡过大时，可能让面板显得被“捏瘦”，削弱顶部直线感。
- 过渡过小时，视觉上又会接近普通直角，达不到“柔和一点”的目标。
- 如果 `NotchExpandedPanelShape` 和 `NotchBridgePanelShape` 没有真正共用同一组几何规则，展开后顶部可能出现细小断层，需要真机人工确认。
