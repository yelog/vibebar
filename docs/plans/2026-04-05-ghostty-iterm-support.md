# Ghostty And iTerm2 Deep Support Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 为 VibeBar 增加 `Ghostty` 的 tab 级可靠支持和 pane 级 best-effort 跳转，以及 `iTerm2` 的 tab/pane 精确支持。

**Architecture:** 扩展 `TerminalContext` 保存脚本定位元数据，在刷新阶段用 AppleScript 快照为 `Ghostty/iTerm2` 补齐 `tab/session` 信息，在导航阶段分别走 `Ghostty terminal focus` 和 `iTerm2 session select`。保持现有 `Kitty/WezTerm/tmux/zellij` 链路不变。

**Tech Stack:** Swift 6.2、AppKit/SwiftUI、AppleScript (`osascript`)、Swift Testing

---

### Task 1: 扩展终端上下文字段

**Files:**
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/Models.swift`
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/TerminalContextResolver.swift`
- Test: `/Users/yelog/workspace/swift/VibeBar/Tests/VibeBarCoreTests/HookContextTests.swift`

**Step 1: 写失败测试**

- 让 `TerminalContext` roundtrip 覆盖新增字段
- 验证 merge 后不会丢失 `clientTabID / clientNativeSessionID`

**Step 2: 运行测试确认失败**

Run: `swift test --filter HookContextTests`

Expected:
- Codable 或 merge 断言失败

**Step 3: 写最小实现**

- 在 `TerminalContext` 增加：
  - `clientTabID`
  - `clientNativeSessionID`
- 在 `TerminalContextResolver.merge` 中补齐合并逻辑

**Step 4: 运行测试确认通过**

Run: `swift test --filter HookContextTests`

Expected:
- PASS

### Task 2: 实现 Ghostty 快照解析与 enrichment

**Files:**
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/AppModel.swift`
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/SessionNavigator.swift`
- Test: `/Users/yelog/workspace/swift/VibeBar/Tests/VibeBarAppTests/SessionNavigatorTests.swift`

**Step 1: 写失败测试**

- 为 Ghostty AppleScript 输出添加 fixture
- 验证能解析出：
  - `window id`
  - `tab id`
  - `tab index`
  - `terminal id`
  - `working directory`
- 验证能按 `cwd` 选中唯一 terminal

**Step 2: 运行测试确认失败**

Run: `swift test --filter SessionNavigatorTests`

Expected:
- Ghostty 解析与匹配测试失败

**Step 3: 写最小实现**

- 在 `SessionNavigator` 增加：
  - Ghostty AppleScript 快照加载
  - 快照解析
  - `resolveGhosttyTarget(...)`
- 在 `AppModel` 中增加 `enrichGhosttyTabs`
- merge 回：
  - `clientWindowID`
  - `clientTabID`
  - `clientTabIndex`
  - `clientNativeSessionID`

**Step 4: 运行测试确认通过**

Run: `swift test --filter SessionNavigatorTests`

Expected:
- PASS

### Task 3: 实现 iTerm2 快照解析与 enrichment

**Files:**
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/AppModel.swift`
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/SessionNavigator.swift`
- Test: `/Users/yelog/workspace/swift/VibeBar/Tests/VibeBarAppTests/SessionNavigatorTests.swift`

**Step 1: 写失败测试**

- 为 iTerm2 AppleScript 输出添加 fixture
- 验证能按 `tty` 匹配：
  - `window id`
  - `tab index`
  - `session unique id`

**Step 2: 运行测试确认失败**

Run: `swift test --filter SessionNavigatorTests`

Expected:
- iTerm2 匹配测试失败

**Step 3: 写最小实现**

- 在 `SessionNavigator` 增加：
  - iTerm2 AppleScript 快照加载
  - 快照解析
  - `resolveITermTarget(...)`
- 在 `AppModel` 中增加 `enrichITermTabs`

**Step 4: 运行测试确认通过**

Run: `swift test --filter SessionNavigatorTests`

Expected:
- PASS

### Task 4: 增加 Ghostty 与 iTerm2 导航策略

**Files:**
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/SessionNavigator.swift`
- Test: `/Users/yelog/workspace/swift/VibeBar/Tests/VibeBarAppTests/SessionNavigatorTests.swift`

**Step 1: 写失败测试**

- 验证 `Ghostty` session 生成 `focusGhosttyTerminal`
- 验证 `iTerm2` session 生成 `focusITermSession`

**Step 2: 运行测试确认失败**

Run: `swift test --filter SessionNavigatorTests`

Expected:
- Jump plan 断言失败

**Step 3: 写最小实现**

- 在 `SessionJumpStrategy` 增加：
  - `focusGhosttyTerminal`
  - `focusITermSession`
- 执行逻辑增加 AppleScript 驱动跳转
- 保留最后的 bundle 激活作为回退

**Step 4: 运行测试确认通过**

Run: `swift test --filter SessionNavigatorTests`

Expected:
- PASS

### Task 5: 增加 UI 展示

**Files:**
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/SessionDisplayFormatter.swift`
- Test: `/Users/yelog/workspace/swift/VibeBar/Tests/VibeBarAppTests/SessionDisplayFormatterTests.swift`

**Step 1: 写失败测试**

- `Ghostty` 带 `clientTabIndex=2` 显示 `Ghostty #2`
- `iTerm2` 带 `clientTabIndex=1` 显示 `iTerm #1`

**Step 2: 运行测试确认失败**

Run: `swift test --filter SessionDisplayFormatterTests`

Expected:
- Badge 断言失败

**Step 3: 写最小实现**

- 在 `clientBadge(for:)` 中增加 `iTerm #n`
- 保持 Ghostty 分支支持 `#n`

**Step 4: 运行测试确认通过**

Run: `swift test --filter SessionDisplayFormatterTests`

Expected:
- PASS

### Task 6: 跑全量验证

**Files:**
- Modify: `/Users/yelog/workspace/swift/VibeBar/Tests/VibeBarAppTests/SessionNavigatorTests.swift`
- Modify: `/Users/yelog/workspace/swift/VibeBar/Tests/VibeBarCoreTests/HookContextTests.swift`
- Modify: `/Users/yelog/workspace/swift/VibeBar/Tests/VibeBarAppTests/SessionDisplayFormatterTests.swift`

**Step 1: 跑目标测试**

Run:
- `swift test --filter HookContextTests`
- `swift test --filter SessionNavigatorTests`
- `swift test --filter SessionDisplayFormatterTests`

Expected:
- 全部 PASS

**Step 2: 跑全量构建**

Run:
- `swift build`
- `swift test`

Expected:
- 全部 PASS

**Step 3: Commit**

```bash
git add /Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/Models.swift \
  /Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/TerminalContextResolver.swift \
  /Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/AppModel.swift \
  /Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/SessionNavigator.swift \
  /Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/SessionDisplayFormatter.swift \
  /Users/yelog/workspace/swift/VibeBar/Tests/VibeBarCoreTests/HookContextTests.swift \
  /Users/yelog/workspace/swift/VibeBar/Tests/VibeBarAppTests/SessionNavigatorTests.swift \
  /Users/yelog/workspace/swift/VibeBar/Tests/VibeBarAppTests/SessionDisplayFormatterTests.swift
git commit -m "feat(navigation): deepen ghostty and iterm support"
```
