# Notch Single Panel Design

**Date:** 2026-03-26

**Status:** Confirmed

## Summary

本次设计把刘海展开态从“顶部遮罩 panel + 下拉内容 panel”改为“单一展开 panel”。

核心目标：

1. 让展开与收起动画只由一个 `NSPanel` 驱动，避免两个窗口的动画事务不同步。
2. 保留当前“刘海顶盖 + 下拉内容”一体化视觉，不回退为普通悬浮卡片。
3. 让 `collapsedPanel` 只负责收起态右侧小块，展开态完全交给 `expandedPanel`。

## Root Cause

当前实现的时序问题来自结构本身：

1. `collapsedPanel` 在展开态被切成 bridge 顶盖形态，但它不是下拉内容的一部分。
2. `expandedPanel` 单独负责主体下拉动画，`collapsedPanel` 只是静态停在顶部。
3. 收起时 `expandedPanel` 已完成缩回，而 `collapsedPanel` 要等 completion 才切回收起态，因此用户会看到黑色遮罩滞留。

## Chosen Approach

采用“单 expandedPanel + 收起态独立 collapsedPanel”的方案。

### Panel Ownership

- 收起态：只显示 `collapsedPanel`。
- 展开开始：创建并显示 `expandedPanel`，其中同时包含 bridge 顶盖和正文内容。
- 展开完成后：隐藏 `collapsedPanel`。
- 收起开始到结束：只动画 `expandedPanel`。
- 收起完成后：隐藏 `expandedPanel`，恢复 `collapsedPanel`。

### View Composition

- 在 [NotchContentView.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/NotchContentView.swift) 顶部增加 bridge 顶盖层。
- bridge 顶盖直接复用 [NotchCollapsedView.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/NotchCollapsedView.swift) 的 `bridge` 展示能力，避免重写图标定位和形状逻辑。
- 正文继续保持当前安全区留白和内容区结构。

### Animation Behavior

- 展开和收起时，不再让 `collapsedPanel` 参与 bridge 动画。
- `expandedPanel` 从 seed frame 展开，也从 seed frame 收起。
- `collapsedPanel` 只在展开前和收起后瞬时切换显示状态。

## Validation

修复后需要满足：

1. 展开过程中只看到一个整体窗口在变化，不再出现“下拉已收回但黑色遮罩还留在顶部”。
2. 展开后刘海顶盖和正文仍保持一体化。
3. 收起完成后只剩右侧小块图标区。
4. hover 进入、离开、桥接热区行为不回归。
