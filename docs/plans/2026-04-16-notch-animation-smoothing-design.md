# Notch Animation Smoothing Design

**Date:** 2026-04-16

**Status:** Confirmed

## Summary

本次优化不再继续扩大刘海面板的结构重写范围，而是在现有单 `NSPanel` 架构上，把“动画主要发生在窗口 frame 层”的实现改成“窗口 frame + 内容层过渡”协同。

目标：

1. 降低展开/收起过程中的硬切感与轻微卡顿感。
2. 让正文内容像从顶部壳体里长出来，而不是被窗口尺寸瞬时裁出来。
3. 减少动画期间的重复测量与根视图重建，避免中途重排。

## Root Cause

当前单 panel 版本已经解决了早期双 panel 切换的断裂感，但仍有三类问题：

1. `NotchDisplayController` 仍以 `NSPanel.setFrame` 作为主动画驱动，视觉变化几乎全部发生在窗口层。
2. `refreshContent()` 每次都会重建 `NSHostingView.rootView` 并重新测量展开内容，高频刷新时容易和动画叠加。
3. `NotchPanelRootView` 的正文在 `expanding` 相位直接全量可见，缺少 opacity / blur / offset 的内容层过渡。

## Chosen Approach

采用“小步快跑”的平滑化方案，而不是再次大改窗口结构。

### Stable Root View

- 引入常驻的 `NotchPanelViewState`。
- `NSHostingView` 只创建一次。
- 后续更新只修改状态对象，不再在刷新路径里反复替换 `rootView`。

### Deferred Transition Refresh

- 展开/收起动画进行中，数据更新只缓存最新 payload。
- 动画结束后再统一刷新内容与尺寸。
- 动画开始时只做一次必要的展开尺寸测量；收起期间不重复测量。

### Content-Layer Motion

- 为 `NotchPanelLayoutModel` 增加正文 reveal 参数：
  - `bodyOpacity`
  - `bodyOffsetY`
  - `bodyBlurRadius`
  - `bodyScale`
  - `surfaceOpacity`
- `NotchPanelRootView` 依据这些参数做内容层动画，并复用现有 `blurFade` 过渡。

### CodeIsland Borrowing

本次参考 `CodeIsland` 的两个思路：

1. `NotchAnimation` 统一作为展开/收起/微交互的动画 token。
2. 自定义 `NSHostingView`，把 `needsLayout` / `needsUpdateConstraints` 延迟到下一个 run loop，降低 SwiftUI 与 AppKit 在动画中的重入抖动风险。

## Validation

修复后需要满足：

1. 展开时正文不会第一帧整块跳出，而是伴随轻微淡入、上方位移回正和 blur 消退。
2. 收起时正文先柔和退出，再由窗口 frame 收回，不再显得突然。
3. 动画期间外部数据刷新不再触发内容重新测量和 root view 重建。
4. 展开完成后仍保留现有交互、命中区和内容布局。
