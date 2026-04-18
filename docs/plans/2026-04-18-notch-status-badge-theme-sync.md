# Notch Status Badge Theme Sync Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 让刘海下拉框 Session 列表右侧的状态 badge 跟随“设置 -> 外观”的状态主题色，同时保留 notch 其他 badge 和整体视觉不变。

**Architecture:** 改动集中在 `SessionBadgeStyle` 的颜色解析逻辑。继续保留 `.standard / .notch` 双外观分支，只对 `.notch + tone == .status + accentState != nil` 的 badge 改用 `AppSettings.shared.nsColor(for:)` 作为基础状态色。测试层补一个针对 notch status badge 的断言，确保主题色管线接通且不影响现有非状态 badge。

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, Swift Testing

---

### Task 1: 补 notch status badge 跟主题色的测试

**Files:**
- Modify: `Tests/VibeBarAppTests/SessionBadgeStyleTests.swift`

**Step 1: 写一个失败测试，覆盖 notch status badge 的颜色来源**

在 `SessionBadgeStyleTests.swift` 增加：

```swift
@MainActor
@Test func notchStatusBadgeUsesAppearanceThemeColor() {
    let badge = SessionBadge(
        kind: .duration,
        text: "空闲 3m",
        tone: .status,
        accentState: .idle
    )

    let colors = SessionBadgeStyle.resolvedColors(
        for: badge,
        appearance: .notch
    )

    let expected = AppSettings.shared.nsColor(for: .idle)

    #expect(colors.textColor.isApproximatelyEqual(to: expected))
}
```

**Step 2: 运行单测确认当前失败**

Run: `swift test --filter notchStatusBadgeUsesAppearanceThemeColor`

Expected: FAIL，因为当前 `.notch` 仍返回 `NotchPanelStyle.nsColor(for:)`。

### Task 2: 最小修改颜色解析逻辑

**Files:**
- Modify: `Sources/VibeBarApp/SessionBadgeView.swift:113-155`

**Step 1: 在状态 badge 分支里加入 notch status 特判**

把现有：

```swift
if let state = badge.accentState {
    let baseColor = accentBaseColor ?? accentColor(for: state, appearance: appearance)
    ...
}
```

改成保留现有结构、仅调整基础色来源，例如：

```swift
if let state = badge.accentState {
    let resolvedBaseColor: NSColor
    if let accentBaseColor {
        resolvedBaseColor = accentBaseColor
    } else if appearance == .notch && badge.tone == .status {
        resolvedBaseColor = AppSettings.shared.nsColor(for: state)
    } else {
        resolvedBaseColor = accentColor(for: state, appearance: appearance)
    }

    return ResolvedColors(
        fillColor: resolvedBaseColor.withAlphaComponent(0.16),
        borderColor: resolvedBaseColor.withAlphaComponent(0.32),
        textColor: resolvedBaseColor
    )
}
```

**Step 2: 不改非状态 badge 的 notch 颜色分支**

确认 `client / manager / origin / neutral` 仍走现有 notch palette，不新增通用主题色扩散。

### Task 3: 验证并收尾

**Files:**
- Verify: `Sources/VibeBarApp/NotchExpandedBodyView.swift`
- Verify: `Tests/VibeBarAppTests/SessionBadgeStyleTests.swift`

**Step 1: 运行单测确认新增断言通过**

Run: `swift test --filter notchStatusBadgeUsesAppearanceThemeColor`

Expected: PASS。

**Step 2: 运行现有 badge 测试，确认未回归**

Run: `swift test --filter SessionBadgeStyleTests`

Expected: PASS，包括现有 `semanticToneBadgesKeepExistingPalette`。

**Step 3: 运行 App target 构建**

Run: `swift build --target VibeBarApp`

Expected: PASS。

**Step 4: 人工检查 notch badge 跟随主题色**

Run: `VIBEBAR_DEBUG_DOCK=1 swift run VibeBarApp`

Expected:
- 切换“设置 -> 外观 -> 主题”后，notch Session 状态 badge 随之变色。
- 顶部状态环不变。
- 非状态 badge 不变。

**Step 5: 如用户要求，再创建提交**

仅在用户明确要求提交时执行：

```bash
git add Sources/VibeBarApp/SessionBadgeView.swift Tests/VibeBarAppTests/SessionBadgeStyleTests.swift docs/plans/2026-04-18-notch-status-badge-theme-sync-design.md docs/plans/2026-04-18-notch-status-badge-theme-sync.md
git commit -m "fix(notch): sync session status badge with theme colors"
```
