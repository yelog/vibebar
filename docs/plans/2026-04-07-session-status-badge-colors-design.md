# Session Status Badge Color Consistency Design

**Date:** 2026-04-07

**Status:** Confirmed

## Summary

将 session 列表第一行右侧的“状态 + 时间” badge 改为直接复用“设置 > 外观”中的状态颜色，并从同一状态主色派生文字、边框、背景。这样菜单 SwiftUI、刘海 SwiftUI、AppKit 菜单项三处展示都会与当前主题和自定义状态颜色保持一致。

## Problem

当前实现里，状态 badge 的颜色来源与设置页状态颜色分离：

- [`SessionDisplayFormatter`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/SessionDisplayFormatter.swift#L113) 把状态硬编码映射到 badge tone：
  - `running -> .client`
  - `awaitingInput -> .origin`
  - `idle -> .neutral`
- [`SessionBadgeStyle`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/SessionBadgeView.swift#L31) 再把 tone 映射成固定的 `systemBlue / systemOrange / secondaryLabelColor`
- [`AppSettings`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/AppSettings.swift#L389) 才是“设置 > 外观”里的真实状态颜色来源，支持预设主题和自定义颜色

结果是：用户修改状态颜色后，状态点和其他状态展示会变化，但 session 第一行右侧的状态 badge 不会同步。

## Goals

- 让 session 第一行右侧状态 badge 与“设置 > 外观”中的状态颜色完全同源
- 让状态 badge 的文字、边框、背景都从同一状态主色派生
- 保证菜单 SwiftUI、刘海 SwiftUI、AppKit 菜单项三处一致
- 不引入新的颜色配置入口，继续以 `AppSettings` 为唯一状态颜色源
- 保持现有胶囊 badge 视觉，不改布局和信息层级

## Non-Goals

- 不重做 `client / manager / origin / tty` 等终端来源 badge 的语义色
- 不调整设置页外观面板的交互和配色模型
- 不修改状态优先级、持续时间格式或 badge 排序
- 不扩展到其他非 session badge 的 UI 组件

## Decision

### 1. 状态 badge 改为“状态驱动样式”，不再复用语义 tone

保留现有 `SessionBadgeTone` 供终端来源 badge 使用，但状态 badge 不再通过 `.client / .origin / .neutral` 间接套色。

改为给 `SessionBadge` 增加可选的状态驱动样式描述，例如：

- `accentState: ToolActivityState?`

当 badge 带有 `accentState` 时，表示这个 badge 应该直接使用该状态在当前外观设置下的颜色，而不是走固定 tone 颜色。

这样做比把字面颜色存进 badge 更稳妥，因为状态颜色会随主题、自定义颜色和系统外观变化；badge 只携带“我属于哪个状态”，真正的颜色在渲染时解析，避免出现切换外观后 badge 颜色陈旧的问题。

### 2. 颜色解析集中到 `SessionBadgeStyle`

`SessionBadgeStyle` 不再只根据 `tone` 返回颜色，而是统一接受整个 `SessionBadge` 进行解析：

- 如果 badge 处于高亮态，继续沿用当前白色高亮覆盖逻辑，保证菜单选中态可读性
- 如果 badge 带有 `accentState`：
  - 主色使用 `AppSettings.shared.nsColor(for: state)`
  - 文字色使用主色本身
  - 边框色使用主色的低透明度版本
  - 背景色使用主色的更低透明度版本
- 如果 badge 没有 `accentState`，继续使用现有 tone 颜色规则

状态 badge 的推荐派生参数：

- `text = base`
- `border = base.opacity(0.32)`
- `fill = base.opacity(0.16)`

`unknown` 不需要单独造新颜色，继续通过 `AppSettings` 自然退化到 `secondaryLabelColor`。

### 3. `duration` badge 直接携带 session 状态

[`SessionDisplayFormatter`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/SessionDisplayFormatter.swift#L113) 中的 `durationBadge(for:now:)` 改为直接生成状态驱动 badge：

- 文案仍为 `状态 + 时间`
- `kind` 仍为 `.duration`
- `tone` 保留现有字段以兼容其他 badge 分支
- 新增 `accentState = session.status`

这样 `duration` badge 的颜色来源会与 `StatusGlyph` 和其他状态展示保持同源，不再依赖 `toneForStatus(_:)` 这种额外映射层。

### 4. SwiftUI 与 AppKit 共用同一套 badge 颜色解析

这次不在各处 UI 里各自拼状态色：

- [`SessionBadgeView`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/SessionBadgeView.swift#L96) 改为通过新的 badge 解析接口获取文字/背景/边框
- [`SessionBadgePillView`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/StatusItemController.swift#L2592) 也改为通过同一接口绘制 AppKit badge

这样菜单、刘海、AppKit 三条渲染路径共用同一套 badge 样式规则，避免只修一处又留下另一处不一致。

## Files Affected

- Modify: `Sources/VibeBarApp/SessionBadgeView.swift`
- Modify: `Sources/VibeBarApp/SessionDisplayFormatter.swift`
- Modify: `Sources/VibeBarApp/StatusItemController.swift`
- Create: `Tests/VibeBarAppTests/SessionBadgeStyleTests.swift`
- Modify: `Tests/VibeBarAppTests/SessionDisplayFormatterTests.swift`

`MenuContentView` 和 `NotchContentView` 预计不需要逻辑改动，因为它们已经通过 `SessionBadgeView` 渲染 badge；样式统一后会自动继承新颜色行为。

## Validation

- 切换“设置 > 外观”的预设主题后，session 第一行右侧状态 badge 颜色立即同步变化
- 修改自定义 `running / awaitingInput / idle` 颜色后，状态 badge 的文字、边框、背景同步变化
- `running / awaitingInput / idle / unknown` 在菜单、刘海、AppKit 菜单项三处表现一致
- `client / manager / origin / tty` 等终端来源 badge 的现有语义色不受影响
- 菜单选中高亮时，状态 badge 仍保持稳定可读
