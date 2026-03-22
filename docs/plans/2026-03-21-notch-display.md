# Notch Display Mode Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 为 VibeBar 增加一个可选的刘海展示模式，在支持刘海的主屏上用刘海右侧延展图标区替代菜单栏图标，并在悬停时展开承接现有菜单的大部分内容。

**Architecture:** 先把“是否启用刘海模式”和“悬停展开/收起”的关键规则抽成可测试的纯策略对象，放进 `VibeBarCore` 锁定行为；再在 `VibeBarApp` 引入菜单栏宿主与刘海宿主的切换层，最后实现刘海右侧延展图标区、展开面板和共享内容适配。定位优先利用 `NSScreen.auxiliaryTopLeftArea / auxiliaryTopRightArea` 推导真实刘海边缘，避免继续把入口钉在屏幕中央。

**Tech Stack:** Swift 6.2, AppKit, SwiftUI, Combine, XCTest, Swift Package Manager

---

### Task 1: Add entry-host policy and settings plumbing

**Files:**
- Create: `Sources/VibeBarCore/EntryHostModeResolver.swift`
- Modify: `Sources/VibeBarCore/L10nStrings.swift`
- Modify: `Sources/VibeBarApp/AppSettings.swift`
- Modify: `Sources/VibeBarApp/SettingsView.swift`
- Test: `Tests/VibeBarCoreTests/EntryHostModeResolverTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import VibeBarCore

final class EntryHostModeResolverTests: XCTestCase {
    func testResolvesToNotchWhenPreferenceEnabledAndPrimaryDisplaySupportsNotch() {
        let mode = EntryHostModeResolver.resolve(
            preferenceEnabled: true,
            primaryDisplaySupportsNotch: true,
            temporarilyBlocked: false
        )

        XCTAssertEqual(mode, .notch)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter EntryHostModeResolverTests`
Expected: FAIL with `cannot find 'EntryHostModeResolver' in scope` or equivalent missing symbol error.

**Step 3: Write minimal implementation**

```swift
public enum EntryHostMode: Sendable {
    case menuBar
    case notch
}

public enum EntryHostModeResolver {
    public static func resolve(
        preferenceEnabled: Bool,
        primaryDisplaySupportsNotch: Bool,
        temporarilyBlocked: Bool
    ) -> EntryHostMode {
        guard preferenceEnabled, primaryDisplaySupportsNotch, !temporarilyBlocked else {
            return .menuBar
        }
        return .notch
    }
}
```

**Step 4: Expand tests for fallback cases**

Add cases covering:
- preference disabled -> `.menuBar`
- no-notch primary display -> `.menuBar`
- temporary block set -> `.menuBar`

**Step 5: Wire settings and localization**

- 在 `AppSettings` 增加 `@Published var notchDisplayEnabled: Bool`
- 注册默认值并持久化到 `UserDefaults`
- 在 `SettingsView` 的 `General > System` 新增开关与说明文案
- 在 `L10nStrings` 增加开关标题、说明、回退提示文案

**Step 6: Run tests and build**

Run: `swift test --filter EntryHostModeResolverTests`
Expected: PASS

Run: `swift build --target VibeBarApp`
Expected: Build succeeds with the new setting visible to the app target.

**Step 7: Commit**

```bash
git add Sources/VibeBarCore/EntryHostModeResolver.swift \
        Tests/VibeBarCoreTests/EntryHostModeResolverTests.swift \
        Sources/VibeBarCore/L10nStrings.swift \
        Sources/VibeBarApp/AppSettings.swift \
        Sources/VibeBarApp/SettingsView.swift
git commit -m "feat(settings): add notch display preference"
```

### Task 2: Add hover timing state machine

**Files:**
- Create: `Sources/VibeBarCore/NotchHoverStateMachine.swift`
- Test: `Tests/VibeBarCoreTests/NotchHoverStateMachineTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import VibeBarCore

final class NotchHoverStateMachineTests: XCTestCase {
    func testSchedulesExpandAfterEnteringHotZone() {
        let machine = NotchHoverStateMachine()
        let effect = machine.reduce(.pointerEnteredHotZone)
        XCTAssertEqual(effect, .scheduleExpand)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter NotchHoverStateMachineTests`
Expected: FAIL with missing type / missing member errors.

**Step 3: Write minimal implementation**

```swift
public struct NotchHoverStateMachine: Sendable {
    public enum Event: Sendable { case pointerEnteredHotZone, pointerExitedAllZones, expandTimerFired, collapseTimerFired }
    public enum State: Sendable { case collapsed, pendingExpand, expanded, pendingCollapse }
    public enum Effect: Sendable { case none, scheduleExpand, cancelExpand, scheduleCollapse, cancelCollapse, expandNow, collapseNow }

    private(set) var state: State = .collapsed

    public mutating func reduce(_ event: Event) -> Effect {
        // implement the minimal transition table first
    }
}
```

**Step 4: Extend tests to lock bridge-zone behavior**

Add tests for:
- leaving hot zone after expansion -> schedule collapse
- re-entering before collapse fires -> cancel collapse
- firing expand timer from `pendingExpand` -> `expandNow`
- stray timer events in unrelated states -> `.none`

**Step 5: Run tests**

Run: `swift test --filter NotchHoverStateMachineTests`
Expected: PASS

**Step 6: Commit**

```bash
git add Sources/VibeBarCore/NotchHoverStateMachine.swift \
        Tests/VibeBarCoreTests/NotchHoverStateMachineTests.swift
git commit -m "test(notch): add hover state machine coverage"
```

### Task 3: Introduce host switching between menu bar and notch entry

**Files:**
- Create: `Sources/VibeBarApp/NotchDisplayController.swift`
- Modify: `Sources/VibeBarApp/StatusItemController.swift`
- Modify: `Sources/VibeBarApp/AppDelegate.swift`
- Test: `Tests/VibeBarCoreTests/EntryHostModeResolverTests.swift`

**Step 1: Extend the resolver test with a realistic environment case**

```swift
func testPrefersMenuBarWhenTemporarilyBlockedEvenIfPreferenceEnabled() {
    let mode = EntryHostModeResolver.resolve(
        preferenceEnabled: true,
        primaryDisplaySupportsNotch: true,
        temporarilyBlocked: true
    )

    XCTAssertEqual(mode, .menuBar)
}
```

**Step 2: Run the focused test**

Run: `swift test --filter EntryHostModeResolverTests`
Expected: PASS before refactor.

**Step 3: Refactor the app entry flow**

- 让 `StatusItemController` 从“直接拥有 `NSStatusItem`”演进为“协调当前入口宿主”
- 保留现有菜单栏宿主逻辑
- 新增 `NotchDisplayController` 的生命周期管理
- 当 `AppSettings.notchDisplayEnabled`、主屏能力或屏幕拓扑变化时，重新解析并切换宿主

**Step 4: Implement minimal notch host activation**

```swift
final class NotchDisplayController {
    func show(summary: GlobalSummary) { /* create collapsed host if needed */ }
    func hide() { /* orderOut both windows */ }
    func update(summary: GlobalSummary, sessions: [SessionSnapshot]) { /* no-op for now */ }
}
```

**Step 5: Build and smoke-test the switch**

Run: `swift build --target VibeBarApp`
Expected: Build succeeds.

Run: `VIBEBAR_DEBUG_DOCK=1 swift run VibeBarApp`
Expected: Toggling the new setting swaps between menu bar mode and placeholder notch host without crashing.

**Step 6: Commit**

```bash
git add Sources/VibeBarApp/NotchDisplayController.swift \
        Sources/VibeBarApp/StatusItemController.swift \
        Sources/VibeBarApp/AppDelegate.swift \
        Tests/VibeBarCoreTests/EntryHostModeResolverTests.swift
git commit -m "feat(app): switch primary entry host for notch mode"
```

### Task 4: Implement the notch right extension and hover hot zone

**Files:**
- Modify: `Sources/VibeBarApp/NotchDisplayController.swift`
- Create: `Sources/VibeBarApp/NotchCollapsedView.swift`
- Modify: `Sources/VibeBarApp/StatusItemController.swift`
- Test: `Tests/VibeBarCoreTests/NotchHoverStateMachineTests.swift`

**Step 1: Add a failing state-machine test for re-entry cancellation**

```swift
func testReEnteringBeforeCollapseTimerCancelsPendingCollapse() {
    var machine = NotchHoverStateMachine()
    _ = machine.reduce(.pointerEnteredHotZone)
    _ = machine.reduce(.expandTimerFired)
    _ = machine.reduce(.pointerExitedAllZones)

    let effect = machine.reduce(.pointerEnteredHotZone)
    XCTAssertEqual(effect, .cancelCollapse)
}
```

**Step 2: Run the hover tests**

Run: `swift test --filter NotchHoverStateMachineTests`
Expected: FAIL until the transition table covers re-entry.

**Step 3: Finish the state-machine transitions**

- 补全 `pendingCollapse -> expanded` 的回退路径
- 锁定 `120-180ms` / `220-280ms` 对应的默认延迟常量
- 让 `NotchDisplayController` 通过 machine 驱动 `DispatchWorkItem` 或 `Task.sleep`

**Step 4: Build the collapsed UI**

- 创建 `NotchCollapsedView`
- 视觉实现为贴着刘海右边缘的黑色延展图标区，内部只保留菜单栏同款图标
- 热区覆盖刘海本体与右侧延展区
- 几何优先由 `auxiliaryTopRightArea` 推导，不再固定在顶部中央

**Step 5: Build and manual-check**

Run: `swift test --filter NotchHoverStateMachineTests`
Expected: PASS

Run: `swift build --target VibeBarApp`
Expected: Build succeeds.

Manual check:
- 延展图标区能随 summary 更新菜单栏同款图标
- 移入刘海或右侧延展区后不会立即闪开或抖动

**Step 6: Commit**

```bash
git add Sources/VibeBarApp/NotchDisplayController.swift \
        Sources/VibeBarApp/NotchCollapsedView.swift \
        Sources/VibeBarApp/StatusItemController.swift \
        Sources/VibeBarCore/NotchHoverStateMachine.swift \
        Tests/VibeBarCoreTests/NotchHoverStateMachineTests.swift
git commit -m "feat(notch): add right-side notch extension"
```

### Task 5: Build the expanded notch panel and shared content adapter

**Files:**
- Create: `Sources/VibeBarApp/NotchContentView.swift`
- Modify: `Sources/VibeBarApp/NotchDisplayController.swift`
- Modify: `Sources/VibeBarApp/StatusItemController.swift`
- Modify: `Sources/VibeBarApp/MenuContentView.swift`

**Step 1: Add a minimal adapter before touching UI**

```swift
struct NotchPanelSnapshot: Sendable {
    let totalSessions: Int
    let updatedAt: Date
    let groupedSessions: [GroupedSessionSnapshot]
}
```

**Step 2: Wire the adapter in `StatusItemController`**

- 从现有 `summary` / `sessions` / `usage` 生成刘海面板需要的数据
- 让 adapter 复用现有分组逻辑，而不是在新 view 中重复拼装业务数据

**Step 3: Implement the expanded panel**

- `NSPanel` 承载 `NotchContentView`
- 展开时保留一个与面板同宽的顶部 bridge cap，从刘海区域向两侧铺开并与内容区连成整体
- 顶部摘要区 + session 列表 + usage 摘要 + 底部操作
- 样式从菜单项升级为顶部信息面板，不直接复用蓝色菜单高亮

**Step 4: Add expand / collapse animation**

- 预热态：轻微放大与提亮
- 形变态：从刘海中线起步，先自上向下拉开，再从中间向左右展开
- 内容淡入：摘要、列表、底部操作分层出现
- 收起顺序与展开相反

**Step 5: Manual verification**

Run: `VIBEBAR_DEBUG_DOCK=1 swift run VibeBarApp`
Expected:
- 鼠标从刘海或右侧延展区移动到面板主体过程中不误收起
- 展开后顶部刘海区域与右侧延展区仍保留桥接占位，不会因为收起态层消失而过早触发收起
- 展开后顶部黑色区域向左右延展到与面板齐平，看起来像从刘海区长出来的一整块
- 面板承接现有菜单的主要信息
- 设置、刷新、退出等底部操作可用

**Step 6: Commit**

```bash
git add Sources/VibeBarApp/NotchContentView.swift \
        Sources/VibeBarApp/NotchDisplayController.swift \
        Sources/VibeBarApp/StatusItemController.swift \
        Sources/VibeBarApp/MenuContentView.swift
git commit -m "feat(notch): add expanded notch panel"
```

### Task 6: Finalize fallback behavior, docs, and regression checks

**Files:**
- Modify: `Sources/VibeBarApp/NotchDisplayController.swift`
- Modify: `Sources/VibeBarApp/StatusItemController.swift`
- Modify: `README.md`
- Modify: `README_zh.md`
- Modify: `README_ja.md`
- Modify: `README_ko.md`

**Step 1: Harden screen-topology fallback**

- 监听主屏变化、显示器连接变化、应用激活状态变化
- 主屏不支持刘海时立即切回菜单栏模式
- 切换时确保不会短暂出现双入口

**Step 2: Document the feature**

- 在 README 多语言文档补充“刘海展示模式”说明
- 明确说明无刘海屏会自动回退为普通菜单栏模式

**Step 3: Run full verification**

Run: `swift test`
Expected: PASS

Run: `swift build`
Expected: Build succeeds for the full package.

**Step 4: Perform manual regression checks**

- 普通菜单栏模式仍可正常显示与展开菜单
- 开启刘海模式后不会影响 usage 刷新、通知和设置窗口
- 无刘海屏 / 外接屏切换时入口不丢失

**Step 5: Commit**

```bash
git add Sources/VibeBarApp/NotchDisplayController.swift \
        Sources/VibeBarApp/StatusItemController.swift \
        README.md README_zh.md README_ja.md README_ko.md
git commit -m "docs(notch): describe notch display mode"
```
