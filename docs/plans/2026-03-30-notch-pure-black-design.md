# Notch Pure Black Design

**Date:** 2026-03-30

**Status:** Confirmed

## Summary

本次设计调整 VibeBar 刘海模式的视觉表面，让贴近真实刘海的所有自绘区域改为绝对纯黑。

确认后的方向：

1. 刘海 bridge 顶盖、收起态右侧延展块、展开态主体背景全部统一为纯黑。
2. 去掉当前为了做“面板质感”而加入的顶部高光、浅色描边和阴影。
3. 以“尽量接近真实刘海”优先，不保留当前浮层层次感。

## Goals

- 消除刘海 bridge 顶盖与真实刘海之间的灰差。
- 让展开态背景和收起态延展块与顶部刘海保持一致的纯黑观感。
- 保持现有刘海几何、hover 交互、展开收起动画和内容排版不变。
- 将改动收敛在视觉样式参数与面板阴影配置，降低回归风险。

## Non-Goals

- 不修改刘海几何计算、热区判断和动画曲线。
- 不重做展开面板的布局结构、尺寸或文案。
- 不调整普通菜单栏模式的任何视觉。
- 不试图解决显示面板发光黑与硬件刘海黑之间的物理差异。

## Current State

- 当前刘海相关表面样式统一定义在 [NotchPanelStyle.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/NotchPanelStyle.swift)。
- 现有 `fillColor` 为偏深灰，不是纯黑。
- 当前还叠加了顶部高光、浅色描边和展开态阴影。
- 展开态 `NSPanel` 也启用了系统窗口阴影。

## Root Cause

色差不是系统偶发渲染问题，而是当前实现主动把刘海下拉区渲染成“深色面板”：

1. 背景填充使用了接近 `#121214` 的深灰，而不是 `#000000`。
2. 顶部高光和浅色描边会进一步把边缘和顶部提亮。
3. SwiftUI 视图阴影和 `NSPanel` 阴影会继续强化“悬浮卡片”而不是“刘海延伸”的感知。

## Chosen Approach

采用“统一纯黑样式 + 关闭所有额外提亮手段”的最小修改方案。

### Visual Style

- 将 `NotchPanelStyle.fillColor` 调整为纯黑。
- 将 `strokeColor` 设为透明，取消轮廓提亮。
- 将 `topHighlight` 设为透明渐变，保留现有 overlay 结构但不产生可见高光。
- 将 `shadowColor` 设为透明，避免 SwiftUI 面板投影。

### Window Styling

- 将展开态 `NSPanel` 的 `hasShadow` 关闭。
- 收起态当前已无系统阴影，保持不变。

### Scope

- 仅修改 [NotchPanelStyle.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/NotchPanelStyle.swift)、[NotchContentView.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/NotchContentView.swift) 的既有样式使用结果，以及 [NotchDisplayController.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/NotchDisplayController.swift) 的面板阴影配置。
- 不改任何业务逻辑。

## Alternatives Considered

### 1. 只把顶盖改成纯黑

- 优点：改动更小。
- 缺点：展开背景仍有浮层感，与你确认的“绝对纯黑”目标不一致。

### 2. 保留纯黑主体，只留下外部阴影

- 优点：仍有一定层次感。
- 缺点：边缘会继续呈现悬浮感，不满足绝对纯黑要求。

### 3. 重做自定义 shape，让顶部与刘海更深度融合

- 优点：理论上可进一步接近系统观感。
- 缺点：复杂度和回归风险明显高于本次目标，不必要。

## Validation

修复后需要满足：

1. 刘海 bridge 顶盖、收起态右侧小块和展开背景都不再出现明显灰感。
2. 面板顶部和边缘不再有白色高光或浅描边。
3. 展开态不再有可见外阴影。
4. hover 展开/收起、点击和内容布局行为保持不变。
5. `swift build --target VibeBarApp` 能通过。

## Risks

- 去掉描边和阴影后，展开面板边界会更隐蔽，层次感下降是预期结果。
- 即使代码改为纯黑，显示面板发光黑与真实刘海硬件黑仍可能存在少量物理差异，需要真机人工确认。
