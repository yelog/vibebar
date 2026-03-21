# Notch Display Design

**Date:** 2026-03-21

**Status:** Confirmed

## Summary

本次设计为 VibeBar 增加一个可选的“刘海展示”入口形态：

1. 在 `General > System` 新增 `在刘海区域显示 VibeBar` 开关。
2. 开启后隐藏原有菜单栏 `NSStatusItem`，改为在支持刘海的主屏顶部中央显示一个贴刘海的收起态胶囊。
3. 鼠标移入刘海区域时自动展开为悬浮信息面板，继续承接当前菜单的大部分实时状态内容。
4. 当当前主屏不支持刘海展示时，自动回退为普通菜单栏图标模式，并在设置页提示原因。

## Goals

- 提供比传统菜单栏图标更符合当前 macOS 趋势的入口形态。
- 保留 VibeBar “轻量状态入口 + 展开查看细节”的核心体验。
- 尽量复用现有 session / usage / settings 数据链路，不重做业务状态模型。
- 不让用户因为切换展示方式而丢失入口。

## Non-Goals

- 不尝试把第三方图标真正注册进系统菜单栏保留区或刘海内部。
- 不在首版把刘海面板做成完整设置中心。
- 不在首版开放展开/收起延迟、尺寸等高级自定义项。
- 不在首版兼顾无刘海屏上的额外悬浮入口样式；无刘海场景直接回退菜单栏模式。

## Current State

- 当前唯一入口是 [StatusItemController.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/StatusItemController.swift) 中的 `NSStatusItem`。
- 设置页 `General` tab 位于 [SettingsView.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/SettingsView.swift)，系统相关开关目前包括开机启动与通知设置。
- 持久化设置集中在 [AppSettings.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/AppSettings.swift)。
- 现有菜单内容以 AppKit 自定义 `NSMenuItem` 视图为主，悬停提示、usage tooltip 等场景已经在 [StatusItemController.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/StatusItemController.swift) 中实现了 `NSPanel + hover tracking` 组合。
- 另有一个未接入主入口的 SwiftUI 版 [MenuContentView.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/MenuContentView.swift)，可作为刘海展开面板的内容组织参考，但不适合直接照搬现有菜单样式。

## Platform Constraints

- Apple 对 macOS 刘海屏公开提供的是屏幕安全区域与可见区域能力，而不是第三方 App 可以占据“刘海内部保留位”的专用 API。
- 实现上更合理的做法是：在支持刘海的主屏顶部安全区域附近放置一个不抢焦点的悬浮入口，并根据 `NSScreen` 的几何信息决定是否启用。
- 参考资料：
  - [NSScreen.visibleFrame](https://developer.apple.com/documentation/AppKit/NSScreen/visibleFrame)
  - [NSScreen.safeAreaInsets](https://developer.apple.com/documentation/appkit/nsscreen/safeareainsets?changes=_8)

## Product Decisions

### Entry Model

- 新模式命名为 `刘海展示`，作为 `General > System` 下的一个总开关。
- 开启且当前主屏支持刘海时：
  - 隐藏原有菜单栏图标。
  - 启用顶部中央的刘海入口。
- 开启但当前主屏不支持刘海时：
  - 自动回退为菜单栏图标模式。
  - 设置页显示说明文案，告知当前屏幕不支持刘海展示。

### Trigger Behavior

- 交互采用“鼠标移到刘海就自动展开”。
- 使用缓冲型时序：
  - 进入热区后延迟 `120-180ms` 展开。
  - 离开入口与面板后延迟 `220-280ms` 收起。
- 不要求点击展开，点击保留给未来可能的快捷动作。

### Collapsed Style

- 收起态采用“贴刘海下沿的状态胶囊”，而不是复用当前 `18x18` 菜单栏图标。
- 建议尺寸：
  - 宽 `64-84pt`
  - 高 `20-24pt`
- 视觉风格：
  - 深色背景，接近纯黑但非死黑
  - 轻微描边与弱阴影，保证在浅色壁纸上可见
  - 整体克制，不做夸张呼吸灯效果
- 内部信息采用“三段式”：
  - 左：主状态色点或简化能量条
  - 中：总 session 数
  - 右：最多 2 个次级状态点
- `0 session` 时保持低存在感，不进行高亮提示。

### Expanded Animation

- 展开不做“菜单突然掉落”，而是做“胶囊被向下拉开”的形变。
- 动画分三段：
  1. 预热：胶囊轻微放大、提亮
  2. 形变：容器自胶囊向下展开
  3. 显现：摘要、列表、底部操作依次淡入
- 总时长建议 `260-320ms`。
- 收起时先淡出内容，再压缩回胶囊，总时长略短于展开。
- 必须加入桥接热区和离开容错，避免从胶囊移向面板时出现抖动收起。

### Expanded Layout

- 展开态使用独立 `NSPanel`，不抢当前 App 焦点。
- 容器建议宽 `420-460pt`，高度按内容自适应，默认上限 `520-560pt`。
- 内容分为四个区块：
  1. 顶部摘要区：总状态、总 session 数、更新时间、状态汇总
  2. 主内容区：session 列表，延续当前菜单的大部分核心信息
  3. 次级信息区：若启用 Usage，以轻量卡片形式展示摘要
  4. 底部操作区：刷新、打开设置、退出
- session 列表继续支持“按工具分组”与“平铺列表”，但样式从菜单项升级为顶部信息面板行样式。
- 插件安装、wrapper 管理、复杂设置项不进入刘海面板，仍留在设置窗口。

### Fallback and Multi-Screen

- 支持刘海的主屏：启用刘海入口。
- 无刘海主屏：回退菜单栏图标模式。
- 外接无刘海显示器成为主屏时：回退菜单栏图标模式，不把入口留在非主交互屏。
- 监听屏幕拓扑变化，在刘海模式与菜单栏模式之间动态切换。
- 若全屏场景下与某些 App 顶部交互冲突，优先保证不抢焦点与不误触；必要时允许临时回退。

## Chosen Architecture

采用“主入口协调器 + 两类入口宿主 + 共享内容模型”的 AppKit / SwiftUI 混合方案。

### Settings and Availability

- 在 [AppSettings.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/AppSettings.swift) 增加 `notchDisplayEnabled`。
- 新增一层刘海可用性判断：
  - 用户是否开启
  - 当前主屏是否支持刘海展示
  - 当前环境是否需要临时回退
- 把“用户意愿”和“当前实际生效模式”区分开，避免用户开启后因外接屏切换导致开关被重置。

### Entry Host Abstraction

- 现有 [StatusItemController.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/StatusItemController.swift) 需要从“只管理 `NSStatusItem`”提升为“管理主入口宿主”的协调器。
- 宿主至少分两类：
  - `MenuBarEntryHost`
  - `NotchEntryHost`
- 这样可以避免在单个控制器里堆积 `if notchMode` 分支，后续也方便继续演进。

### Notch Host

- 新增 `NotchDisplayController`，负责：
  - 收起态胶囊窗口
  - 展开态面板窗口
  - hover tracking / 定时器 / 桥接热区
  - 根据主屏几何信息定位
- 收起态和展开态都应使用 `non-activating` / 不抢焦点的窗口配置。

### Shared Content Model

- 不建议直接把当前菜单的 `NSMenuItem` 视图迁入刘海面板。
- 建议抽一层共享展示数据，例如：
  - 顶部摘要文本
  - 分组后的 session 列表
  - usage 摘要
  - 底部快捷操作定义
- 现有菜单和刘海面板共享数据组织逻辑，但各自保留独立视图层，避免 UI 条件分支膨胀。

## Interaction Details

### Hover Zone

- 入口热区大于实际胶囊可视区域：
  - 左右各扩 `12-16pt`
  - 向下扩 `10-12pt`
- 展开时增加胶囊与面板之间的无形桥接区，确保鼠标移动到面板主体过程中不会错误触发收起。

### Visual Tone

- 收起态关键词：
  - 黑
  - 窄
  - 克制
  - 有活性但不过度发光
- 展开态关键词：
  - 信息岛
  - 深色浮层
  - 精致但不花哨
  - 工具型产品而非消费型卡片

## Implementation Direction

### Suggested New Components

- `NotchDisplayController`
- `NotchCollapsedView`
- `NotchExpandedPanelController`
- `NotchContentView`
- `EntryHostModeResolver` 或等价的纯策略对象

### Existing Files Likely to Change

- [AppSettings.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/AppSettings.swift)
- [SettingsView.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/SettingsView.swift)
- [StatusItemController.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/StatusItemController.swift)
- [L10nStrings.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/L10nStrings.swift)

## Risks

- 顶部 hover 区与全屏应用、系统菜单栏自动隐藏行为之间可能出现交互边界问题，需要实机验证。
- 如果展开态继续沿用当前菜单的 AppKit 构建方式，后续样式调优成本会快速上升。
- 多显示器切换时，若入口宿主切换不彻底，容易出现闪烁或短暂双入口。

## Manual Validation

- 刘海屏主屏下，开启模式后菜单栏图标消失，顶部中央出现收起态胶囊。
- 鼠标移入刘海区域 `120-180ms` 后稳定展开。
- 鼠标从胶囊移动到面板主体过程中不抖动、不误收起。
- 鼠标离开后 `220-280ms` 内收起，重新进入可取消收起。
- 外接无刘海屏成为主屏后，自动回退菜单栏图标模式且入口不丢失。
- 关闭设置中的开关后，立即回到传统菜单栏模式。
