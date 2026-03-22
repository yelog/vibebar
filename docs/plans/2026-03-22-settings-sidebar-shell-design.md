# Settings Sidebar Shell Design

**Date:** 2026-03-22

**Status:** Confirmed

## Summary

本次设计将 VibeBar 设置窗口从“顶部 tab + 按页面手工调整窗口尺寸”的结构，重构为“左侧 sidebar 导航 + 右侧统一内容区 + 单一可调窗口”的壳层架构。

核心变化：

1. 顶部 tab 导航改为左侧 sidebar，消除随着 tab 数量增长产生的横向挤压与裁切。
2. 窗口不再按页面写死宽高，改为一套稳定的默认尺寸和最小尺寸，允许用户手动调整。
3. 页面内容统一挂到设置壳层中，默认由壳层负责滚动、边距、section/card 结构。
4. 对复杂页面保留特例能力，例如 `CLI` 页面可以声明为自管理布局，而不是被强行塞进统一滚动容器。
5. `Usage`、`Appearance` 等使用固定列数的页面，改为基于可用宽度的响应式布局。

## Goals

- 彻底消除设置页在不同 tab、不同语言文案下的横向溢出和裁切。
- 去掉对 `contentWidth(for:)` / `contentHeight(for:)` 这类魔法数字的长期依赖。
- 为后续增加 `Advanced`、`Diagnostics`、`Labs` 等页面预留稳定扩展位。
- 统一设置页的导航、滚动、间距、section/card 样式，降低后续维护成本。
- 让布局对中文、英文、未来新增本地化都更稳健。

## Non-Goals

- 首版不重做设置页视觉语言，只调整导航结构和布局策略。
- 首版不引入全文搜索，但要为后续接入预留页面注册与选中机制。
- 首版不重写所有页面内容，只优先改造会受壳层影响的根布局和固定列数。
- 首版不做 UI snapshot 测试体系，但会为纯策略和页面注册引入可测试对象。

## Current State

- 当前设置页根视图在 [SettingsView.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/SettingsView.swift) 中实现，顶部导航是一个 `HStack`，6 个页面都放在同一行。
- 当前窗口宽度由 `SettingsPanelLayout.contentWidth(for:)` 决定，多个页面仍使用 `550pt` 的基础宽度。
- 顶部按钮最小宽度是 `92pt`，同时有 `24pt` 左右边距与 `10pt` 按钮间距；6 个 tab 时理论最小总宽已经达到 `650pt`。
- `NSHostingController` 的自动尺寸能力在 [SettingsWindowController.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/SettingsWindowController.swift) 中被关闭，窗口尺寸完全依赖手工计算。
- `General` / `Appearance` / `About` 由根视图包裹 `ScrollView`，`Usage` 自己内部再包 `ScrollView`，`Hooks` 则把滚动留给内部列表，页面之间缺乏统一约束。
- `UsageSettingsView` 中仍存在固定 4 列来源卡片、固定 3 列样式卡片、固定 3 列控制项的布局假设。

## Root Cause

问题本质上不是单个控件超宽，而是整体布局模型已经与功能规模脱节：

1. 顶部导航仍按“少量 tab”假设设计，但页面数量已经增长到 6 个。
2. 窗口尺寸仍按页面静态写死，而不是基于壳层与内容的最小可用宽度统一约束。
3. 页面对滚动、列数、边距的责任边界不清晰，导致根视图和子页面在互相争夺布局控制权。
4. 新增功能时只是在现有架构上继续叠加卡片和选项，没有同步升级设置窗口的导航与响应式结构。

## Product Decisions

### Navigation Model

- 设置窗口改为 sidebar 导航。
- 首版保持单层页面列表，不增加二级树结构。
- 页面顺序维持当前习惯：
  - General
  - CLI
  - Appearance
  - Usage
  - Hooks
  - About
- 现有快捷键 `Cmd+1...Cmd+6` 继续保留，直接映射到 sidebar 选中项。

### Window Strategy

- 取消按页面自动切换窗口宽高。
- 窗口改为单一默认尺寸，建议：
  - 默认内容尺寸：约 `780 x 700`
  - 最小内容尺寸：约 `720 x 620`
  - 最大内容尺寸：保留较宽松上限，不再按页面卡死
- 用户可以手动调整窗口大小，设置页不再因为切换页面而跳动。

### Content Ownership

- 壳层统一负责：
  - 页面选中态
  - sidebar
  - 默认滚动容器
  - 内容区边距
  - 页面标题、副标题、section/card 基础样式
- 页面只负责自己的业务内容。
- 允许页面声明展示模式：
  - `standardScrollable`：壳层负责滚动与标准边距
  - `fullBleed`：页面自管理布局，适合 `CLI` 这种内部分栏页面

### Responsive Layout

- 不再使用“固定列数适配某个当前宽度”的做法。
- 所有卡片网格改为基于容器宽度的自适应列数。
- 所有说明文案默认允许多行。
- 分段控件在宽度不足时，应降级为 `Picker(.menu)` 或纵向排列，而不是硬顶宽度。

## Chosen Architecture

采用“设置壳层 + 页面注册表 + 页面展示模式”的结构。

### 1. Settings Shell

新增一个专用壳层视图，例如：

- `SettingsShellView`
- `SettingsSidebarView`
- `SettingsDetailContainer`

职责：

- 渲染 sidebar 与 detail 区域
- 管理当前选中的页面
- 响应快捷键切换
- 统一 detail 区域滚动和边距
- 为特殊页面切换展示模式

### 2. Page Registry

引入页面注册结构，而不是把导航文案、图标、顺序和内容散落在 `switch` 与数组里。

建议结构：

- `SettingsPage`
- `SettingsPageDescriptor`
- `SettingsPagePresentation`

每个 descriptor 至少包含：

- `id`
- `title`
- `icon`
- `keyboardShortcut`
- `presentation`
- `makeContent()`

这样可以把页面注册、sidebar 渲染、快捷键和默认选中逻辑收敛在同一处。

### 3. Window Policy

`SettingsWindowController` 从“根据 tab 切换尺寸”改为“配置统一窗口策略”。

新职责：

- 创建并展示设置窗口
- 应用统一的默认尺寸 / 最小尺寸 / 最大尺寸
- 保留用户手动调整后的窗口 frame
- 不再感知每个页面自己的宽高偏好

### 4. Standard Page Container

对 `General` / `Appearance` / `Usage` / `Hooks` / `About` 这类标准设置页，引入统一 detail 容器：

- 统一 `ScrollView`
- 统一 `padding`
- 统一 section 间距
- 统一顶部标题区

这些页面改成输出“纯内容块”，不再各自决定是否包外层滚动。

### 5. Full-Bleed Page Support

`CLI` 仍然保留自管理布局：

- 左侧工具列表
- 右侧详情与局部滚动

但它不再参与根窗口宽度计算，也不应反向影响其他页面。

壳层只负责给它提供 detail 区域的完整尺寸。

## Page-Level Changes

### General

- 继续使用标准 section/card 页面。
- 仅移除外层滚动责任，交给壳层统一管理。

### Appearance

- 图标卡片网格可保留 4 列上限，但要按可用宽度自适应缩减为 3 列或 2 列。
- 颜色区域保持标准 section 结构。

### Usage

- 把固定 4 列来源卡片、固定 3 列样式卡片、固定 3 列控制项改为 adaptive grid。
- 滚动责任移交给壳层。
- 若预览区对 tooltip / overlay 有特殊依赖，保留局部 overlay，不保留外层 `ScrollView`。

### Hooks

- 页面根层收敛到标准设置内容。
- hooks 列表可以继续内部滚动，但外层页面结构要适配统一 detail 容器。

### About

- 保持信息展示为主，但不再拥有独立的根滚动策略。

## Suggested New Components

- `Sources/VibeBarApp/SettingsShellModels.swift`
- `Sources/VibeBarApp/SettingsShellView.swift`
- `Sources/VibeBarApp/SettingsSidebarView.swift`
- `Sources/VibeBarApp/SettingsDetailContainer.swift`
- `Sources/VibeBarApp/SettingsResponsiveLayout.swift`

说明：

- 不要求首版一次性拆成很多文件，但结构上建议将“壳层 / 模型 / 页面内容”分离，避免继续把所有设置逻辑堆在单个 `SettingsView.swift` 中。

## Existing Files Likely to Change

- [SettingsView.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/SettingsView.swift)
- [SettingsWindowController.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/SettingsWindowController.swift)
- [CLISettingsView.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/CLISettingsView.swift)
- [UsageSettingsView.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/UsageSettingsView.swift)
- [HooksSettingsView.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/HooksSettingsView.swift)
- [Package.swift](/Users/yelog/workspace/swift/VibeBar/Package.swift)

## Risks

- `CLI` 是当前设置页里最接近“子应用”的页面，若直接套用统一页面容器，容易出现双重滚动或分栏约束冲突。
- `Usage` 预览区存在 tooltip 与图表 hover 逻辑，改动根滚动容器时需要验证坐标空间和 overlay 定位。
- 如果只把顶部 tab 换成 sidebar，但仍保留页面各自的固定列数与滚动策略，问题只会从“顶部裁切”变成“内容拥挤”。
- 当前没有 `VibeBarApp` 对应测试 target；若不先补上纯策略测试承载位，后续重构会过度依赖手工验证。

## Manual Validation

- 设置窗口在 `General / Appearance / Usage / About` 页面不再出现左右裁切。
- 中文环境下 sidebar 项目完整显示，不因文案长度影响内容区布局。
- 切换不同页面时窗口不再跳尺寸。
- 窗口缩窄时：
  - `Usage` 卡片列数自动减少
  - `Appearance` 图标网格自动减少列数
  - 文案正常换行
- `CLI` 页面仍然能正常选择工具、滚动右侧详情、执行安装/更新等操作。
- `Hooks` 页面有数据和空状态都能在统一壳层下正常显示。
