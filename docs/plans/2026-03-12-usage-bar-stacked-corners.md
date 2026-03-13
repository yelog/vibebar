# Usage Bar Stacked Corners Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 修复 Token Usage 柱状图中同一根堆叠柱出现多重圆角和分段缝隙的问题，只保留整根柱子的上下圆角。

**Architecture:** 保持现有 bucket/series 聚合与颜色分配逻辑不变，仅调整紧凑柱状图的绘制方式。每个分段改为无圆角矩形并使用零间距垂直堆叠，最后通过整根柱子的统一圆角形状裁剪内容。

**Tech Stack:** Swift 6.2、SwiftUI、VibeBarCore

---

### Task 1: 修复紧凑柱状图堆叠圆角

**Files:**
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/UsageMenuSectionView.swift`
- Test: `swift build`

**Step 1: 确认问题实现位置**

检查 `barChartView` 中的柱状图绘制代码，确认当前分段使用了独立 `Capsule()`，且 `VStack` 使用了非零 `spacing`。

**Step 2: 调整分段绘制方式**

将每个分段改为普通矩形填充，移除分段之间的间距，保持现有高度计算和颜色映射不变。

**Step 3: 统一整根柱子的圆角裁剪**

对堆叠后的整根柱子应用统一的圆角裁剪，让顶部和底部保留圆角，中间接缝保持完全平直。

**Step 4: 运行构建验证**

Run: `swift build`
Expected: BUILD SUCCEEDED

**Step 5: 提交**

```bash
git add /Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/UsageMenuSectionView.swift /Users/yelog/workspace/swift/VibeBar/docs/plans/2026-03-12-usage-bar-stacked-corners.md
git commit -m "fix(usage): unify stacked bar corners"
```
