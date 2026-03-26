# Notch Dropdown Safe Area Design

**Date:** 2026-03-26

**Status:** Confirmed

## Summary

本次设计修复 VibeBar 刘海模式展开面板的顶部内容遮挡问题，并同步处理底部内容被裁切的问题。

核心目标：

1. 保留当前“刘海顶盖 + 下拉信息岛”一体化视觉，不改变展开入口和 bridge 结构。
2. 让展开面板的正文内容从刘海安全区下方开始排版，避免标题、更新时间和首条会话内容被遮挡。
3. 继续复用当前 `NotchDisplayController + NotchContentView` 架构，不重写动画、hover 热区和窗口宿主逻辑。
4. 让展开面板在屏幕允许范围内获得足够高度，避免 usage 卡片底部和 `total tokens` 文本被截断。

## Goals

- 修复刘海模式下展开面板上方正文被刘海遮挡的问题。
- 修复刘海模式下展开面板底部内容被裁切的问题。
- 保持现有刘海顶盖与展开面板的连续视觉。
- 让安全区计算与当前真实刘海几何一致，而不是依赖脆弱的视觉占位。
- 将改动范围收敛在展开内容布局与安全区传递，降低回归风险。

## Non-Goals

- 不调整 hover 展开/收起时序。
- 不改变收起态延展块、bridge 顶盖或窗口锚点策略。
- 不重做展开面板视觉语言、阴影或动画参数。
- 不处理普通菜单栏模式的布局。

## Current State

- 刘海展开内容在 [NotchContentView.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/NotchContentView.swift) 中构建。
- 当前正文顶部通过一个透明 `Color.clear.frame(height:)` 人工占位来避让刘海。
- 展开窗口位置由 [NotchDisplayController.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/NotchDisplayController.swift) 基于 `notchFrame.minY` 计算，窗口顶边与刘海底边直接对齐。
- bridge 顶盖与正文面板是分层协作关系：顶盖负责与刘海连成一体，正文面板负责承载摘要、会话和 usage 内容。

## Root Cause

问题不是单一视图少了 `padding`，而是“视觉顶盖”“正文安全起点”和“面板真实可见高度”被割裂处理：

1. 当前正文避让依赖视图内部的透明占位，语义不清晰。
2. 占位高度来自估算值与局部几何组合，不足以稳定覆盖不同刘海高度场景。
3. 顶盖需要继续贴着刘海，但正文需要从更低的安全起点开始；这两件事当前没有被拆开建模。
4. 展开面板高度仍被固定上限截断，没有根据当前屏幕可用高度重新计算，因此顶部安全区一旦变大，底部内容就更容易被裁掉。

## Chosen Approach

采用“保留窗口锚点，只重构展开内容安全区布局”的方案。

### Geometry Ownership

- [NotchDisplayController.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/NotchDisplayController.swift) 继续作为刘海几何的唯一来源。
- 控制器负责把展开内容所需的顶部安全高度传给 `NotchContentView`。
- 该高度直接跟随当前 `notchFrame.height` 和 bridge overlap 关系，不再让内容层自行猜测。

### Content Layering

- [NotchContentView.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/NotchContentView.swift) 拆分为两层职责：
  - 背景层：继续绘制完整的一体化深色面板，保持与顶盖相连。
  - 内容层：从顶部安全高度以下开始布局 header、session 列表、usage 和 footer。
- 顶部安全区改为一个显式的内容区段，而不是依赖外层 `padding` 侧面表达，确保 `NSHostingView.fittingSize` 与真实布局一致。

### Height Budget

- [NotchDisplayController.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/NotchDisplayController.swift) 需要同时考虑：
  - 内容理想高度
  - 当前主屏 `visibleFrame`
  - 刘海底边到屏幕底部的实际可用高度
- 面板最终高度应取“内容所需高度”和“屏幕允许高度”的较小值，而不是固定截断在单一常量。

### Visual Behavior

- 展开态面板顶边仍然贴着刘海底边，用户看到的黑色顶盖不变。
- 标题、更新时间、第一条可见内容必须完整落在刘海下方。
- 内容越多时，只应向下增长或滚动，不允许重新侵入顶部危险区。

## Alternatives Considered

### 1. 整个展开窗口继续下移

- 优点：从窗口几何层面看更直观。
- 缺点：会影响 bridge 对齐、动画起终点和阴影关系，回归面更大。

### 2. 仅修改面板 Shape 做顶部挖空

- 优点：视觉上能快速避让刘海。
- 缺点：正文排版基线不变，仍可能把文字放进遮挡区，只是“看起来像让开了”，本质不对。

## Validation

修复后需要满足：

1. 刘海展开时，顶部黑色顶盖仍与刘海连续，不出现断层或空隙。
2. `VibeBar` 标题、更新时间和首行会话内容完整显示在刘海下方。
3. 开启 usage 区或会话较多时，正文起点保持不变，只增加下方高度。
4. usage 卡片底部的 `total tokens` 与日期范围文本完整可见。
5. 收起/展开动画、hover 热区和 bridge 交互行为不变。
6. 非刘海主屏回退菜单栏模式时，不受本次改动影响。

## Risks

- 如果只改正文 inset 而忽略背景层，可能造成顶盖和正文背景之间出现视觉断层。
- 如果安全高度与 bridge overlap 关系处理不一致，可能出现“内容已避让，但描边或高光仍被截断”的细小瑕疵。
- 估算刘海几何的兜底路径仍需人工验证，避免在无法获取真实辅助区域时重新出现偏差。
