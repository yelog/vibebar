# Kitty Navigation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 让运行在 Kitty 原生 tab/split 中的 session，点击时能精确切到对应 tab 并聚焦正确 pane。

**Architecture:** 扩展 `TerminalContext` 记录 Kitty remote control 地址，然后在 `SessionNavigator` 中新增 Kitty 专用导航策略。导航器优先按 `KITTY_WINDOW_ID` 聚焦，失败时再用 `kitty @ ls` 按 `pid/cwd` 回退匹配。

**Tech Stack:** Swift 6.2, Foundation, AppKit, Swift Testing, Kitty remote control

---

### Task 1: 补 Kitty 设计与计划文档

**Files:**
- Create: `/Users/yelog/workspace/swift/VibeBar/docs/plans/2026-04-04-kitty-navigation-design.md`
- Create: `/Users/yelog/workspace/swift/VibeBar/docs/plans/2026-04-04-kitty-navigation.md`

**Step 1: 写入设计与实现计划**

- 说明 Kitty 和 zellij 的能力差异
- 定义控制地址采集与回退匹配策略

**Step 2: 校验文档存在**

Run: `ls /Users/yelog/workspace/swift/VibeBar/docs/plans`
Expected: 能看到新增 Kitty 文档

### Task 2: 扩展 terminal context 与导航器

**Files:**
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/Models.swift`
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/DetectorSupport.swift`
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/TerminalContextResolver.swift`
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/SessionNavigator.swift`

**Step 1: 写失败测试**

- 增加 Kitty 控制地址解析和导航计划测试

**Step 2: 运行测试确认失败**

Run: `swift test --filter HookContextTests`
Run: `swift test --filter SessionNavigatorTests`
Expected: 新增测试失败

**Step 3: 写最小实现**

- 采集 `KITTY_LISTEN_ON`
- 增加 Kitty 导航策略
- 解析 `kitty @ ls`
- 实现 `focus-tab + focus-window`

**Step 4: 再跑测试确认通过**

Run: `swift test --filter HookContextTests`
Run: `swift test --filter SessionNavigatorTests`
Expected: PASS

### Task 3: 全量验证

**Files:**
- Modify: `/Users/yelog/workspace/swift/VibeBar/Tests/VibeBarCoreTests/HookContextTests.swift`
- Modify: `/Users/yelog/workspace/swift/VibeBar/Tests/VibeBarAppTests/SessionNavigatorTests.swift`

**Step 1: 全量构建**

Run: `swift build`
Expected: PASS

**Step 2: 全量测试**

Run: `swift test`
Expected: PASS
