# Tooltip Token Format Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 让 Token Usage 的 hover tooltip 使用 `K / M / B` 紧凑单位展示 token 数字。

**Architecture:** 在 `VibeBarCore` 提供单一 token formatter，菜单 tooltip 与热力图 hover 共同复用，避免同类格式化逻辑分散在多个 SwiftUI 视图里。测试放在 core target，直接锁定显示规则和边界行为。

**Tech Stack:** Swift 6.2, SwiftUI, Swift Testing

---

### Task 1: Add Shared Token Formatter

**Files:**
- Create: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/UsageTokenFormatter.swift`
- Test: `/Users/yelog/workspace/swift/VibeBar/Tests/VibeBarCoreTests/UsageTokenFormatterTests.swift`

**Step 1: Write the failing test**

```swift
@Test func tokenFormatterUsesCompactUnits() {
    #expect(UsageTokenFormatter.tooltipTokenText(296_125_188) == "296.1M tokens")
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter tokenFormatterUsesCompactUnits`
Expected: FAIL with missing formatter symbol.

**Step 3: Write minimal implementation**

```swift
enum UsageTokenFormatter {
    static func tooltipTokenText(_ tokens: Int) -> String { ... }
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter UsageTokenFormatterTests`
Expected: PASS.

**Step 5: Commit**

```bash
git add Sources/VibeBarCore/UsageTokenFormatter.swift Tests/VibeBarCoreTests/UsageTokenFormatterTests.swift
git commit -m "feat(usage): compact tooltip token values"
```

### Task 2: Wire Formatter Into Tooltip Views

**Files:**
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/UsageMenuSectionView.swift`
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/UsageHeatmapView.swift`

**Step 1: Replace raw token strings in tooltips**

```swift
return UsageTokenFormatter.tooltipTokenText(tokens)
```

**Step 2: Build the app**

Run: `swift build`
Expected: PASS.

**Step 3: Verify tooltip output**

Run: `swift test --filter UsageTokenFormatterTests`
Expected: PASS and tooltip-related views compile cleanly.

**Step 4: Commit**

```bash
git add Sources/VibeBarApp/UsageMenuSectionView.swift Sources/VibeBarApp/UsageHeatmapView.swift
git commit -m "feat(app): use compact token values in usage tooltips"
```
