# Session Runtime In Menu Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在下拉菜单的 session 列表中显示每个 session 的运行时间，并保证不同检测来源下的数据口径可解释。

**Architecture:** 运行时间统一定义为 `max(0, now - startedAt)`。先修复 `processScan` 来源的 `startedAt` 精度（从 `ps etime` 反推），再在两个菜单渲染入口（SwiftUI `MenuContentView` 与 AppKit `SessionMenuItemView`）统一显示。为避免额外本地化成本，时长文本采用语言无关格式（`mm:ss` / `h:mm:ss` / `d+h`）。

**Tech Stack:** Swift 6.2、AppKit/SwiftUI、VibeBarCore SessionSnapshot、`ps` 命令解析

---

### Task 1: 明确显示规则与边界（需求冻结）

**Files:**
- Modify: `Sources/VibeBarApp/MenuContentView.swift`
- Modify: `Sources/VibeBarApp/StatusItemController.swift`
- Modify: `Sources/VibeBarCore/Models.swift`（仅在需要补充注释时）

**Step 1: 定义时长语义（文档注释级）**

- 运行时间来源：`SessionSnapshot.startedAt`
- 展示对象：session 列表中所有条目（running/awaitingInput/idle/unknown）
- 文本格式：
  - `< 1h`: `mm:ss`
  - `< 24h`: `h:mm:ss`
  - `>= 24h`: `Xd Yh`
- 当 `startedAt` 明显异常（未来时间）时，显示 `00:00`

**Step 2: 冻结 UI 位置**

- SwiftUI 行：右侧状态文本后追加时长（紧凑样式）
- NSMenu 行：第二行 `pid · directory` 改为 `pid · duration · directory`
- 保持现有 `prefix(8)` 上限，不新增交互行为

**Step 3: 手动验收标准（先写）**

Run: `swift run VibeBarApp`
Expected:
- 有 active session 时，时长每秒递增
- 无 active session 时，仍可按当前刷新周期更新（最多 5 秒步进）
- 菜单宽度不出现明显截断/重叠

---

### Task 2: 修复 processScan 来源的 startedAt 精度

**Files:**
- Modify: `Sources/VibeBarCore/ProcessScanner.swift`

**Step 1: 写失败用例（若本轮补测试基础设施）**

建议新增（可选，当前仓库无测试 target）：
- `Tests/VibeBarCoreTests/ProcessScannerElapsedTimeParsingTests.swift`

示例断言：
```swift
XCTAssertEqual(parseElapsed("00:03"), 3)
XCTAssertEqual(parseElapsed("01:02:03"), 3723)
XCTAssertEqual(parseElapsed("02-01:02:03"), 176523)
```

**Step 2: 调整 ps 字段并解析 elapsed**

- 将 `runPS` 输出列从 `pid,ppid,pcpu,comm,args` 调整为 `pid,ppid,pcpu,etime,comm,args`
- Candidate 增加 `elapsedSeconds`
- `startedAt` 改为 `now.addingTimeInterval(-elapsedSeconds)`
- 解析失败时回退 `startedAt = now`

**Step 3: 验证 detector 不回归**

Run: `swift build`
Expected: 编译通过

Run: `swift run vibebar-agent --verbose`（另开窗口触发会话事件）
Expected: 现有检测链行为不变，仅时长更稳定

---

### Task 3: 提取统一时长格式化工具

**Files:**
- Create: `Sources/VibeBarApp/SessionDurationFormatter.swift`
- Modify: `Sources/VibeBarApp/MenuContentView.swift`
- Modify: `Sources/VibeBarApp/StatusItemController.swift`

**Step 1: 新增 formatter（纯函数）**

```swift
import Foundation

enum SessionDurationFormatter {
    static func string(startedAt: Date, now: Date) -> String {
        let raw = max(0, Int(now.timeIntervalSince(startedAt)))
        let day = raw / 86_400
        let hour = (raw % 86_400) / 3_600
        let minute = (raw % 3_600) / 60
        let second = raw % 60
        if day > 0 { return "\(day)d \(hour)h" }
        if raw >= 3_600 { return String(format: "%d:%02d:%02d", hour, minute, second) }
        return String(format: "%02d:%02d", minute, second)
    }
}
```

**Step 2: 接入 SwiftUI 行**

- `MenuContentView.sessionRow` 右侧增加时长文本
- 使用 `.font(.caption2.monospacedDigit())` 防止抖动

**Step 3: 接入 NSMenu 自定义行**

- 在 `SessionMenuItemView` 构造 row2 文本时插入 `duration`
- 字符串形态：`pid 1234 · 03:21 · ~/repo`

---

### Task 4: 菜单刷新与性能校验

**Files:**
- Modify: `Sources/VibeBarApp/AppModel.swift`（仅在需要微调刷新频率时）

**Step 1: 复核刷新机制是否满足实时性**

- 当前 active 1s / idle 5s 已满足时长显示最小需求
- 默认不新增额外 Timer，避免双重刷新

**Step 2: 压测场景手工验证**

Run: `VIBEBAR_DEBUG_DOCK=1 swift run VibeBarApp`
Expected:
- 8 条 session 同时显示时菜单滚动与 hover 无明显卡顿
- 状态颜色、图标、插件区行为无回归

---

### Task 5: 回归检查与文档更新

**Files:**
- Modify: `README_zh.md`（可选：说明 session 行新增时长）
- Modify: `CHANGELOG.md`

**Step 1: 编译回归**

Run: `swift build`
Expected: `Build complete`

**Step 2: 手动功能回归**

Run:
- `swift run VibeBarApp`
- `swift run vibebar codex -- --model gpt-5-codex`
Expected:
- session 行稳定显示时长
- 关闭会话后条目按原有逻辑消失

**Step 3: 提交建议**

```bash
git add Sources/VibeBarCore/ProcessScanner.swift \
        Sources/VibeBarApp/MenuContentView.swift \
        Sources/VibeBarApp/StatusItemController.swift \
        Sources/VibeBarApp/SessionDurationFormatter.swift \
        CHANGELOG.md

git commit -m "feat(menu): show session runtime in dropdown list"
```
