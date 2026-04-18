# Notch Status Badge Theme Sync Design

**Date:** 2026-04-18

**Status:** Confirmed

## Summary

当前刘海下拉框中的 Session 列表右侧状态 badge，例如“空闲 35m”或“等待输入 1m”，在 `.notch` 外观下使用的是 `NotchPanelStyle` 里的固定状态色，不跟随“设置 -> 外观”中的状态主题或自定义颜色。

本次设计的目标，是只让这个 status badge 在 notch 下复用外观主题色，同时保留 notch 自己的布局、透明度、边框强度和其他非状态 badge 的独立视觉。

## Scope

### In Scope

- 刘海下拉框 Session 列表右侧的 `duration` / `status` badge 主色来源。
- `.notch` 外观下 `tone == .status` 且带 `accentState` 的 badge 颜色解析。
- 对应测试，确保 notch status badge 跟随 `AppSettings.shared.nsColor(for:)`。

### Out Of Scope

- 顶部状态环 `StatusGlyph` 的颜色。
- `NotchCollapsedView` 中 collapsed notch 的状态色。
- notch 中 `client`、`manager`、`origin`、`neutral` 等非状态 badge 的配色。
- Session badge 的文案拆分或交互变化。

## Current Behavior

`SessionDisplayFormatter.durationBadge(...)` 会为 Session 状态 badge 创建：

```swift
SessionBadge(
    kind: .duration,
    text: "\(statusText) \(duration)",
    tone: .status,
    accentState: session.status
)
```

在渲染阶段，`NotchExpandedBodyView` 会显式传入：

```swift
SessionBadgeStrip(badges: badges, compact: true, appearance: .notch)
```

而 `SessionBadgeStyle.resolvedColors(...)` 当前对 `.notch` 的状态色解析会走：

```swift
NotchPanelStyle.nsColor(for: state)
```

因此 notch status badge 目前使用的是 notch 专用固定色，而不是设置页中的主题色。

## Chosen Approach

采用最小改动方案：只把 notch status badge 的主色来源切到 `AppSettings.shared.nsColor(for:)`，其余 notch 视觉保持不变。

### Why This Approach

1. 命中用户诉求，只改“状态 + 时长”badge。
2. 不破坏当前 notch 参考视觉里的深色表面和非状态 badge 设计。
3. 改动集中在 `SessionBadgeStyle`，不需要改 Session 数据模型、视图结构或设置项。

## Detailed Design

### 1. Keep Badge Shape And Alpha Rules

status badge 仍保持当前的 notch capsule 规则：

- 文本色 = 基础状态色
- 背景色 = 基础状态色 `0.16 alpha`
- 边框色 = 基础状态色 `0.32 alpha`

也就是说，这次只改“基础状态色来源”，不改透明度或圆角。

### 2. Route Only Notch Status Badges To AppSettings Theme

在 `SessionBadgeStyle.resolvedColors(...)` 中保留现有分支结构，但增加更细的判断：

- 如果 `badge.accentState != nil`
- 且 `appearance == .notch`
- 且 `badge.tone == .status`

则基础色改为：

```swift
AppSettings.shared.nsColor(for: state)
```

这样 notch status badge 会跟随：

- 默认主题
- 预设主题
- 自定义 running / awaiting / idle 颜色

### 3. Preserve Existing Notch-Specific Non-Status Colors

以下内容保持不变：

- `client` badge 的 notch 中性色
- `manager` badge 的 notch 中性色
- `origin` badge 的 notch 中性色
- `neutral` badge 的 notch 中性色

这能保证 notch 视觉依然以参考分支的深色语言为主，只在真正代表 Session 状态的 badge 上复用外观主题色。

## File Map

- Modify: `Sources/VibeBarApp/SessionBadgeView.swift`
- Test: `Tests/VibeBarAppTests/SessionBadgeStyleTests.swift`

## Validation

完成后应满足：

1. notch 下拉框里的“运行中 / 等待输入 / 空闲 + 时长”badge 跟随“设置 -> 外观”的状态主题色。
2. 普通菜单中的 badge 行为保持原有 `.standard` 逻辑。
3. notch 的非状态 badge 仍保留当前独立中性色。
4. `swift build --target VibeBarApp` 与 `swift test --filter SessionBadgeStyleTests` 通过。

## Notes

本设计不创建 commit。若后续需要提交，由用户显式请求后再执行。
