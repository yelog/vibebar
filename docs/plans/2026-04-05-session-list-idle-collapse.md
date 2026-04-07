# Session List Idle Collapse Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 为 VibeBar 的 session 下拉列表补齐显式的“按 `updatedAt` 倒序排序”和“idle 超过 30 分钟自动折叠为单行”规则。

**Architecture:** 保留现有 `updatedAt` 作为列表排序键，并在 `SessionSnapshot` 中新增 `idleSince` 作为独立的 idle 起点时间；再在 App 层抽出共享 presentation helper，统一 notch、原生菜单和备用 SwiftUI 菜单的排序、分组和折叠判断。

**Tech Stack:** Swift 6.2, Foundation, SwiftUI, AppKit, Swift Testing

---

### Task 1: Add `idleSince` to the session model and merge rules

**Files:**
- Modify: `Sources/VibeBarCore/Models.swift`
- Modify: `Sources/VibeBarApp/AppModel.swift`
- Test: `Tests/VibeBarAppTests/AppModelTests.swift`

**Step 1: Write the failing test**

在 `AppModelTests` 新增测试，覆盖：

- `SessionSnapshot` 支持可选 `idleSince`
- `mergeDetectedDetails` 在 detector 缺少 `idleSince` 时保留 file session 的值
- interaction hydrate / resolve 后清空 `idleSince`

**Step 2: Run test to verify it fails**

Run: `swift test --filter AppModelTests`
Expected: FAIL with missing `idleSince` property or outdated merge behavior.

**Step 3: Write minimal implementation**

- 在 `SessionSnapshot` 中新增 `idleSince: Date?`
- 更新 `AppModel.mergeDetectedDetails`
- 更新 `hydrate` 和 `applyResolvedInteractionLocally`，确保离开 idle 时清空 `idleSince`

**Step 4: Re-run focused test**

Run: `swift test --filter AppModelTests`
Expected: PASS

### Task 2: Capture `idleSince` in wrapper and agent event flows

**Files:**
- Modify: `Sources/VibeBarCLI/main.swift`
- Modify: `Sources/VibeBarAgent/main.swift`

**Step 1: Write minimal implementation**

- 在 wrapper 中检测状态从非 idle 切到 idle 的边界，写入 `idleSince`
- 在 wrapper 保持 idle 时保留 `idleSince`
- 在 wrapper 切回 `running` / `awaitingInput` 时清空 `idleSince`
- 在 agent 的 session update、pending interaction、clear interaction 路径同步上述规则

**Step 2: Run validation**

Run: `swift build`
Expected: PASS

### Task 3: Populate `idleSince` for transcript and session-file detectors

**Files:**
- Modify: `Sources/VibeBarCore/CodexSessionDetector.swift`
- Modify: `Sources/VibeBarCore/ClaudeTranscriptDetector.swift`
- Modify: `Sources/VibeBarCore/GeminiTranscriptDetector.swift`
- Modify: `Sources/VibeBarCore/OpenCodeHTTPDetector.swift`
- Test: `Tests/VibeBarCoreTests/CodexSessionDetectorTests.swift`
- Test: `Tests/VibeBarCoreTests/GeminiTranscriptDetectorTests.swift`

**Step 1: Write the failing test**

新增或扩展测试，断言：

- Codex idle session 的 `idleSince` 来自最近 rollout activity
- Gemini idle transcript session 的 `idleSince` 来自 `lastOutputAt ?? lastInputAt`

**Step 2: Run tests to verify they fail**

Run: `swift test --filter CodexSessionDetectorTests`
Expected: FAIL with missing `idleSince`.

Run: `swift test --filter GeminiTranscriptDetectorTests`
Expected: FAIL with missing `idleSince`.

**Step 3: Write minimal implementation**

- Codex detector 在 `status == .idle` 时写入 `idleSince`
- Claude / Gemini transcript detector 在 `status == .idle` 时写入 `idleSince`
- OpenCode HTTP detector 在 `status == .idle` 时使用 API 的更新时间作为 `idleSince`
- 对缺少可靠 idle 起点的 fallback 路径保持 `idleSince = nil`

**Step 4: Re-run focused tests**

Run: `swift test --filter CodexSessionDetectorTests`
Expected: PASS

Run: `swift test --filter GeminiTranscriptDetectorTests`
Expected: PASS

### Task 4: Build a shared session list presentation helper

**Files:**
- Create: `Sources/VibeBarApp/SessionListPresentation.swift`
- Test: `Tests/VibeBarAppTests/SessionListPresentationTests.swift`

**Step 1: Write the failing test**

新增测试覆盖：

- `sortSessions` 按 `updatedAt desc, pid asc`
- `groupedSessions` 在组内保持 `updatedAt desc, pid asc`
- `isCondensed` 只在 idle 且 `idleSince` 超过 30 分钟时返回 `true`

**Step 2: Run test to verify it fails**

Run: `swift test --filter SessionListPresentationTests`
Expected: FAIL with missing presentation helper.

**Step 3: Write minimal implementation**

- 新增 `SessionListPresentation`
- 提供统一的排序、分组和折叠判断 API
- 保持 group 顺序仍按 `ToolKind.allCases`

**Step 4: Re-run focused test**

Run: `swift test --filter SessionListPresentationTests`
Expected: PASS

### Task 5: Apply condensed rendering to notch and menu surfaces

**Files:**
- Modify: `Sources/VibeBarApp/NotchContentView.swift`
- Modify: `Sources/VibeBarApp/StatusItemController.swift`
- Modify: `Sources/VibeBarApp/MenuContentView.swift`
- Modify: `Sources/VibeBarApp/SessionDisplayFormatter.swift`

**Step 1: Write minimal implementation**

- notch session row 接入 `isCondensed`
- `SessionMenuItemView` 新增 `isCondensed` 参数，只渲染第一行时重新计算高度
- grouped session 输出统一改为通过 `SessionListPresentation`
- `MenuContentView` 同步相同行为，避免未来重新接线时分叉

**Step 2: Run validation**

Run: `swift build`
Expected: PASS

### Task 6: Run full validation

**Files:**
- Modify: none

**Step 1: Run targeted app tests**

Run: `swift test --filter AppModelTests`
Expected: PASS

Run: `swift test --filter SessionListPresentationTests`
Expected: PASS

**Step 2: Run core detector tests**

Run: `swift test --filter CodexSessionDetectorTests`
Expected: PASS

Run: `swift test --filter GeminiTranscriptDetectorTests`
Expected: PASS

**Step 3: Run full test suite**

Run: `swift test`
Expected: PASS

**Step 4: Run build**

Run: `swift build`
Expected: PASS

**Step 5: Manual verification**

- 非分组模式下，最新更新的 session 始终排在最上面
- 分组模式下，组内 session 仍按最新更新时间倒序
- `idleSince` 超过 30 分钟的 idle session 只显示第一行
- `awaitingInput` session 即使停留很久也不会折叠
