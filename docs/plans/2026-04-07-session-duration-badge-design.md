# Session Duration Badge Design

**Date:** 2026-04-07

**Status:** Confirmed

## Summary

将 session 状态的持续时间移至第一行末尾，终端 badge 左侧。使用胶囊样式 badge，格式为 `状态 时间`（如 `空闲 1h30m`），颜色跟随状态。

## Goals

- 持续时间显示在第一行末尾（终端 badge 左侧）
- 样式与终端 badge 一致（胶囊形状）
- 格式：`状态 + 简化时间`，如 `空闲 1h30m`、`运行中 30m`
- 颜色跟随状态：running=蓝色, idle=灰色, awaitingInput=橙色
- 折叠模式（idle>30min）下也正常显示

## UI Specification

### 显示位置
```
[工具图标] Session 名称xxxxx     [空闲 1h30m] [终端类型]
```

### 格式规则
- `< 1 分钟`: `30s`
- `1 分钟 ~ 1 小时`: `30m` / `45m`
- `1 小时 ~ 24 小时`: `1h30m` / `12h45m`
- `>= 24 小时`: `1d3h` / `5d12h`

### 颜色方案
| 状态 | 背景色 (14% opacity) | 边框色 (28% opacity) | 文字色 |
|------|---------------------|---------------------|--------|
| running | systemBlue 14% | systemBlue 28% | systemBlue |
| idle | secondaryLabel 12% | secondaryLabel 24% | secondaryLabel |
| awaitingInput | systemOrange 16% | systemOrange 30% | systemOrange |

## Implementation

### 1. SessionBadge 扩展
在 `SessionBadge.Kind` 中新增 `.duration`：
```swift
enum Kind: String, Sendable {
    case client
    case tab
    case manager
    case origin
    case tty
    case duration  // 新增
}
```

新增 `SessionBadgeTone.status`：
```swift
enum SessionBadgeTone: String, Sendable {
    case client
    case manager
    case origin
    case neutral
    case status  // 新增 - 颜色跟随状态
}
```

### 2. SessionBadgeStyle 扩展
```swift
static func nsFillColor(for tone: SessionBadgeTone, highlighted: Bool = false) -> NSColor {
    if highlighted { return NSColor.white.withAlphaComponent(0.14) }
    switch tone {
    case .status: 
        return statusColor(for: nil).withAlphaComponent(0.14)  // 运行时确定颜色
    // 现有...
    }
}
```

### 3. Duration Badge 生成
在 `SessionDisplayFormatter.badges()` 中生成：
```swift
static func badges(for session: SessionSnapshot, now: Date) -> [SessionBadge] {
    var badges: [SessionBadge] = []
    
    // 现有 badges...
    
    // Duration badge
    let duration = DurationBadgeFormatter.string(for: session, now: now)
    let statusText = session.status.displayName  // "运行中" / "空闲" / "等待输入"
    badges.append(SessionBadge(
        kind: .duration,
        text: "\(statusText) \(duration)",
        tone: .status
    ))
    
    return badges
}
```

### 4. DurationBadgeFormatter
新建 `DurationBadgeFormatter.swift`：
```swift
enum DurationBadgeFormatter {
    static func string(for session: SessionSnapshot, now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(session.currentStatusSince))
        
        if seconds < 60 {
            return "\(seconds)s"
        }
        
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m"
        }
        
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours < 24 {
            if remainingMinutes > 0 {
                return "\(hours)h\(remainingMinutes)m"
            }
            return "\(hours)h"
        }
        
        let days = hours / 24
        let remainingHours = hours % 24
        if remainingHours > 0 {
            return "\(days)d\(remainingHours)h"
        }
        return "\(days)d"
    }
}
```

### 5. UI 更新
- 移除第二行的 `sessionDuration` 显示
- Badge 顺序调整：duration badge 在 tty badge 左侧

## Files to Modify

- `Sources/VibeBarApp/SessionBadgeView.swift` - 扩展 badge 样式
- `Sources/VibeBarApp/SessionDisplayFormatter.swift` - 生成 duration badge
- `Sources/VibeBarApp/SessionDurationFormatter.swift` - 可选：保留用于其他用途
- `Sources/VibeBarApp/MenuContentView.swift` - 移除第二行 duration
- `Sources/VibeBarApp/NotchContentView.swift` - 移除第二行 duration
- `Sources/VibeBarApp/StatusItemController.swift` - 移除第二行 duration

## Files to Create

- `Sources/VibeBarApp/DurationBadgeFormatter.swift` - 时间格式化为 badge 文本