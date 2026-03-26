# Notch Native Origin Animation Design

**Date:** 2026-03-26

**Status:** Confirmed

## Summary

本次设计调整刘海展开/收起动画的起点与节奏：

1. 展开动画从真实刘海位置开始，而不是固定的 seed 矩形。
2. 起始尺寸与原生刘海尺寸一致，优先使用 `auxiliaryTopLeftArea / auxiliaryTopRightArea` 推导出的真实几何。
3. 动画使用单段非线性过渡，让宽高在一次窗口动画里同步变化。
4. 收起态仍保留现有“刘海右侧延展块”入口，不改收起后的静态外观。

## Root Cause

当前实现虽然已经能拿到真实刘海几何，但展开/收起动画没有使用它：

1. `animationSeedFrame` 仍使用固定的 `44x18` 尺寸。
2. 两段式 frame 动画会把阶段感暴露出来，宽高变化不够一体。
3. 这会削弱“从刘海自然长出来 / 缩回刘海里”的感觉。

## Chosen Approach

采用“真实刘海 seed + 单段非线性 frame 动画”的最小修改方案。

### Geometry

- 展开和收起都以 `geometry.notchFrame` 作为起点或终点。
- 当系统能返回真实刘海几何时，动画与原生刘海位置、尺寸对齐。
- 当系统拿不到真实刘海几何时，继续回退到现有估算逻辑，保证行为稳定。

### Animation

- 展开和收起都使用单段 `NSAnimationContext` 动画。
- 展开时从真实刘海 frame 直接过渡到最终面板 frame，但继续使用非线性贝塞尔曲线。
- 收起时从最终面板 frame 直接缩回真实刘海 frame，保持展开/收起在视觉上更统一。

### Panel Ownership

- 收起态继续使用 `collapsedPanel` 承载右侧延展块。
- 展开动画开始时立即让 `expandedPanel` 接管视觉变化。
- 收起动画完成后再恢复 `collapsedPanel`，避免把需求扩大成新的多窗口同步重构。

## Validation

需要满足以下结果：

1. 展开时宽高同步变化，不再出现明显的“两段感”。
2. 收起时宽高同步缩回真实刘海区域。
3. 收起完成后仍回到当前右侧延展块外观。
4. hover 热区与展开中的保活逻辑不回归。
