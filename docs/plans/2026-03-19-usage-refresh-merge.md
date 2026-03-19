# Usage Refresh Merge Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 合并 Usage 的自动刷新和完整校验为单一刷新路径，并保留清缓存重建入口。

**Architecture:** `UsageMonitorViewModel` 的自动与手动刷新统一走安全版 full refresh 路径；设置页移除独立的完整校验区域，只展示单一刷新设置和清缓存重建操作。保留现有 loader 与数据结构，尽量减少对持久化和历史状态的影响。

**Tech Stack:** Swift 6.2, SwiftUI, Foundation

---

### Task 1: 调整刷新调度

**Files:**
- Modify: `Sources/VibeBarApp/UsageMonitorViewModel.swift`

**Step 1:** 让定时刷新和 `refreshNow()` 统一走单一路径。  
**Step 2:** 移除 `usageFullRefreshInterval` 对刷新调度的影响。  
**Step 3:** 让单一刷新状态负责 UI 反馈，保留清缓存重建逻辑。

### Task 2: 简化设置页

**Files:**
- Modify: `Sources/VibeBarApp/UsageSettingsView.swift`
- Modify: `Sources/VibeBarApp/SettingsView.swift`
- Modify: `Sources/VibeBarCore/L10nStrings.swift`

**Step 1:** 移除独立的完整校验按钮和频率分段控件。  
**Step 2:** 保留一个“刷新”入口和“清缓存重建”入口。  
**Step 3:** 更新文案，确保语义与当前实现一致。

### Task 3: 验证

**Files:**
- Modify: none

**Step 1:** `swift build`  
**Step 2:** 搜索残留引用，确认没有 UI/调度死代码导致的编译问题。
