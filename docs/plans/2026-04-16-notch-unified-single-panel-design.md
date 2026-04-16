# Notch Unified Single Panel Design

**Date:** 2026-04-16

**Status:** Confirmed

## Summary

本次设计把刘海入口重构为真正的单一 `NSPanel` 实现。

核心目标：

1. 让 `未展开时的窗口` 成为唯一的视觉宿主，而不是在收起和展开之间切换两个独立 panel。
2. 让展开动画从收起态窗口开始，收起动画也回到同一个收起态窗口。
3. 消除收起过程中左右图标先消失、等窗口缩回刘海中央后再重新出现的断裂感。

## Root Cause

当前问题不是单一动画曲线导致的，而是窗口所有权与动画终点共同造成的：

1. [NotchDisplayController.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/NotchDisplayController.swift) 同时维护 `collapsedPanel` 与 `expandedPanel`，折叠态与展开态分别由两个独立 `NSPanel` 承载。
2. 收起时会先执行 `collapsedPanel.orderOut(nil)`，随后只对 `expandedPanel` 做 frame 动画，直到 completion 才重新 `orderFront` 折叠态 panel。
3. `animationSeedFrame(using:)` 当前返回 `geometry.notchFrame`，也就是物理刘海本体，而不是收起态真实窗口 frame。
4. 这导致收起路径是：
   - 先隐藏承载左右图标的折叠态窗口
   - 再把展开态窗口缩回刘海本体
   - 最后重新显示折叠态窗口

因此用户看到的现象是：左右图标先消失，等窗口缩到刘海中央后再回来。

## Goals

- 保证顶部左右图标在整个收起过程中持续可见。
- 保证展开起点与收起终点都等于 `collapsedTopPanelLayout.frame`。
- 保持当前黑色刘海顶盖、左右图标位置、正文布局与 hover 交互语义。
- 尽量复用现有 `NotchCollapsedView`、`NotchPanelOutlineShape` 与正文内容结构，避免无关重写。

## Non-Goals

- 不改变当前刘海入口的视觉语言、颜色或图标样式。
- 不重新设计 session / usage 的正文内容结构。
- 不在这次重构里增加新的用户配置项。
- 不把交互改成点击展开；仍保持 hover 驱动。

## Chosen Approach

采用“一个 panel + 一个根视图 + 四态展示相位”的方案。

### Panel Ownership

- 只保留一个 `notchPanel`。
- 收起态、展开态、展开中、收起中都由这个 panel 承载。
- 不再在 `collapsedPanel` 与 `expandedPanel` 之间做 `orderOut/orderFront` 切换。

### Presentation Phases

展示状态定义为四个相位：

- `collapsed`
- `expanding`
- `expanded`
- `collapsing`

相位只服务于视觉与交互控制，不替代现有 `NotchHoverStateMachine` 的 hover 时序职责。

### Unified Root View

- 新增一个统一根视图，例如 `NotchPanelRootView`。
- 这个根视图统一负责：
  - 顶部壳体绘制
  - 正文内容容器
  - 过渡中的裁剪、透明度、命中开关
- 现有 `NotchCollapsedView` 降级为顶部壳体子视图，不再作为独立窗口内容。
- 现有 `NotchContentView` 拆成正文内容组件，例如 `NotchExpandedBodyView`，由根视图决定何时显示。

## Geometry And Animation

### Frames

- 收起态目标 frame 使用 `collapsedTopPanelLayout(using:).frame`。
- 展开态目标 frame 使用 `expandedPanelFrame(using:)`。
- 展开与收起都只在这两个 frame 之间切换。
- `animationSeedFrame(using:)` 不再返回 `geometry.notchFrame`，因为物理刘海本体不再是过渡终点。

### Top Edge Continuity

- 当前收起态与展开态 frame 的顶部都对齐 `geometry.notchFrame.maxY`。
- 单 panel 后应继续保持这个约束，使顶部壳体在展开与收起中始终沿同一条顶部基线运动。
- 视觉上应呈现为“从未展开窗口长出正文，再收回同一窗口”，而不是“先缩回刘海中心，再补一个收起态块”。

### Body Reveal Strategy

- 正文不应在收起开始时直接整块消失。
- 正文区域应采用：
  - 顶部锚定
  - 高度裁剪
  - 轻微透明度辅助
- 收起进入 `collapsing` 后关闭正文 hit testing，避免点击区域残留。

## Hover And Hit Testing

- 命中判断只围绕一个 panel 进行。
- 折叠态命中区等价于收起态 frame。
- 展开态与过渡态命中区统一基于当前 `notchPanel.frame`，并保留现有 `pointerHitSlop` 外扩。
- 这样鼠标在收起动画中仍位于同一个窗口上方，不会因为宿主窗口切换被错误判定为离开。

## File Direction

### New File

- `Sources/VibeBarApp/NotchPanelRootView.swift`

### Existing Files Likely To Change

- `Sources/VibeBarApp/NotchDisplayController.swift`
- `Sources/VibeBarApp/NotchCollapsedView.swift`
- `Sources/VibeBarApp/NotchContentView.swift`
- `Sources/VibeBarApp/NotchPanelOutlineShape.swift`
- `Sources/VibeBarApp/NotchPanelStyle.swift`

### Optional Supporting Extraction

如果单元测试需要稳定落点，可以引入一个很小的纯逻辑辅助类型，例如：

- `NotchPanelPhase`
- `NotchPanelLayoutModel`

它们只负责描述当前相位、正文可见性与目标 frame，不引入额外业务层。

## Risks

1. 折叠态不能被正文 `fittingSize` 反向撑大，因此窗口目标尺寸与正文固有尺寸必须解耦。
2. 如果根视图同时承担顶部壳体与正文，布局裁剪顺序错误时可能出现顶部描边或圆角抖动。
3. 单 panel 后若刷新路径没有区分相位，数据更新可能在动画中触发不必要的重新布局。
4. hover 命中区若直接依赖实时缩小的 frame，边缘场景仍可能误判离开，需要保留少量外扩容错。

## Validation

修复后需要满足：

1. 收起全过程左右图标持续可见，不再先消失再显示。
2. 展开起点等于 `未展开时的窗口`，收起终点也等于这个窗口。
3. 展开与收起只看到一个窗口，不再有 panel 切换感。
4. 鼠标从顶部进入、停留、离开时，hover 展开/收起逻辑不回归。
5. 数据刷新时，折叠态与展开态都能正确更新图标、统计与正文内容。
