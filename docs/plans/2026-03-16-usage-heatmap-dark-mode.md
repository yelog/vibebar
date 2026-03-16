# Usage Heatmap Dark Mode Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 提升 usage Github 热力图在 macOS 暗色模式下的对比度、层次和可读性，同时保持现有 GitHub 风格语义。

**Architecture:** 将热力图的视觉规则收敛到共享的 `UsageHeatmapView`/`UsageHeatmapGridView` 组件中，通过按 `colorScheme` 切换的离散色阶、非线性强度映射和更清晰的容器底板实现暗色适配。菜单卡片与设置页预览继续复用同一套热力图组件，避免重复维护。

**Tech Stack:** Swift 6.2, SwiftUI, macOS 13+

---

### Task 1: 规划热力图暗色主题

**Files:**
- Modify: `Sources/VibeBarApp/UsageHeatmapView.swift`

**Step 1: 定义热力图主题模型**

在热力图视图文件中添加内部主题结构，明确空状态底色、边框色、悬浮态描边色和 5 档离散热力色。

**Step 2: 将填充颜色改为主题驱动**

把当前固定绿色渐变替换为亮色/暗色两套离散色阶，确保低档位在暗色背景下仍可辨认。

**Step 3: 引入非线性强度映射**

对原始强度做非线性压缩，避免极值导致大多数格子落入不可见区间。

### Task 2: 提升热力图信息层级

**Files:**
- Modify: `Sources/VibeBarApp/UsageHeatmapView.swift`
- Reference: `Sources/VibeBarApp/UsageMenuSectionView.swift`

**Step 1: 调整容器视觉层**

为热力图容器提供更明确的底板和细边框，拉开卡片背景与图元的层级。

**Step 2: 强化交互反馈**

为 hover 单元格增加描边或高亮，而不是仅依赖 tooltip。

**Step 3: 同步 legend 展示**

让 legend 与热力图使用同一套主题色阶，避免认知偏差。

### Task 3: 验证与回归检查

**Files:**
- Verify: `Sources/VibeBarApp/UsageHeatmapView.swift`

**Step 1: 构建项目**

Run: `swift build`
Expected: 构建成功，无新增编译错误

**Step 2: 检查影响面**

确认设置页预览和菜单卡片都通过共享组件获得新样式，不需要额外改动现有业务逻辑。
