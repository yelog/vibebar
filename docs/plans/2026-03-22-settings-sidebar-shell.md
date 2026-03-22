# Settings Sidebar Shell Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 将设置窗口重构为 sidebar 导航和统一内容壳层，消除横向溢出问题，并为未来新增页面保留稳定扩展结构。

**Architecture:** 先引入可测试的设置页注册与展示模式模型，再替换根视图为 sidebar shell，随后把窗口策略从“按页面写死尺寸”改成“统一可调窗口”，最后逐页收敛滚动与响应式布局，优先处理 `Usage` 和 `CLI` 这两个复杂页面。

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, Swift Package Manager, XCTest

---

### Task 1: Introduce settings shell models and app test target

**Files:**
- Modify: `Package.swift`
- Create: `Sources/VibeBarApp/SettingsShellModels.swift`
- Create: `Tests/VibeBarAppTests/SettingsShellModelsTests.swift`

**Step 1: Write the failing tests**

在 `Tests/VibeBarAppTests/SettingsShellModelsTests.swift` 新增测试，锁定页面注册和展示模式：

```swift
import XCTest
@testable import VibeBarApp

final class SettingsShellModelsTests: XCTestCase {
    func testSidebarPageOrderMatchesProductDecision() {
        XCTAssertEqual(
            SettingsPage.allCases,
            [.general, .cli, .appearance, .usage, .hooks, .about]
        )
    }

    func testCLIPresentationIsFullBleed() {
        XCTAssertEqual(SettingsPage.cli.presentation, .fullBleed)
    }

    func testGeneralPresentationIsStandardScrollable() {
        XCTAssertEqual(SettingsPage.general.presentation, .standardScrollable)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter SettingsShellModelsTests`
Expected: FAIL with missing `VibeBarAppTests` target or missing `SettingsPage` / `presentation`.

**Step 3: Write minimal implementation**

- 在 `Package.swift` 新增 `VibeBarAppTests` test target，依赖 `VibeBarApp`。
- 在 `Sources/VibeBarApp/SettingsShellModels.swift` 定义：

```swift
enum SettingsPage: Int, CaseIterable {
    case general
    case cli
    case appearance
    case usage
    case hooks
    case about
}

enum SettingsPagePresentation {
    case standardScrollable
    case fullBleed
}

extension SettingsPage {
    var presentation: SettingsPagePresentation {
        switch self {
        case .cli:
            return .fullBleed
        default:
            return .standardScrollable
        }
    }
}
```

**Step 4: Run tests and build**

Run: `swift test --filter SettingsShellModelsTests`
Expected: PASS

Run: `swift build --target VibeBarApp`
Expected: Build succeeds with the new settings shell model module.

**Step 5: Commit**

```bash
git add Package.swift Sources/VibeBarApp/SettingsShellModels.swift Tests/VibeBarAppTests/SettingsShellModelsTests.swift
git commit -m "test(settings): add shell model coverage"
```

### Task 2: Replace top tab bar with sidebar shell

**Files:**
- Create: `Sources/VibeBarApp/SettingsShellView.swift`
- Modify: `Sources/VibeBarApp/SettingsView.swift`

**Step 1: Write the failing test**

扩展 `Tests/VibeBarAppTests/SettingsShellModelsTests.swift`，锁定 sidebar descriptor 的标题和快捷键：

```swift
func testSidebarDescriptorsExposeStableShortcuts() {
    let shortcuts = SettingsPage.allCases.map(\.shortcutKey)
    XCTAssertEqual(shortcuts, ["1", "2", "3", "4", "5", "6"])
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter testSidebarDescriptorsExposeStableShortcuts`
Expected: FAIL with missing `shortcutKey`.

**Step 3: Write minimal implementation**

- 在 `SettingsShellModels.swift` 为 `SettingsPage` 增加：
  - `title(l10n:)`
  - `iconName`
  - `shortcutKey`
- 新建 `SettingsShellView.swift`，实现：
  - 左侧 sidebar 列表
  - 右侧 detail 容器
  - `@ObservedObject var viewState`
  - 选中页绑定
- 修改 `SettingsView.swift`：
  - 删除顶部 `HStack` tab bar
  - 用 `SettingsShellView` 承载页面切换
  - 保留原有页面内容构造逻辑

**Step 4: Run tests and build**

Run: `swift test --filter SettingsShellModelsTests`
Expected: PASS

Run: `swift build --target VibeBarApp`
Expected: Build succeeds and settings window still opens.

**Step 5: Commit**

```bash
git add Sources/VibeBarApp/SettingsShellModels.swift Sources/VibeBarApp/SettingsShellView.swift Sources/VibeBarApp/SettingsView.swift Tests/VibeBarAppTests/SettingsShellModelsTests.swift
git commit -m "refactor(settings): replace top tabs with sidebar shell"
```

### Task 3: Replace per-tab window sizing with unified window policy

**Files:**
- Modify: `Sources/VibeBarApp/SettingsWindowController.swift`
- Modify: `Sources/VibeBarApp/SettingsView.swift`
- Modify: `Tests/VibeBarAppTests/SettingsShellModelsTests.swift`

**Step 1: Write the failing test**

在 `Tests/VibeBarAppTests/SettingsShellModelsTests.swift` 中新增统一窗口策略测试：

```swift
func testSettingsWindowUsesSingleResizablePolicy() {
    let policy = SettingsWindowPolicy.default
    XCTAssertEqual(policy.defaultContentSize.width, 780)
    XCTAssertEqual(policy.minContentSize.width, 720)
    XCTAssertFalse(policy.resizesPerPage)
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter testSettingsWindowUsesSingleResizablePolicy`
Expected: FAIL with missing `SettingsWindowPolicy`.

**Step 3: Write minimal implementation**

- 在 `SettingsShellModels.swift` 或单独文件中增加：

```swift
struct SettingsWindowPolicy {
    let defaultContentSize: CGSize
    let minContentSize: CGSize
    let maxContentSize: CGSize
    let resizesPerPage: Bool

    static let `default` = SettingsWindowPolicy(
        defaultContentSize: CGSize(width: 780, height: 700),
        minContentSize: CGSize(width: 720, height: 620),
        maxContentSize: CGSize(width: 1100, height: 900),
        resizesPerPage: false
    )
}
```

- 修改 `SettingsWindowController.swift`：
  - 删除 `contentWidth(for:)` / `contentHeight(for:)` 驱动的窗口尺寸切换
  - 统一应用 `SettingsWindowPolicy.default`
  - 去掉切换页面时对窗口 frame 的动画调整
- 修改 `SettingsView.swift`，删除 `resizeWindow(for:animated:)` 相关逻辑。

**Step 4: Run tests and build**

Run: `swift test --filter SettingsShellModelsTests`
Expected: PASS

Run: `swift build --target VibeBarApp`
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/VibeBarApp/SettingsShellModels.swift Sources/VibeBarApp/SettingsView.swift Sources/VibeBarApp/SettingsWindowController.swift Tests/VibeBarAppTests/SettingsShellModelsTests.swift
git commit -m "refactor(settings): use single resizable window policy"
```

### Task 4: Move standard pages onto shell-managed scrolling

**Files:**
- Modify: `Sources/VibeBarApp/SettingsView.swift`
- Modify: `Sources/VibeBarApp/UsageSettingsView.swift`
- Modify: `Sources/VibeBarApp/HooksSettingsView.swift`

**Step 1: Write the failing build expectation**

先让页面 API 显式区分“页面内容”和“外层滚动容器”：

- `GeneralSettingsView`
- `AppearanceSettingsView`
- `AboutSettingsView`
- `UsageSettingsView`
- `HooksSettingsView`

这些页面都不应再拥有根级 `ScrollView`。

**Step 2: Run build to confirm current state**

Run: `swift build --target VibeBarApp`
Expected: PASS, but current runtime still contains duplicated scroll ownership.

**Step 3: Write minimal implementation**

- 在 `SettingsShellView` 的 standard detail 容器中统一提供：
  - `ScrollView(showsIndicators: true)`
  - 内容 `padding`
  - 标准顶部/底部留白
- 修改 `SettingsView.swift`：
  - `general` / `appearance` / `usage` / `hooks` / `about` 全部改为输出纯内容
- 修改 `UsageSettingsView.swift`：
  - 删除根级 `ScrollView`
  - 保留 preview tooltip / overlay 行为
- 修改 `HooksSettingsView.swift`：
  - 让页面根层适配 shell detail；仅对 hooks 列表区域保留内部滚动

**Step 4: Run build and smoke test**

Run: `swift build --target VibeBarApp`
Expected: PASS

Run: `VIBEBAR_DEBUG_DOCK=1 swift run VibeBarApp`
Expected: Standard pages share one consistent scroll behavior and no longer clip horizontally.

**Step 5: Commit**

```bash
git add Sources/VibeBarApp/SettingsView.swift Sources/VibeBarApp/UsageSettingsView.swift Sources/VibeBarApp/HooksSettingsView.swift
git commit -m "refactor(settings): unify standard page scrolling"
```

### Task 5: Make Usage and Appearance layouts responsive

**Files:**
- Create: `Sources/VibeBarApp/SettingsResponsiveLayout.swift`
- Modify: `Sources/VibeBarApp/UsageSettingsView.swift`
- Modify: `Sources/VibeBarApp/SettingsView.swift`
- Create: `Tests/VibeBarAppTests/SettingsResponsiveLayoutTests.swift`

**Step 1: Write the failing tests**

在 `Tests/VibeBarAppTests/SettingsResponsiveLayoutTests.swift` 中增加基于可用宽度的列数测试：

```swift
import XCTest
@testable import VibeBarApp

final class SettingsResponsiveLayoutTests: XCTestCase {
    func testUsageSourceGridShrinksWhenWidthIsNarrow() {
        XCTAssertEqual(
            SettingsResponsiveLayout.columnCount(
                availableWidth: 420,
                minimumItemWidth: 140,
                spacing: 10
            ),
            2
        )
    }

    func testUsageSourceGridExpandsWithinReasonableUpperBound() {
        XCTAssertEqual(
            SettingsResponsiveLayout.columnCount(
                availableWidth: 760,
                minimumItemWidth: 140,
                spacing: 10
            ),
            4
        )
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter SettingsResponsiveLayoutTests`
Expected: FAIL with missing `SettingsResponsiveLayout`.

**Step 3: Write minimal implementation**

- 新建 `SettingsResponsiveLayout.swift`，实现纯函数：

```swift
enum SettingsResponsiveLayout {
    static func columnCount(
        availableWidth: CGFloat,
        minimumItemWidth: CGFloat,
        spacing: CGFloat,
        maxColumns: Int = 4
    ) -> Int {
        // return clamped adaptive count
    }
}
```

- 修改 `UsageSettingsView.swift`：
  - `sourceGridColumns`
  - `styleGridColumns`
  - `controlGridColumns`
  改为依赖可用宽度动态计算
- 修改 `SettingsView.swift` 中 `AppearanceSettingsView` 的图标网格，使其在窄宽度下可以退化为 3 列或 2 列。

**Step 4: Run tests and build**

Run: `swift test --filter SettingsResponsiveLayoutTests`
Expected: PASS

Run: `swift build --target VibeBarApp`
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/VibeBarApp/SettingsResponsiveLayout.swift Sources/VibeBarApp/UsageSettingsView.swift Sources/VibeBarApp/SettingsView.swift Tests/VibeBarAppTests/SettingsResponsiveLayoutTests.swift
git commit -m "refactor(settings): make settings grids adaptive"
```

### Task 6: Stabilize CLI as a full-bleed settings page

**Files:**
- Modify: `Sources/VibeBarApp/CLISettingsView.swift`
- Modify: `Sources/VibeBarApp/SettingsShellView.swift`
- Modify: `Tests/VibeBarAppTests/SettingsShellModelsTests.swift`

**Step 1: Write the failing test**

扩展 `SettingsShellModelsTests.swift`，锁定 `CLI` 页面必须通过 full-bleed detail 承载：

```swift
func testCLIUsesFullBleedPresentation() {
    XCTAssertEqual(SettingsPage.cli.presentation, .fullBleed)
}
```

**Step 2: Run test to verify it fails if not already covered**

Run: `swift test --filter testCLIUsesFullBleedPresentation`
Expected: PASS after Task 1, keep as regression guard.

**Step 3: Write minimal implementation**

- 修改 `SettingsShellView.swift`：
  - 对 `.fullBleed` 页面不包标准外层 `ScrollView`
  - 直接把 detail 尺寸交给页面
- 修改 `CLISettingsView.swift`：
  - 确保左侧工具列表和右侧详情在新 detail 容器下能稳定约束
  - 检查 `toolList.frame(width: 190)` 是否仍然合适；必要时改成最小宽加可压缩策略

**Step 4: Run build and smoke test**

Run: `swift build --target VibeBarApp`
Expected: PASS

Run: `VIBEBAR_DEBUG_DOCK=1 swift run VibeBarApp`
Expected: CLI 页面在 sidebar shell 中布局稳定，右侧详情正常滚动，窗口缩放时不出现新的裁切。

**Step 5: Commit**

```bash
git add Sources/VibeBarApp/CLISettingsView.swift Sources/VibeBarApp/SettingsShellView.swift Tests/VibeBarAppTests/SettingsShellModelsTests.swift
git commit -m "refactor(settings): stabilize cli page in shell layout"
```

### Task 7: Final regression pass and documentation

**Files:**
- Modify: `docs/plans/2026-03-22-settings-sidebar-shell-design.md`
- Modify: `CHANGELOG.md`

**Step 1: Run focused tests**

Run: `swift test --filter SettingsShellModelsTests`
Expected: PASS

Run: `swift test --filter SettingsResponsiveLayoutTests`
Expected: PASS

**Step 2: Run app build**

Run: `swift build --target VibeBarApp`
Expected: PASS

**Step 3: Manual regression checklist**

- `General / Appearance / Usage / Hooks / About` 不再左右溢出
- `Usage` 卡片会随窗口宽度自动减少列数
- `Appearance` 图标网格会随窗口宽度自动减少列数
- `CLI` 页面维持双栏结构且右侧可滚动
- `Cmd+1...Cmd+6` 仍然能切换页面
- 切换页面时窗口不再跳尺寸

**Step 4: Update docs**

- 在 `CHANGELOG.md` 记录设置窗口导航与布局重构
- 若实现中对设计有偏离，回写 `docs/plans/2026-03-22-settings-sidebar-shell-design.md`

**Step 5: Commit**

```bash
git add CHANGELOG.md docs/plans/2026-03-22-settings-sidebar-shell-design.md
git commit -m "docs(settings): record sidebar shell refactor"
```
