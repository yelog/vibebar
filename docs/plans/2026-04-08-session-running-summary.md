# Session Running Summary Implementation Plan

**Goal:** 将“最近一次对话”和“当前正在执行的动作”拆成两个独立字段，避免会话列表副文本被重复去重后只剩一行。

**Architecture:** 在 `SessionSnapshot` 中新增 `runningSummary`，插件来源优先产出该字段，UI 改为分别渲染 `lastUserMessage` 与 `runningSummary`。保留 `currentTask` 作为兼容字段，但不再作为列表副文本的直接来源。

**Tech Stack:** Swift 6.2, SwiftUI, Foundation

---

### Task 1: 扩展会话模型

**Files:**
- Modify: `Sources/VibeBarCore/Models.swift`

1. 在 `SessionSnapshot` 中新增 `runningSummary: String?`
2. 更新初始化方法参数与赋值
3. 保持 `Codable` 兼容旧会话文件

### Task 2: 插件会话写入独立运行摘要

**Files:**
- Modify: `Sources/VibeBarAgent/main.swift`

1. 为插件事件新增 `resolveLastUserMessage()`
2. 新增 `resolveRunningSummary()`，仅读取动作类字段
3. 写入/更新 `snapshot.lastUserMessage` 与 `snapshot.runningSummary`
4. `markPendingInteraction()` 继续设置 `currentTask`，同时设置 `runningSummary`

### Task 3: 会话合并逻辑独立处理运行摘要

**Files:**
- Modify: `Sources/VibeBarApp/AppModel.swift`
- Modify: `Sources/VibeBarCore/CompositeSessionDetector.swift`

1. 合并时独立补齐 `runningSummary`
2. 不再让标题、用户消息回退污染 `runningSummary`

### Task 4: 列表 UI 改为显示独立运行摘要

**Files:**
- Modify: `Sources/VibeBarApp/SessionDisplayFormatter.swift`
- Modify: `Sources/VibeBarApp/MenuContentView.swift`

1. 新增 `runningSummaryText()` 供 UI 使用
2. 列表第二行显示 `lastUserMessage`
3. 列表第三行仅在 `runningSummary` 非空且不重复时显示

### Task 5: 基础验证

**Files:**
- None

1. 运行 `swift build`
2. 如有编译错误，修正后重新构建
3. 总结当前阶段已覆盖和未覆盖的来源
