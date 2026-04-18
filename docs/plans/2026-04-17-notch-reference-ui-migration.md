# Notch Reference UI Migration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 让当前 VibeBar 的 notch 展开面板在不影响普通菜单和设置页样式的前提下，对齐参考工作区的顶栏、Session 列表和 Token Usage 视觉。

**Architecture:** 先把参考分支中的深色 notch token 收敛到 `NotchPanelStyle`，再通过共享组件的 appearance 隔离，把 notch 风格只注入 `NotchExpandedBodyView` 和 notch 外壳相关视图。顶栏、状态环、Session 行和 Usage 卡片分阶段迁移，避免一次性大改共享组件导致菜单 UI 串色。

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, Swift Package Manager

---

### Task 1: 建立 notch 专用视觉 token

**Files:**
- Modify: `Sources/VibeBarApp/NotchPanelStyle.swift`
- Modify: `Sources/VibeBarApp/StatusGlyph.swift`

**Step 1: 补齐参考分支中的 notch token**

在 `NotchPanelStyle` 中加入统一的深色表面和文本 token，形态参考：

```swift
static let surfaceElevated = Color(red: 0.047, green: 0.063, blue: 0.078)
static let surfaceCard = Color(red: 0.067, green: 0.086, blue: 0.106)
static let dividerColor = Color.white.opacity(0.07)
static let primaryTextColor = Color(red: 0.953, green: 0.965, blue: 0.980)
static let secondaryTextColor = Color(red: 0.651, green: 0.686, blue: 0.729)
static let tertiaryTextColor = Color(red: 0.435, green: 0.471, blue: 0.514)
static let accentColor = Color(red: 0.337, green: 0.761, blue: 1.000)
```

**Step 2: 补齐 notch 布局常量**

增加：

```swift
static let horizontalPadding: CGFloat = 14
static let iconButtonSize: CGFloat = 28
static let smallButtonCornerRadius: CGFloat = 9
```

并把已有圆角、阴影与 top highlight 调整到参考分支量级。

**Step 3: 统一状态环配色来源**

让 `StatusGlyph` 使用 `NotchPanelStyle.color(for:)` 和 notch 文本色，而不是 `AppSettings.shared.swiftUIColor(...)` 与默认 `Color.primary`。

**Step 4: 运行 App target 构建**

Run: `swift build --target VibeBarApp`

Expected: 构建通过，尚未改变普通菜单 UI。

### Task 2: 为共享 Session 组件加 appearance 隔离

**Files:**
- Modify: `Sources/VibeBarApp/SessionGroupingControls.swift`
- Modify: `Sources/VibeBarApp/SessionBadgeView.swift`
- Modify: `Sources/VibeBarApp/MenuContentView.swift`
- Modify: `Sources/VibeBarApp/StatusItemController.swift`
- Modify: `Sources/VibeBarApp/UsageSettingsView.swift`

**Step 1: 建立共享 appearance 类型**

在共享 Session 组件附近新增轻量外观类型，例如：

```swift
enum SessionChromeAppearance {
    case standard
    case notch
}
```

**Step 2: 给分组切换器增加 appearance 参数**

让 `SessionGroupingModeSwitcher` 和 `SessionSectionHeaderView` 支持：

```swift
SessionSectionHeaderView(
    title: ...,
    selection: ...,
    compact: true,
    appearance: .notch
)
```

默认值保持 `.standard`，确保 `MenuContentView` 不变。

**Step 3: 给 badge 组件增加 appearance 参数**

让 `SessionBadgeView` 和 `SessionBadgeStrip` 支持 notch 调色和数量裁剪，例如：

```swift
SessionBadgeStrip(badges: badges, compact: true, appearance: .notch)
```

notch 版本只展示前 2 个 badge，菜单版本保持现状。

**Step 4: 在非 notch 调用点显式保留标准外观**

检查 `MenuContentView`、`StatusItemController`、`UsageSettingsView` 的调用点，只做最小参数适配，不改它们视觉。

**Step 5: 运行构建验证共享组件未破坏调用点**

Run: `swift build --target VibeBarApp`

Expected: 所有调用点编译通过。

### Task 3: 迁移 notch 外壳和顶栏样式

**Files:**
- Modify: `Sources/VibeBarApp/NotchPanelRootView.swift`
- Modify: `Sources/VibeBarApp/NotchCollapsedView.swift`
- Modify: `Sources/VibeBarApp/StatusGlyph.swift`

**Step 1: 对齐展开态顶栏 spacing 和 divider**

把 `NotchPanelRootView` 的展开顶栏改为使用 notch token：

```swift
.padding(.horizontal, NotchPanelStyle.horizontalPadding)
.overlay(alignment: .bottom) {
    Rectangle()
        .fill(NotchPanelStyle.dividerColor)
        .frame(height: 1)
}
```

**Step 2: 把顶栏按钮改成 hover 驱动的独立 view**

用参考分支的结构替换本地 `ButtonStyle`，让按钮 hover 时才出现底色和描边。

**Step 3: 对齐 collapsed 壳体里的图标尺寸和排序**

把 `NotchCollapsedView` 的 active tool 选择逻辑、tool icon 尺寸、status glyph 尺寸和文本颜色对齐参考分支。

**Step 4: 调整 panel 阴影和整体观感**

让 `NotchPanelRootView` 的外层阴影接近参考值：更深、半径更大、Y 偏移略高。

**Step 5: 运行应用人工检查 notch 外壳**

Run: `VIBEBAR_DEBUG_DOCK=1 swift run VibeBarApp`

Expected: 顶栏应用名、左右图标位、状态环和按钮 hover 态接近参考分支。

### Task 4: 迁移 Session 区域视觉

**Files:**
- Modify: `Sources/VibeBarApp/NotchExpandedBodyView.swift`
- Modify: `Sources/VibeBarApp/SessionGroupingControls.swift`
- Modify: `Sources/VibeBarApp/SessionBadgeView.swift`

**Step 1: 把 notch Session 标题区切到 notch appearance**

在 `NotchExpandedBodyView` 中显式传入：

```swift
SessionSectionHeaderView(
    title: l10n.string(.sessionTitle),
    selection: $settings.sessionGroupingMode,
    compact: true,
    appearance: .notch
)
```

**Step 2: 对齐分组行的文字层级和缩进**

把 group header 的箭头、图标、标题、详情和计数字色改成 `primary/secondary/tertiaryTextColor`，并对齐参考分支的间距与展开缩进。

**Step 3: 对齐 Session 行文字层级和字重**

主标题改为 semibold，二级文案和第 3 行辅助文案分开使用 secondary / tertiary 色。

**Step 4: 对齐 hover / pressed 高亮与左侧 accent 条**

将 `NotchSessionButtonStyle` 改成参考分支结构：

```swift
.background(
    RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(isPressed ? NotchPanelStyle.pressedFillColor : hoverFill)
)
.overlay(alignment: .leading) {
    RoundedRectangle(cornerRadius: 1, style: .continuous)
        .fill(NotchPanelStyle.accentColor.opacity(isActive ? 0.92 : 0))
        .frame(width: 2, height: 28)
}
```

本次不要新增持久 `selectedSessionID`。

**Step 5: 切换 badge strip 为 notch 外观**

让 `NotchExpandedBodyView` 里的 badge strip 使用 notch 版本调色和数量裁剪。

**Step 6: 运行应用人工检查 Session 行交互**

Run: `VIBEBAR_DEBUG_DOCK=1 swift run VibeBarApp`

Expected: hover / pressed 时有明显高亮和左侧蓝色强调条，但点击后不会保持常驻高亮。

### Task 5: 迁移 Token Usage 卡片视觉

**Files:**
- Modify: `Sources/VibeBarApp/UsageMenuSectionView.swift`
- Modify: `Sources/VibeBarApp/UsageSeriesLegendView.swift`
- Modify: `Sources/VibeBarApp/NotchExpandedBodyView.swift`

**Step 1: 统一 header 和空态容器色彩**

把 `UsageMenuSectionView` 的 header、loading、empty state 切到 notch token：

```swift
RoundedRectangle(cornerRadius: 8, style: .continuous)
    .fill(NotchPanelStyle.surfaceElevated)
    .overlay(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(NotchPanelStyle.strokeColor, lineWidth: 1)
    )
```

**Step 2: 对齐 bar / line / heatmap 容器与轴线**

所有图表容器统一改成 `surfaceElevated + strokeColor`，X 轴和 active dot 改用 `dividerColor` / `accentColor`。

**Step 3: 重做 footer 信息层级**

改成参考分支的“大数字 + 小单位 + 右侧日期范围”样式，例如：

```swift
HStack(alignment: .firstTextBaseline, spacing: 4) {
    Text(primaryValueText)
        .font(.system(size: 16, weight: .semibold))
    Text(primaryValueUnitText)
        .font(.system(size: 10, weight: .medium))
}
```

其中 tokens 使用 `compactTokenLabel`，cost 保留两位或四位小数策略。

**Step 4: 压缩 legend 布局**

让 `UsageSeriesLegendView` 采用参考分支的更小最小宽度、更紧凑字号和 notch 文本色。

**Step 5: 对齐 section 分隔线**

把 `NotchExpandedBodyView` 里 Session 和 Usage 之间的 `Divider()` 也切到 `NotchPanelStyle.dividerColor`。

**Step 6: 运行构建并人工检查 Usage 卡片**

Run: `swift build --target VibeBarApp && VIBEBAR_DEBUG_DOCK=1 swift run VibeBarApp`

Expected: Usage 卡片容器、legend、footer 和 hover guide 接近参考分支截图。

### Task 6: 回归验证 notch-only 范围

**Files:**
- Verify: `Sources/VibeBarApp/MenuContentView.swift`
- Verify: `Sources/VibeBarApp/UsageSettingsView.swift`
- Verify: `Sources/VibeBarApp/StatusItemController.swift`

**Step 1: 检查普通菜单仍为标准外观**

打开 status item 普通菜单，确认 `SessionSectionHeaderView` 和 `SessionBadgeStrip` 没有切成 notch 深色风格。

**Step 2: 检查设置页预览未串色**

打开 Usage 设置页和状态栏预览，确认新 appearance 默认值没有污染现有 UI。

**Step 3: 运行全量测试与构建**

Run: `swift test && swift build`

Expected: 构建通过；若测试基线已有非本次问题，记录下来但不要扩大修复范围。

**Step 4: 如用户要求，再创建提交**

仅在用户明确要求提交时执行：

```bash
git add Sources/VibeBarApp/NotchPanelStyle.swift Sources/VibeBarApp/NotchPanelRootView.swift Sources/VibeBarApp/NotchCollapsedView.swift Sources/VibeBarApp/StatusGlyph.swift Sources/VibeBarApp/NotchExpandedBodyView.swift Sources/VibeBarApp/SessionGroupingControls.swift Sources/VibeBarApp/SessionBadgeView.swift Sources/VibeBarApp/UsageMenuSectionView.swift Sources/VibeBarApp/UsageSeriesLegendView.swift
git commit -m "fix(notch): align panel UI with reference styling"
```
