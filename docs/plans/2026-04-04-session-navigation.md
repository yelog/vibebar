# Session Navigation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 为 VibeBar 增加结构化 terminal badge 展示，并让 session 行支持基于 `terminalContext` 的终端跳转。

**Architecture:** 先在 App 层抽出统一的 badge/presentation 模型，让菜单栏和刘海共享同一份 `terminalContext` 展示逻辑；再新增 `SessionNavigator` 作为跳转服务，负责把 `tmux / zellij / desktop / terminal client` 映射成可执行动作，并接入 session 行点击事件。

**Tech Stack:** Swift 6.2, AppKit, SwiftUI, Foundation, Swift Testing

---

### Task 1: Build a shared badge presentation model

**Files:**
- Modify: `Sources/VibeBarApp/SessionDisplayFormatter.swift`
- Create: `Sources/VibeBarApp/SessionBadgeView.swift`
- Test: `Tests/VibeBarAppTests/SessionDisplayFormatterTests.swift`

**Step 1: Write the failing test**

新增测试，断言：

- `Codex Desktop` 会生成 desktop badge
- `Kitty + tmux + tty` 会生成按优先级排序的 badge
- 无终端上下文时 badge 为空

**Step 2: Run test to verify it fails**

Run: `swift test --filter SessionDisplayFormatterTests`
Expected: FAIL with missing badge API.

**Step 3: Write minimal implementation**

- 在 `SessionDisplayFormatter` 中新增 `badges(for:)`
- 新增 badge 视图，供 SwiftUI 行渲染
- 保留现有 `primaryText` / `directoryText`

**Step 4: Re-run focused test**

Run: `swift test --filter SessionDisplayFormatterTests`
Expected: PASS

### Task 2: Wire badges into notch and menu rows

**Files:**
- Modify: `Sources/VibeBarApp/NotchContentView.swift`
- Modify: `Sources/VibeBarApp/StatusItemController.swift`

**Step 1: Write the failing test**

不写 UI 快照测试，改用构建和已有 App 测试做 smoke check。

**Step 2: Write minimal implementation**

- 在 notch 的 session row 下方渲染 badge strip
- 在 `SessionMenuItemView` 中增加 badge 行
- 调整 item 高度，避免 badge 被截断

**Step 3: Run validation**

Run: `swift build`
Expected: PASS

### Task 3: Add a session navigator with tmux/zellij-aware planning

**Files:**
- Create: `Sources/VibeBarApp/SessionNavigator.swift`
- Test: `Tests/VibeBarAppTests/SessionNavigatorTests.swift`

**Step 1: Write the failing test**

新增测试覆盖：

- `Codex Desktop` -> app activation
- `tmux` -> 解析 socket + pane target
- `zellij` -> session 级跳转计划 + app activation fallback
- `kitty` / `iTerm` -> client activation优先

**Step 2: Run test to verify it fails**

Run: `swift test --filter SessionNavigatorTests`
Expected: FAIL with missing navigator.

**Step 3: Write minimal implementation**

- 新增 `SessionNavigator`
- 抽纯函数生成跳转计划
- 执行层负责：
  - shell command
  - AppleScript
  - app activation

**Step 4: Re-run focused test**

Run: `swift test --filter SessionNavigatorTests`
Expected: PASS

### Task 4: Connect session row clicks to navigator

**Files:**
- Modify: `Sources/VibeBarApp/StatusItemController.swift`
- Modify: `Sources/VibeBarApp/NotchDisplayController.swift`
- Modify: `Sources/VibeBarApp/NotchContentView.swift`

**Step 1: Write minimal implementation**

- `StatusItemController` 注入 navigator
- 菜单中的 `SessionMenuItemView` 支持点击
- notch 中的 session row 改为可点击
- notch 点击后折叠并执行跳转

**Step 2: Run validation**

Run: `swift build`
Expected: PASS

### Task 5: Full validation and docs

**Files:**
- Modify: `README.md` (optional if user-visible interaction changes需要说明)

**Step 1: Run full test suite**

Run: `swift test`
Expected: PASS

**Step 2: Run build**

Run: `swift build`
Expected: PASS

**Step 3: Manual verification**

- 从菜单点击带 `tmux` badge 的 session，确认 outer terminal 被激活
- 从刘海点击 `Codex Desktop` session，确认 Codex 被激活
- 点击 `zellij` session，确认至少激活正确 terminal app，并尝试附着到目标 session
