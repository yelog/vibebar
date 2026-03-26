# Notch Native Origin Animation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 让刘海展开/收起动画从真实刘海位置和尺寸起步，并改成单段非线性宽高同步过渡。

**Architecture:** 保留现有 `collapsedPanel` 右侧延展块作为收起态入口，只修改 `NotchDisplayController` 的动画几何与时序。展开和收起都以真实刘海 frame 作为起点或终点，用单段 `setFrame` 动画同步驱动宽高变化，去掉中间态 frame。

**Tech Stack:** Swift 6.2, AppKit, SwiftUI, Swift Package Manager

---

### Task 1: 收敛动画 seed 到真实刘海几何

**Files:**
- Modify: `Sources/VibeBarApp/NotchDisplayController.swift`

**Step 1: 删除固定 seed 尺寸依赖**

移除 `44x18` 固定 seed 的使用，让动画起点直接使用 `geometry.notchFrame`。

**Step 2: 保持起点收敛**

确认展开起点与收起终点都直接使用 `geometry.notchFrame`，不再额外生成 seed 尺寸。

**Step 3: 构建验证**

Run: `swift build --target VibeBarApp`
Expected: BUILD SUCCEEDED

### Task 2: 把两段式动画收敛回单段非线性过渡

**Files:**
- Modify: `Sources/VibeBarApp/NotchDisplayController.swift`

**Step 1: 改造展开路径**

把展开改为从 `notchFrame` 直接过渡到最终面板 frame 的单段贝塞尔动画。

**Step 2: 改造收起路径**

把收起改为从最终面板 frame 直接缩回 `notchFrame` 的单段贝塞尔动画。

**Step 3: 删除中间态逻辑**

移除 `columnFrame` 和相关时长常量，避免代码继续保留两段式结构。

**Step 4: 构建验证**

Run: `swift build --target VibeBarApp`
Expected: BUILD SUCCEEDED

### Task 3: 回归验证交互与视觉

**Files:**
- None

**Step 1: 验证展开轨迹**

确认面板不是从固定小矩形弹出，而是从刘海本体位置以宽高同步方式展开。

**Step 2: 验证收起轨迹**

确认面板以宽高同步方式缩回刘海本体。

**Step 3: 验证入口形态**

确认收起后仍恢复为现有右侧延展块，而不是永久停在原生刘海大小。
