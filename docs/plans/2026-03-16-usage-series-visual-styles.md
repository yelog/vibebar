# Usage Series Visual Styles Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 提升 usage 多序列折线图和图例的区分度，避免系列数量增多时出现撞色和映射不稳定问题。

**Architecture:** 在共享调色板层引入稳定的系列视觉样式映射，统一管理颜色、虚线模式和图例样本；折线图与设置页紧凑预览复用这套样式，保持不同视图的一致性。对 `Others` 使用中性色，不占用高辨识度主色位。

**Tech Stack:** Swift 6.2, SwiftUI, Charts, macOS 13+

---

### Task 1: 设计共享系列视觉样式

**Files:**
- Modify: `Sources/VibeBarApp/UsageSeriesLegendView.swift`

**Step 1: 建立视觉样式模型**

为系列定义共享样式，至少包含颜色和线段 dash 信息，供图例与线图复用。

**Step 2: 提供稳定分配策略**

将现有按索引取模的配色逻辑改为按 `series.id` 稳定分配，同时扩充高差异调色板并为 `Others` 保留中性色。

**Step 3: 支持图例样式变体**

让图例既支持原有色块，也支持线段样本，以便在线图场景中展示颜色和线型。

### Task 2: 同步线图样式

**Files:**
- Modify: `Sources/VibeBarApp/UsageLineChartView.swift`
- Modify: `Sources/VibeBarApp/UsageMenuSectionView.swift`

**Step 1: 桌面折线图改用共享样式**

桌面 `Charts` 线图直接使用共享颜色和线型，而不是只通过 label 到颜色的映射。

**Step 2: 紧凑预览折线图改用共享样式**

设置页预览和菜单中的自绘线图使用同一套颜色与 dash 规则，避免和图例脱节。

**Step 3: 线图图例显示线样本**

在线图场景下，图例展示一段带点位的线样本，而不是单纯色块。

### Task 3: 验证

**Files:**
- Verify: `Sources/VibeBarApp/UsageSeriesLegendView.swift`
- Verify: `Sources/VibeBarApp/UsageLineChartView.swift`
- Verify: `Sources/VibeBarApp/UsageMenuSectionView.swift`

**Step 1: 构建项目**

Run: `swift build`
Expected: 构建成功，无新增编译错误

**Step 2: 回归视觉一致性**

确认折线、图例、tooltip 及紧凑预览中的系列颜色映射一致，不再出现明显撞色。
