# Zellij Tab Navigation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 让运行在 zellij 中的 session 点击后可以切到正确 tab，而不是只激活外层终端应用。

**Architecture:** 扩展 `TerminalContext` 以容纳 zellij tab 元数据；在 App 层新增 zellij layout 解析与 tab 推断逻辑；更新 `SessionNavigator`，优先按已知 tab name 跳转，缺失时再基于 `dump-layout + cwd` 临时推断。

**Tech Stack:** Swift 6.2, Foundation, AppKit, Swift Testing

---

### Task 1: Extend terminal context for zellij tab metadata

**Files:**
- Modify: `Sources/VibeBarCore/Models.swift`
- Modify: `Sources/VibeBarCore/TerminalContextResolver.swift`
- Test: `Tests/VibeBarCoreTests/HookContextTests.swift`

**Step 1: Write the failing test**

新增测试，断言 resolver 能从 metadata 中恢复：

- `sessionManagerTabName`
- `sessionManagerTabIndex`

**Step 2: Run test to verify it fails**

Run: `swift test --filter HookContextTests`
Expected: FAIL with missing zellij tab fields.

**Step 3: Write minimal implementation**

- 为 `TerminalContext` 增加 zellij tab 字段
- 让 resolver 兼容 `ZELLIJ_TAB_NAME` / `ZELLIJ_TAB_INDEX`

**Step 4: Re-run focused test**

Run: `swift test --filter HookContextTests`
Expected: PASS

### Task 2: Add zellij layout parser and tab inference

**Files:**
- Modify: `Sources/VibeBarApp/SessionNavigator.swift`
- Test: `Tests/VibeBarAppTests/SessionNavigatorTests.swift`

**Step 1: Write the failing test**

新增测试覆盖：

- `dump-layout` 解析出 tab name 和 cwd
- 使用 session cwd 能匹配到正确 tab name
- 无匹配时返回 nil

**Step 2: Run test to verify it fails**

Run: `swift test --filter SessionNavigatorTests`
Expected: FAIL with missing parser/inference logic.

**Step 3: Write minimal implementation**

- 新增 zellij layout 解析结构
- 新增 `inferZellijTabName(sessionName:cwd:)`
- 优先使用 `TerminalContext.sessionManagerTabName`

**Step 4: Re-run focused test**

Run: `swift test --filter SessionNavigatorTests`
Expected: PASS

### Task 3: Replace zellij no-op query with actual tab navigation

**Files:**
- Modify: `Sources/VibeBarApp/SessionNavigator.swift`

**Step 1: Write minimal implementation**

- 把 `focusZellijSession()` 从 `query-tab-names` 改为：
  - `go-to-tab-name` when known
  - infer + `go-to-tab-name` when unknown
  - final app activation fallback

**Step 2: Run build**

Run: `swift build`
Expected: PASS

### Task 4: Full validation

**Files:**
- Test: `Tests/VibeBarAppTests/SessionNavigatorTests.swift`
- Test: `Tests/VibeBarCoreTests/HookContextTests.swift`

**Step 1: Run focused tests**

Run: `swift test --filter SessionNavigatorTests`
Expected: PASS

Run: `swift test --filter HookContextTests`
Expected: PASS

**Step 2: Run full suite**

Run: `swift test`
Expected: PASS

**Step 3: Run build**

Run: `swift build`
Expected: PASS
