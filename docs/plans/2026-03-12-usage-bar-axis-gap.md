# Usage Bar Axis Gap Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 修复 Token Usage 紧凑柱状图默认状态下与坐标轴之间的固定空隙过大的问题，让柱子在非 hover 状态下也更贴近坐标轴。

**Architecture:** 保持现有 hover/tooltip 与柱子绘制逻辑不变，仅调整紧凑柱状图和坐标轴的固定布局常量。通过收紧柱状图区与坐标轴之间的 `VStack` 间距，并上移坐标轴线与刻度点的垂直位置，消除默认状态的多余空白。

**Tech Stack:** Swift 6.2、SwiftUI、VibeBarCore

---

### Task 1: 收紧柱状图与坐标轴的默认间距

**Files:**
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/UsageMenuSectionView.swift`
- Test: `swift build`

**Step 1: 确认间距来源**

检查 `barChartView` 外层 `VStack` 的 `spacing`，以及 `UsageCompactChartAxisView` 中轴线和刻度点的固定 `y` 坐标。

**Step 2: 调整布局常量**

将柱状图区与坐标轴之间的 `spacing` 调小到 0，并把轴线与刻度点在轴视图中的位置上移，减少默认视觉空隙。

**Step 3: 保持交互不变**

确认 hover 高亮和 tooltip 逻辑不需要修改，避免引入新的交互回归。

**Step 4: 运行构建验证**

Run: `swift build`
Expected: BUILD SUCCEEDED

**Step 5: 提交**

```bash
git add /Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/UsageMenuSectionView.swift /Users/yelog/workspace/swift/VibeBar/docs/plans/2026-03-12-usage-bar-axis-gap.md
git commit -m "fix(usage): tighten compact bar axis gap"
```
