# WezTerm Support Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 为 VibeBar 增加 `WezTerm` 的正式终端识别、`WezTerm #n` 展示和 pane 级精确跳转。

**Architecture:** 复用现有 `Kitty` 的 enrichment 模式和 `tmux/zellij` 的导航模式，在 `TerminalContext` 中把 `WEZTERM_PANE` 作为核心定位标识，在刷新阶段补全 tab index，在跳转阶段调用官方 `wezterm cli activate-pane`。

**Tech Stack:** Swift 6.2、AppKit/SwiftUI、`wezterm cli`、JSON decoding、Swift Testing

---

### Task 1: 扩展终端模型与环境采集

**Files:**
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/Models.swift`
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/DetectorSupport.swift`
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/TerminalContextResolver.swift`
- Test: `/Users/yelog/workspace/swift/VibeBar/Tests/VibeBarCoreTests/HookContextTests.swift`

**Step 1: 写失败测试**

- 在 `HookContextTests` 增加 `WEZTERM_PANE` / `WEZTERM_UNIX_SOCKET` 的识别断言
- 断言 `clientKind == .wezterm`
- 断言 `clientSessionID == WEZTERM_PANE`

**Step 2: 运行测试确认失败**

Run: `swift test --filter HookContextTests`

Expected:
- WezTerm 相关断言失败

**Step 3: 写最小实现**

- 在 `TerminalClientKind` 中新增 `.wezterm`
- 在 `DetectorSupport.parseEnvironmentDump` 中采集：
  - `WEZTERM_PANE`
  - `WEZTERM_UNIX_SOCKET`
- 在 `TerminalContextResolver` 中新增：
  - `WEZTERM_PANE` 命中识别
  - `wezterm-gui` 进程名识别
  - `clientSessionID = WEZTERM_PANE`
  - `clientControlAddress = WEZTERM_UNIX_SOCKET`

**Step 4: 运行测试确认通过**

Run: `swift test --filter HookContextTests`

Expected:
- PASS

**Step 5: Commit**

```bash
git add /Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/Models.swift \
  /Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/DetectorSupport.swift \
  /Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/TerminalContextResolver.swift \
  /Users/yelog/workspace/swift/VibeBar/Tests/VibeBarCoreTests/HookContextTests.swift
git commit -m "feat(core): detect wezterm sessions"
```

### Task 2: 增加 WezTerm 运行时枚举与 tab enrichment

**Files:**
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/AppModel.swift`
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/SessionNavigator.swift`
- Test: `/Users/yelog/workspace/swift/VibeBar/Tests/VibeBarAppTests/SessionNavigatorTests.swift`

**Step 1: 写失败测试**

- 为 `wezterm cli list --format json` 添加 fixture
- 断言能从 `pane_id` 匹配出：
  - `tab_id`
  - `window_id`
  - `tab index`

**Step 2: 运行测试确认失败**

Run: `swift test --filter SessionNavigatorTests`

Expected:
- WezTerm 解析相关测试失败

**Step 3: 写最小实现**

- 在 `SessionNavigator` 增加：
  - `weztermListOutput(socketPath:)`
  - `resolveWezTermTarget(...)`
- 在 `AppModel.performRefresh()` 增加 `WezTerm` enrichment
- 将 `clientTabIndex` merge 回 `terminalContext`

**Step 4: 运行测试确认通过**

Run: `swift test --filter SessionNavigatorTests`

Expected:
- PASS

**Step 5: Commit**

```bash
git add /Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/AppModel.swift \
  /Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/SessionNavigator.swift \
  /Users/yelog/workspace/swift/VibeBar/Tests/VibeBarAppTests/SessionNavigatorTests.swift
git commit -m "feat(app): enrich wezterm tab metadata"
```

### Task 3: 增加 WezTerm badge 展示

**Files:**
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/SessionDisplayFormatter.swift`
- Test: `/Users/yelog/workspace/swift/VibeBar/Tests/VibeBarAppTests/SessionDisplayFormatterTests.swift`

**Step 1: 写失败测试**

- 断言带 `clientTabIndex = 2` 的 WezTerm session 显示为 `WezTerm #2`
- 断言没有 index 时显示为 `WezTerm`

**Step 2: 运行测试确认失败**

Run: `swift test --filter SessionDisplayFormatterTests`

Expected:
- WezTerm badge 断言失败

**Step 3: 写最小实现**

- 在 `clientBadge(for:)` 中新增 WezTerm 分支

**Step 4: 运行测试确认通过**

Run: `swift test --filter SessionDisplayFormatterTests`

Expected:
- PASS

**Step 5: Commit**

```bash
git add /Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/SessionDisplayFormatter.swift \
  /Users/yelog/workspace/swift/VibeBar/Tests/VibeBarAppTests/SessionDisplayFormatterTests.swift
git commit -m "feat(ui): show wezterm tab indices"
```

### Task 4: 增加 WezTerm pane 级跳转

**Files:**
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/SessionNavigator.swift`
- Test: `/Users/yelog/workspace/swift/VibeBar/Tests/VibeBarAppTests/SessionNavigatorTests.swift`

**Step 1: 写失败测试**

- 断言 `SessionNavigator.plan(for:)` 会为 WezTerm session 生成 pane 级跳转策略
- 断言优先使用 `pane_id`

**Step 2: 运行测试确认失败**

Run: `swift test --filter SessionNavigatorTests`

Expected:
- WezTerm 跳转计划断言失败

**Step 3: 写最小实现**

- 在 `SessionJumpStrategy` 中新增 `focusWezTermPane`
- 在 `plan(for:)` 中增加 WezTerm 路径
- 执行逻辑调用 `wezterm cli activate-pane --pane-id <id>`
- 失败时回退到激活 `WezTerm.app`

**Step 4: 运行测试确认通过**

Run: `swift test --filter SessionNavigatorTests`

Expected:
- PASS

**Step 5: Commit**

```bash
git add /Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/SessionNavigator.swift \
  /Users/yelog/workspace/swift/VibeBar/Tests/VibeBarAppTests/SessionNavigatorTests.swift
git commit -m "feat(navigation): focus wezterm panes"
```

### Task 5: 让插件链路带出 WezTerm 元数据

**Files:**
- Modify: `/Users/yelog/workspace/swift/VibeBar/plugins/opencode-vibebar-plugin/index.js`
- Modify: `/Users/yelog/workspace/swift/VibeBar/plugins/claude-vibebar-plugin/scripts/emit.js`
- Test: `/Users/yelog/workspace/swift/VibeBar/Tests/VibeBarCoreTests/HookContextTests.swift`

**Step 1: 写失败测试**

- 验证 metadata 解码后能保留 `WEZTERM_PANE` 和 `WEZTERM_UNIX_SOCKET`

**Step 2: 运行测试确认失败**

Run: `swift test --filter HookContextTests`

Expected:
- 缺少 WezTerm 字段

**Step 3: 写最小实现**

- 在 OpenCode/Claude 插件 metadata 中加入：
  - `WEZTERM_PANE`
  - `WEZTERM_UNIX_SOCKET`

**Step 4: 运行验证**

Run:
- `node --check /Users/yelog/workspace/swift/VibeBar/plugins/opencode-vibebar-plugin/index.js`
- `node --check /Users/yelog/workspace/swift/VibeBar/plugins/claude-vibebar-plugin/scripts/emit.js`
- `swift test --filter HookContextTests`

Expected:
- 全部 PASS

**Step 5: Commit**

```bash
git add /Users/yelog/workspace/swift/VibeBar/plugins/opencode-vibebar-plugin/index.js \
  /Users/yelog/workspace/swift/VibeBar/plugins/claude-vibebar-plugin/scripts/emit.js \
  /Users/yelog/workspace/swift/VibeBar/Tests/VibeBarCoreTests/HookContextTests.swift
git commit -m "feat(plugin): forward wezterm metadata"
```

### Task 6: 端到端验证与文档更新

**Files:**
- Modify: `/Users/yelog/workspace/swift/VibeBar/README.md`
- Modify: `/Users/yelog/workspace/swift/VibeBar/CLAUDE.md`
- Modify: `/Users/yelog/workspace/swift/VibeBar/docs/plans/2026-04-04-terminal-support-matrix.md`

**Step 1: 更新文档**

- 在用户文档里加入 WezTerm 已支持说明
- 在支持矩阵中把 WezTerm 状态从 candidate 提升为 supported

**Step 2: 全量验证**

Run:
- `swift build`
- `swift test`

Expected:
- 全部 PASS

**Step 3: Commit**

```bash
git add /Users/yelog/workspace/swift/VibeBar/README.md \
  /Users/yelog/workspace/swift/VibeBar/CLAUDE.md \
  /Users/yelog/workspace/swift/VibeBar/docs/plans/2026-04-04-terminal-support-matrix.md
git commit -m "docs: document wezterm support"
```
