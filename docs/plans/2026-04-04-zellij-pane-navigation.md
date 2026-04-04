# Zellij Pane Navigation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 让 VibeBar 在切到正确 zellij tab 后，尽量把焦点继续移动到 agent 所在 pane。

**Architecture:** 在现有 `SessionNavigator` 的 zellij 跳转链路上追加一层 pane 级 best-effort 聚焦。具体做法是解析 `dump-layout`，定位当前焦点 pane 和目标 pane，并通过 `move-focus` 迭代逼近目标。

**Tech Stack:** Swift 6.2, Foundation, AppKit, Swift Testing, zellij CLI

---

### Task 1: 补 pane 聚焦设计文档

**Files:**
- Create: `/Users/yelog/workspace/swift/VibeBar/docs/plans/2026-04-04-zellij-pane-navigation-design.md`
- Create: `/Users/yelog/workspace/swift/VibeBar/docs/plans/2026-04-04-zellij-pane-navigation.md`

**Step 1: 写入设计与实现计划**

- 说明 zellij CLI 的能力边界
- 说明为什么只能做 best-effort
- 定义 pane 匹配和方向推导规则

**Step 2: 校验文档路径和命名**

Run: `ls /Users/yelog/workspace/swift/VibeBar/docs/plans`
Expected: 能看到新增文档

### Task 2: 实现 pane 布局解析与方向推导

**Files:**
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/SessionNavigator.swift`
- Test: `/Users/yelog/workspace/swift/VibeBar/Tests/VibeBarAppTests/SessionNavigatorTests.swift`

**Step 1: 写失败测试**

- 为 zellij layout 中的 pane 解析、目标 pane 匹配、方向推导写测试

**Step 2: 运行测试确认失败**

Run: `swift test --filter SessionNavigatorTests`
Expected: 新增断言失败

**Step 3: 实现最小逻辑**

- 解析当前 focused tab 的 pane 树
- 推断目标 pane
- 计算下一步方向
- 迭代执行 `move-focus`

**Step 4: 再跑测试确认通过**

Run: `swift test --filter SessionNavigatorTests`
Expected: PASS

### Task 3: 全量验证

**Files:**
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/SessionNavigator.swift`
- Test: `/Users/yelog/workspace/swift/VibeBar/Tests/VibeBarAppTests/SessionNavigatorTests.swift`

**Step 1: 全量构建**

Run: `swift build`
Expected: PASS

**Step 2: 全量测试**

Run: `swift test`
Expected: PASS
