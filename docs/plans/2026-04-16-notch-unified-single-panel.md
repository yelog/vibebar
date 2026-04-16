# Notch Unified Single Panel Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 把刘海入口重构为真正的单一 `NSPanel`，让展开起点和收起终点都回到未展开窗口，并消除收起过程中左右图标先消失再出现的问题。

**Architecture:** 用一个统一的 `notchPanel` 取代当前 `collapsedPanel` / `expandedPanel` 双窗口结构。`NotchDisplayController` 只负责驱动一个窗口在收起 frame 与展开 frame 间过渡，新的 `NotchPanelRootView` 统一承载顶部壳体和正文内容，并通过展示相位控制正文裁剪、透明度和命中行为。

**Tech Stack:** Swift 6.2, AppKit, SwiftUI, Swift Package Manager

---

### Task 1: 提取可测试的单面板展示相位与布局辅助

**Files:**
- Create: `Sources/VibeBarApp/NotchPanelLayoutModel.swift`
- Create: `Tests/VibeBarAppTests/NotchPanelLayoutModelTests.swift`

**Step 1: Write the failing test**

```swift
@testable import VibeBarApp
import XCTest

final class NotchPanelLayoutModelTests: XCTestCase {
    func testCollapsingKeepsTopShellVisibleAndDisablesBodyHitTesting() {
        let model = NotchPanelLayoutModel(phase: .collapsing)

        XCTAssertTrue(model.showsTopShell)
        XCTAssertFalse(model.allowsBodyHitTesting)
    }

    func testCollapsedTargetFrameUsesCollapsedWindowFrame() {
        let collapsedFrame = NSRect(x: 100, y: 10, width: 268, height: 42)
        let expandedFrame = NSRect(x: 40, y: -180, width: 440, height: 240)
        let model = NotchPanelLayoutModel(
            phase: .collapsed,
            collapsedFrame: collapsedFrame,
            expandedFrame: expandedFrame
        )

        XCTAssertEqual(model.targetFrame, collapsedFrame)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter NotchPanelLayoutModelTests`
Expected: FAIL with missing `NotchPanelLayoutModel` / `.collapsing`

**Step 3: Write minimal implementation**

```swift
import AppKit

enum NotchPanelPhase: Sendable {
    case collapsed
    case expanding
    case expanded
    case collapsing
}

struct NotchPanelLayoutModel: Sendable {
    var phase: NotchPanelPhase
    var collapsedFrame: NSRect = .zero
    var expandedFrame: NSRect = .zero

    var targetFrame: NSRect {
        switch phase {
        case .collapsed, .collapsing:
            return collapsedFrame
        case .expanded, .expanding:
            return expandedFrame
        }
    }

    var showsTopShell: Bool { true }

    var allowsBodyHitTesting: Bool {
        phase == .expanded || phase == .expanding
    }
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter NotchPanelLayoutModelTests`
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/VibeBarApp/NotchPanelLayoutModel.swift Tests/VibeBarAppTests/NotchPanelLayoutModelTests.swift
git commit -m "test(notch): cover unified panel layout state"
```

### Task 2: 建立统一根视图并拆出正文内容

**Files:**
- Create: `Sources/VibeBarApp/NotchPanelRootView.swift`
- Create: `Sources/VibeBarApp/NotchExpandedBodyView.swift`
- Modify: `Sources/VibeBarApp/NotchCollapsedView.swift`
- Modify: `Sources/VibeBarApp/NotchContentView.swift`

**Step 1: Write the failing test**

```swift
@testable import VibeBarApp
import XCTest

final class NotchPanelLayoutModelBodyTests: XCTestCase {
    func testCollapsedPhaseHidesExpandedBody() {
        let model = NotchPanelLayoutModel(phase: .collapsed)
        XCTAssertFalse(model.showsExpandedBody)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter NotchPanelLayoutModelBodyTests`
Expected: FAIL with missing `showsExpandedBody`

**Step 3: Write minimal implementation**

```swift
extension NotchPanelLayoutModel {
    var showsExpandedBody: Bool {
        phase != .collapsed
    }
}
```

然后新增 `NotchPanelRootView`：

```swift
struct NotchPanelRootView: View {
    let layoutModel: NotchPanelLayoutModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            panelBackground
            topShell
            if layoutModel.showsExpandedBody {
                expandedBody
                    .allowsHitTesting(layoutModel.allowsBodyHitTesting)
            }
        }
    }
}
```

并把 `NotchContentView` 的正文区提取到 `NotchExpandedBodyView`，让 `NotchCollapsedView` 仅保留顶部壳体绘制与图标定位。

**Step 4: Run build to verify it passes**

Run: `swift build --target VibeBarApp`
Expected: BUILD SUCCEEDED

**Step 5: Commit**

```bash
git add Sources/VibeBarApp/NotchPanelRootView.swift Sources/VibeBarApp/NotchExpandedBodyView.swift Sources/VibeBarApp/NotchCollapsedView.swift Sources/VibeBarApp/NotchContentView.swift Sources/VibeBarApp/NotchPanelLayoutModel.swift Tests/VibeBarAppTests/NotchPanelLayoutModelTests.swift
git commit -m "refactor(notch): unify shell and body into one root view"
```

### Task 3: 把 NotchDisplayController 改为单一 panel 宿主

**Files:**
- Modify: `Sources/VibeBarApp/NotchDisplayController.swift`

**Step 1: Write the failing test**

在 `Tests/VibeBarAppTests/NotchPanelLayoutModelTests.swift` 增加收起目标 frame 断言，明确 `collapsing` 必须回到收起态窗口而不是物理刘海：

```swift
func testCollapsingReturnsToCollapsedFrameInsteadOfPhysicalNotchFrame() {
    let collapsedFrame = NSRect(x: 100, y: 10, width: 268, height: 42)
    let expandedFrame = NSRect(x: 40, y: -180, width: 440, height: 240)
    let model = NotchPanelLayoutModel(
        phase: .collapsing,
        collapsedFrame: collapsedFrame,
        expandedFrame: expandedFrame
    )

    XCTAssertEqual(model.targetFrame, collapsedFrame)
}
```

**Step 2: Run test to verify it passes before wiring**

Run: `swift test --filter NotchPanelLayoutModelTests/testCollapsingReturnsToCollapsedFrameInsteadOfPhysicalNotchFrame`
Expected: PASS

**Step 3: Write minimal implementation**

在 `NotchDisplayController` 中做以下收敛：

```swift
private let notchPanel: NSPanel
private let notchContainerView: NotchTrackingContainerView
private let notchHostingView: NSHostingView<NotchPanelRootView>
private var panelPhase: NotchPanelPhase = .collapsed
```

并删除：

```swift
private let collapsedPanel: NSPanel
private let expandedPanel: NSPanel
```

展开时：

```swift
panelPhase = .expanding
notchPanel.setFrame(collapsedFrame, display: true)
notchPanel.orderFrontRegardless()
notchPanel.animator().setFrame(expandedFrame, display: true)
```

收起时：

```swift
panelPhase = .collapsing
notchPanel.animator().setFrame(collapsedFrame, display: true)
```

动画完成后分别落到 `.expanded` 或 `.collapsed`，不再做 `orderOut/orderFront` 的窗口切换。

**Step 4: Run build to verify it passes**

Run: `swift build --target VibeBarApp`
Expected: BUILD SUCCEEDED

**Step 5: Commit**

```bash
git add Sources/VibeBarApp/NotchDisplayController.swift Sources/VibeBarApp/NotchPanelRootView.swift Sources/VibeBarApp/NotchExpandedBodyView.swift Sources/VibeBarApp/NotchCollapsedView.swift Sources/VibeBarApp/NotchContentView.swift Sources/VibeBarApp/NotchPanelLayoutModel.swift Tests/VibeBarAppTests/NotchPanelLayoutModelTests.swift
git commit -m "refactor(notch): use a single panel for notch transitions"
```

### Task 4: 收敛刷新、命中区与动画中交互

**Files:**
- Modify: `Sources/VibeBarApp/NotchDisplayController.swift`
- Modify: `Sources/VibeBarApp/NotchPanelRootView.swift`

**Step 1: Write the failing test**

在 `Tests/VibeBarAppTests/NotchPanelLayoutModelTests.swift` 增加命中和正文命中相关断言：

```swift
func testCollapsingDisablesBodyHitTesting() {
    let model = NotchPanelLayoutModel(phase: .collapsing)
    XCTAssertFalse(model.allowsBodyHitTesting)
}
```

**Step 2: Run test to verify it passes before wiring**

Run: `swift test --filter NotchPanelLayoutModelTests/testCollapsingDisablesBodyHitTesting`
Expected: PASS

**Step 3: Write minimal implementation**

- 让 `isPointerInsideVisiblePanel()` 只判断 `notchPanel.frame` 及其外扩区域。
- 在 `refreshContent()` 中只更新一次 `NotchPanelRootView`。
- 在 `collapsing` 阶段禁用正文 hit testing，并保留顶部壳体可见。
- 删掉 `expandedTopCoverPresentation()` 与双 panel 专用 bridge 切换路径。

**Step 4: Run build and focused tests**

Run: `swift test --filter NotchPanelLayoutModelTests && swift build --target VibeBarApp`
Expected: all selected tests PASS and BUILD SUCCEEDED

**Step 5: Commit**

```bash
git add Sources/VibeBarApp/NotchDisplayController.swift Sources/VibeBarApp/NotchPanelRootView.swift Sources/VibeBarApp/NotchPanelLayoutModel.swift Tests/VibeBarAppTests/NotchPanelLayoutModelTests.swift
git commit -m "fix(notch): keep collapsed shell stable during collapse"
```

### Task 5: 手动回归验证

**Files:**
- None

**Step 1: Run app build**

Run: `swift build --target VibeBarApp`
Expected: BUILD SUCCEEDED

**Step 2: Verify expand path manually**

Run: `VIBEBAR_DEBUG_DOCK=1 swift run VibeBarApp`
Expected: hover 进入刘海后，从未展开窗口直接展开到完整面板，没有第二个窗口抢前景

**Step 3: Verify collapse path manually**

Run: `VIBEBAR_DEBUG_DOCK=1 swift run VibeBarApp`
Expected: 收起全过程左右图标持续可见，最终回到未展开窗口，而不是先缩进刘海中央再补一个收起态块

**Step 4: Verify hover stability manually**

Run: `VIBEBAR_DEBUG_DOCK=1 swift run VibeBarApp`
Expected: 鼠标从顶部壳体移向正文，再离开窗口时，不出现闪烁、误收起或热区断裂

**Step 5: Commit**

```bash
git add .
git commit -m "test(notch): verify unified single-panel notch behavior"
```
