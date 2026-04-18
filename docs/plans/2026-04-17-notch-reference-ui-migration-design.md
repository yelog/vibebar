# Notch Reference UI Migration Design

**Date:** 2026-04-17

**Status:** Confirmed

## Summary

本次迁移的目标，是将当前 `VibeBar` 刘海展开面板的视觉表现，对齐参考工作区 `/Users/yelog/workspace/swift/VibeBar-codex-notch-ui` 中已经验证过的 notch UI 风格。

本次只迁移 notch 面板相关视觉，不顺带改动普通菜单弹窗 `MenuContentView`、状态栏预览和设置页里的复用组件样式。

目标包括：

1. 顶栏应用名、图标区、按钮区和分割线样式对齐参考分支。
2. Session 列表获得更明确的 hover / pressed 高亮、文字层级和 badge 视觉。
3. Token Usage 卡片切换到统一的深色面板风格和更清晰的 footer 信息层级。

## Scope

### In Scope

- `NotchPanelRootView` 的顶栏、padding、阴影、分割线和按钮视觉。
- `NotchCollapsedView` 与 `StatusGlyph` 的图标尺寸、色彩和状态环风格。
- `NotchExpandedBodyView` 中 Session 分组区、行文本层级、hover / pressed 行样式。
- `UsageMenuSectionView` 与 `UsageSeriesLegendView` 的 notch 卡片视觉。
- 为共享 Session 组件增加 notch 专用 appearance 入口，避免把 notch 风格泄漏到菜单和设置页。

### Out Of Scope

- Session 数据聚合、排序、命名、状态检测逻辑。
- 持久化“当前选中 Session”模型状态。
- `MenuContentView`、`StatusItemController` 里的菜单式外观统一改版。
- 使用参考分支整文件覆盖当前分支的交互实现。

## Current Gap

当前 notch 面板已经具备单 `NSPanel` 架构和完整交互，但视觉层仍偏向默认 SwiftUI 配色：

1. `NotchPanelStyle` 只定义了少量基础 token，无法统一驱动 notch 专属深色表面。
2. 顶栏、Session 行、Badge、Usage 卡片分别使用 `.primary` / `.secondary` 和局部透明白，整体语言不一致。
3. `SessionGroupingControls`、`SessionBadgeView`、`UsageMenuSectionView` 是共享组件，直接替换会把参考分支的 notch 风格扩散到普通菜单 UI。

## Chosen Approach

采用“notch 专用视觉 token + 共享组件 appearance 隔离 + 分区迁移”的方式，而不是直接把参考分支文件整体复制过来。

### Step 1: Establish Notch Tokens

先把参考分支中稳定的视觉 token 迁入 `NotchPanelStyle`，包括：

- `surfaceElevated`
- `surfaceCard`
- `dividerColor`
- `hoverFillColor`
- `pressedFillColor`
- `primaryTextColor`
- `secondaryTextColor`
- `tertiaryTextColor`
- `accentColor`
- `neutralAccentColor`
- `horizontalPadding`
- `iconButtonSize`
- `smallButtonCornerRadius`

这样后续视图改动都能引用统一样式，不会继续散落硬编码颜色。

### Step 2: Keep Shared Components Scoped

`SessionGroupingControls` 和 `SessionBadgeView` 不能直接全局替换为 notch 风格。

建议给这类共享组件增加轻量 appearance 参数，例如：

```swift
enum SessionChromeAppearance {
    case standard
    case notch
}
```

其中：

- `NotchExpandedBodyView` 传 `.notch`
- `MenuContentView`、`StatusItemController`、`UsageSettingsView` 保持默认 `.standard`

这样可以在不拆组件的情况下，把 notch 视觉迁移限制在刘海面板。

### Step 3: Migrate Notch Chrome First

优先迁移外壳和顶栏：

- `NotchPanelRootView`
- `NotchCollapsedView`
- `StatusGlyph`

这一步会让截图上半部分先对齐，包括：

- 左上应用名文本色与 spacing
- 右侧按钮 hover 态
- 顶栏底部 divider
- 左侧 agent icon
- 右侧数字环和状态色
- 整体 panel 阴影与圆角观感

### Step 4: Migrate Session List Styling

然后迁移 `NotchExpandedBodyView` 内的会话列表：

- 分组行文字和计数颜色层级
- Session 标题字重
- 次级文本与第 3 行辅助信息的层级
- hover / pressed 背景
- 左侧 accent 条
- badge 配色和最多显示数量

需要强调的是：参考分支只有 hover / pressed 高亮，并没有“点击后常驻”的持久选中态。因此本次迁移不新增 `selectedSessionID`。

### Step 5: Migrate Token Usage Card

最后迁移 `UsageMenuSectionView` 和 `UsageSeriesLegendView`：

- 标题和副标题使用 notch 文本 token
- 图表容器使用 `surfaceElevated + strokeColor`
- bar / line / heatmap 共用统一容器描边
- X 轴和 hover 指示线使用 `dividerColor` / `accentColor`
- footer 改为“大数字 + 小单位 + 右侧日期范围”布局
- legend 字号、最小宽度和颜色改为 notch 版本

这部分改动最多，但和业务逻辑几乎解耦。

## File Map

### Core Style Layer

- Modify: `Sources/VibeBarApp/NotchPanelStyle.swift`

### Notch Container And Header

- Modify: `Sources/VibeBarApp/NotchPanelRootView.swift`
- Modify: `Sources/VibeBarApp/NotchCollapsedView.swift`
- Modify: `Sources/VibeBarApp/StatusGlyph.swift`

### Session List Styling

- Modify: `Sources/VibeBarApp/NotchExpandedBodyView.swift`
- Modify: `Sources/VibeBarApp/SessionGroupingControls.swift`
- Modify: `Sources/VibeBarApp/SessionBadgeView.swift`

### Usage Styling

- Modify: `Sources/VibeBarApp/UsageMenuSectionView.swift`
- Modify: `Sources/VibeBarApp/UsageSeriesLegendView.swift`

### Explicitly Left Unchanged In This Migration

- `Sources/VibeBarApp/MenuContentView.swift`
- `Sources/VibeBarApp/UsageSettingsView.swift`
- `Sources/VibeBarApp/StatusItemController.swift`

这些文件只会在需要接收新的默认参数时做最小适配，不会切换成 notch 视觉。

## Risks

1. 共享组件串色
如果不做 appearance 隔离，菜单和设置页会一起变成 notch 风格。

2. 布局轻微回归
顶栏 padding、badge 高度、Session 行内边距变化后，展开面板总高度和 hover hit area 需要重新核对。

3. 参考分支不是当前分支的直接上游
当前分支已经包含新的 Codex 状态和交互流，不能直接把参考分支文件整块拷回。

4. 截图中的“选中感”容易被误解成持久选中
如果后续需要点击后保持高亮，需要单独设计状态模型，不应混入本次纯视觉迁移。

## Validation

迁移完成后需要满足：

1. notch 展开面板顶栏、左侧图标位、右侧数字环和按钮视觉接近参考分支。
2. Session 列表 hover / pressed 时有明显高亮和左侧强调条，但点击后不引入新的持久选中状态。
3. Token Usage 卡片的容器、legend、footer 信息层级接近参考分支截图。
4. 普通菜单弹窗和设置页预览仍维持现有样式，不被 notch 视觉污染。
5. `swift build --target VibeBarApp` 通过，`VIBEBAR_DEBUG_DOCK=1 swift run VibeBarApp` 下人工检查无明显回归。
