# Session Duration Badge Implementation Plan

> **For Claude:** Use superpowers:subagent-driven_execution to implement this plan task-by-task.

**Goal:** 将 session 状态的持续时间显示为 badge，格式 `状态 时间`，颜色跟随状态，位于第一行末尾（终端 badge 左侧）。

**Architecture:** 复用现有 SessionBadge 系统，新增 `.duration` badge kind 和 `.status` tone。创建 DurationBadgeFormatter 格式化时间字符串。

**Tech Stack:** Swift, SwiftUI, AppKit

---

### Task 1: 扩展 SessionBadge 类型

**Files:**
- Modify: `Sources/VibeBarApp/SessionBadgeView.swift:11-27`

**Step 1: 添加 Kind.duration**

编辑 `SessionBadge.Kind` 枚举，添加 `duration` case：

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

**Step 2: 添加 Tone.status**

编辑 `SessionBadgeTone` 枚举，添加 `status` case：

```swift
enum SessionBadgeTone: String, Sendable {
    case client
    case manager
    case origin
    case neutral
    case status  // 新增 - 颜色跟随状态
}
```

---

### Task 2: 扩展 SessionBadgeStyle 颜色支持

**Files:**
- Modify: `Sources/VibeBarApp/SessionBadgeView.swift:29-92`

**Step 1: 修改 nsFillColor**

在 `SessionBadgeStyle.nsFillColor(for:highlighted:)` 方法中添加 `.status` case。颜色需要根据 session 状态动态确定，但因为 tone 是静态的，我们需要让调用方传入状态。

更好的方案是：`.status` tone 使用通用的次要颜色，然后在生成 badge 时根据状态选择合适的 tone。

编辑 `SessionBadgeStyle`，将 `.status` 的填充色改为与 `.neutral` 相同（灰色），因为颜色会在生成时根据状态决定：

```swift
case .status:
    return NSColor.secondaryLabelColor.withAlphaComponent(0.12)
```

**Step 2: 修改 nsBorderColor**

同样为 `.status` 添加：

```swift
case .status:
    return NSColor.secondaryLabelColor.withAlphaComponent(0.24)
```

**Step 3: 修改 nsTextColor**

同样为 `.status` 添加：

```swift
case .status:
    return NSColor.secondaryLabelColor
```

---

### Task 3: 创建 DurationBadgeFormatter

**Files:**
- Create: `Sources/VibeBarApp/DurationBadgeFormatter.swift`

**Step 1: 写入文件**

```swift
import Foundation
import VibeBarCore

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

---

### Task 4: 修改 SessionDisplayFormatter 生成 Duration Badge

**Files:**
- Modify: `Sources/VibeBarApp/SessionDisplayFormatter.swift:63-85`

**Step 1: 修改 badges 方法签名**

添加 `now` 参数：

```swift
static func badges(for session: SessionSnapshot, now: Date) -> [SessionBadge] {
```

**Step 2: 添加 duration badge 生成**

在方法末尾添加：

```swift
// Duration badge
let duration = DurationBadgeFormatter.string(for: session, now: now)
let statusText = session.status.displayName
let statusTone = toneForStatus(session.status)

badges.append(SessionBadge(
    kind: .duration,
    text: "\(statusText) \(duration)",
    tone: statusTone
))

return badges
```

**Step 3: 添加 toneForStatus 辅助方法**

在文件末尾添加：

```swift
private static func toneForStatus(_ status: ToolActivityState) -> SessionBadgeTone {
    switch status {
    case .running:
        return .client  // 使用蓝色
    case .idle:
        return .neutral  // 使用灰色
    case .awaitingInput:
        return .origin  // 使用橙色
    case .unknown:
        return .neutral
    }
}
```

---

### Task 5: 更新 MenuContentView 调用

**Files:**
- Modify: `Sources/VibeBarApp/MenuContentView.swift:184-231`

**Step 1: 更新 badges 调用**

找到调用 `SessionDisplayFormatter.badges(for: session)` 的地方，添加 `now` 参数：

```swift
let badges = SessionDisplayFormatter.badges(for: session, now: model.summary.updatedAt)
```

**Step 2: 移除第二行的 duration 显示**

找到第二行中的 `sessionDuration(for: session)` 调用并删除：

删除这部分：
```swift
Text(sessionDuration(for: session))
    .font(.caption2.monospacedDigit())
    .foregroundStyle(.secondary)
```

---

### Task 6: 更新 NotchContentView 调用

**Files:**
- Modify: `Sources/VibeBarApp/NotchContentView.swift:248-282`

**Step 1: 更新 badges 调用**

找到调用 `SessionDisplayFormatter.badges(for: session)` 的地方，添加 `now` 参数：

```swift
let badges = SessionDisplayFormatter.badges(for: session, now: model.summary.updatedAt)
```

**Step 2: 移除第二行的 duration 显示**

找到第二行中的 `sessionDuration(for: session)` 调用并删除。

---

### Task 7: 更新 StatusItemController (AppKit 菜单)

**Files:**
- Modify: `Sources/VibeBarApp/StatusItemController.swift:2249-2251`

**Step 1: 更新 badges 调用**

找到 `SessionDisplayFormatter.badges(for: session)` 调用，添加 `now` 参数：

```swift
let badges = SessionDisplayFormatter.badges(for: session, now: now)
```

**Step 2: 移除第二行的 duration 显示**

在 `SessionMenuItemView` 初始化中，找到 `sessionDuration` 相关代码并移除。

---

### Task 8: 编译验证

**Step 1: 编译项目**

运行：
```bash
swift build
```

预期：编译成功，无错误。

---

### Task 9: 手动测试

**Step 1: 运行 VibeBarApp**

```bash
swift run VibeBarApp
```

**Step 2: 验证 UI**

1. 打开菜单栏 dropdown
2. 确认每个 session 第一行末尾显示 duration badge（如 `空闲 1h30m`）
3. 确认颜色正确：running=蓝, idle=灰, awaitingInput=橙
4. 确认折叠模式下也显示 duration badge

---

## 总结

本计划共 9 个任务：
- Task 1-2: 扩展 SessionBadge 类型和样式
- Task 3: 创建 DurationBadgeFormatter
- Task 4: 修改 SessionDisplayFormatter 生成 badge
- Task 5-7: 更新三个 UI 入口（MenuContentView, NotchContentView, StatusItemController）
- Task 8-9: 编译和测试