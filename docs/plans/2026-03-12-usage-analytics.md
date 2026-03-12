# Usage Analytics Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 为 VibeBar 增加多来源 token usage / 估算价值统计能力，并在设置页与菜单栏中提供可配置的可视化展示，同时将插件管理从菜单栏移除。

**Architecture:** 在 `VibeBarCore` 中新增 usage 领域模型、来源 loader、聚合器、价格解析器与快照缓存；在 `VibeBarApp` 中新增独立 `UsageMonitorViewModel`、设置页 `Usage` tab 与菜单 usage 模块。usage 刷新链路与现有 session 刷新链路解耦，默认按 5 分钟异步刷新。

**Tech Stack:** Swift 6.2、SwiftUI、AppKit、Charts、Foundation、UserDefaults、VibeBarCore

---

### Task 1: 补最小测试基础设施

**Files:**
- Modify: `/Users/yelog/workspace/swift/VibeBar/Package.swift`
- Create: `/Users/yelog/workspace/swift/VibeBar/Tests/VibeBarCoreTests/UsageAggregationTests.swift`
- Create: `/Users/yelog/workspace/swift/VibeBar/Tests/VibeBarCoreTests/UsageLoaderFixtureTests.swift`

**Step 1: 写失败测试**

为未来 usage 模块预留最小测试目标，先写一个会失败的占位测试：

```swift
import Testing
@testable import VibeBarCore

@Test func usageAggregationPlaceholder() throws {
    #expect(false)
}
```

**Step 2: 运行测试确认失败**

Run: `swift test --filter usageAggregationPlaceholder`
Expected: FAIL，提示断言失败或目标未配置。

**Step 3: 配置最小测试 target**

在 `Package.swift` 中新增 `testTarget(name: "VibeBarCoreTests", dependencies: ["VibeBarCore"])`，并保证测试目标可编译。

**Step 4: 运行测试确认可执行**

Run: `swift test`
Expected: 测试目标被发现，当前占位测试失败。

**Step 5: Commit**

```bash
git add Package.swift Tests/VibeBarCoreTests
git commit -m "test(core): add usage test target scaffold"
```

### Task 2: 建立 usage 领域模型与设置枚举

**Files:**
- Create: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/UsageModels.swift`
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/AppSettings.swift`
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/L10nStrings.swift`

**Step 1: 写失败测试**

在 `UsageAggregationTests.swift` 中增加对枚举默认值与快照解码的测试：

```swift
@Test func usageSettingsDefaultsDecode() throws {
    let snapshot = UsageSnapshot.empty
    #expect(snapshot.totalTokens == 0)
}
```

**Step 2: 运行测试确认失败**

Run: `swift test --filter usageSettingsDefaultsDecode`
Expected: FAIL，提示 `UsageSnapshot` 未定义。

**Step 3: 写最小实现**

新增：

- `UsageSource`
- `UsageMetric`
- `UsageVisualizationStyle`
- `UsageGranularity`
- `UsageSeriesGrouping`
- `UsageRefreshCadence`
- `UsageEvent`
- `UsageBucket`
- `UsageSeries`
- `UsageSnapshot`

并在 `AppSettings` 中增加 usage 相关持久化字段。

**Step 4: 运行测试确认通过**

Run: `swift test --filter usageSettingsDefaultsDecode`
Expected: PASS。

**Step 5: Commit**

```bash
git add Sources/VibeBarCore/UsageModels.swift Sources/VibeBarApp/AppSettings.swift Sources/VibeBarCore/L10nStrings.swift Tests/VibeBarCoreTests
git commit -m "feat(usage): add usage models and settings enums"
```

### Task 3: 建立 usage 缓存路径与快照存储

**Files:**
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/Paths.swift`
- Create: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/UsageSnapshotStore.swift`
- Modify: `/Users/yelog/workspace/swift/VibeBar/Tests/VibeBarCoreTests/UsageLoaderFixtureTests.swift`

**Step 1: 写失败测试**

```swift
@Test func usageSnapshotStoreRoundTrips() throws {
    let store = UsageSnapshotStore(baseURL: FileManager.default.temporaryDirectory)
    try store.write(.empty)
    let loaded = try store.load()
    #expect(loaded.totalTokens == 0)
}
```

**Step 2: 运行测试确认失败**

Run: `swift test --filter usageSnapshotStoreRoundTrips`
Expected: FAIL，提示 `UsageSnapshotStore` 未定义。

**Step 3: 写最小实现**

- 在 `VibeBarPaths` 增加 `usageDirectory`
- 实现 `UsageSnapshotStore`
- 使用原子写入

**Step 4: 运行测试确认通过**

Run: `swift test --filter usageSnapshotStoreRoundTrips`
Expected: PASS。

**Step 5: Commit**

```bash
git add Sources/VibeBarCore/Paths.swift Sources/VibeBarCore/UsageSnapshotStore.swift Tests/VibeBarCoreTests
git commit -m "feat(usage): add usage snapshot storage"
```

### Task 4: 实现 Claude usage loader

**Files:**
- Create: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/ClaudeUsageLoader.swift`
- Modify: `/Users/yelog/workspace/swift/VibeBar/Tests/VibeBarCoreTests/UsageLoaderFixtureTests.swift`

**Step 1: 写失败测试**

使用最小 JSONL fixture 覆盖：

- `~/.config/claude/projects`
- `~/.claude/projects`
- 自带 `costUSD`
- cache token 字段

```swift
@Test func claudeLoaderParsesUsageEntries() async throws {
    let loader = ClaudeUsageLoader(searchRoots: [fixtureRoot])
    let result = try await loader.load()
    #expect(result.events.count == 2)
}
```

**Step 2: 运行测试确认失败**

Run: `swift test --filter claudeLoaderParsesUsageEntries`
Expected: FAIL。

**Step 3: 写最小实现**

- 解析 Claude JSONL usage 数据
- 兼容 XDG 与旧目录
- 产出 `UsageEvent`

**Step 4: 运行测试确认通过**

Run: `swift test --filter claudeLoaderParsesUsageEntries`
Expected: PASS。

**Step 5: Commit**

```bash
git add Sources/VibeBarCore/ClaudeUsageLoader.swift Tests/VibeBarCoreTests/UsageLoaderFixtureTests.swift
git commit -m "feat(usage): add Claude usage loader"
```

### Task 5: 实现 Codex usage loader

**Files:**
- Create: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/CodexUsageLoader.swift`
- Modify: `/Users/yelog/workspace/swift/VibeBar/Tests/VibeBarCoreTests/UsageLoaderFixtureTests.swift`

**Step 1: 写失败测试**

覆盖：

- `~/.codex/sessions/**/*.jsonl`
- `turn_context` 中 model
- `token_count` 累积值转增量

```swift
@Test func codexLoaderBuildsDeltaEvents() async throws {
    let loader = CodexUsageLoader(baseDirectory: fixtureRoot)
    let result = try await loader.load()
    #expect(result.events.count == 2)
    #expect(result.events[1].totalTokens > 0)
}
```

**Step 2: 运行测试确认失败**

Run: `swift test --filter codexLoaderBuildsDeltaEvents`
Expected: FAIL。

**Step 3: 写最小实现**

- 解析 Codex JSONL
- 从累计 token 转为 delta
- 缺 model 时按 `gpt-5` fallback 并标记估算来源

**Step 4: 运行测试确认通过**

Run: `swift test --filter codexLoaderBuildsDeltaEvents`
Expected: PASS。

**Step 5: Commit**

```bash
git add Sources/VibeBarCore/CodexUsageLoader.swift Tests/VibeBarCoreTests/UsageLoaderFixtureTests.swift
git commit -m "feat(usage): add Codex usage loader"
```

### Task 6: 实现 OpenCode usage loader

**Files:**
- Create: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/OpenCodeUsageLoader.swift`
- Modify: `/Users/yelog/workspace/swift/VibeBar/Tests/VibeBarCoreTests/UsageLoaderFixtureTests.swift`

**Step 1: 写失败测试**

覆盖：

- `storage/message/**/*.json`
- `tokens.input/output/cache`
- `cost = 0` 时保留为空等待估算

```swift
@Test func opencodeLoaderParsesMessageFiles() async throws {
    let loader = OpenCodeUsageLoader(baseDirectory: fixtureRoot)
    let result = try await loader.load()
    #expect(result.events.count == 1)
    #expect(result.events[0].modelName == "claude-sonnet-4-5")
}
```

**Step 2: 运行测试确认失败**

Run: `swift test --filter opencodeLoaderParsesMessageFiles`
Expected: FAIL。

**Step 3: 写最小实现**

- 扫描 `storage/message`
- 解析 message JSON
- 映射为 `UsageEvent`

**Step 4: 运行测试确认通过**

Run: `swift test --filter opencodeLoaderParsesMessageFiles`
Expected: PASS。

**Step 5: Commit**

```bash
git add Sources/VibeBarCore/OpenCodeUsageLoader.swift Tests/VibeBarCoreTests/UsageLoaderFixtureTests.swift
git commit -m "feat(usage): add OpenCode usage loader"
```

### Task 7: 实现价格解析与聚合器

**Files:**
- Create: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/UsagePricingResolver.swift`
- Create: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/UsageAggregation.swift`
- Modify: `/Users/yelog/workspace/swift/VibeBar/Tests/VibeBarCoreTests/UsageAggregationTests.swift`

**Step 1: 写失败测试**

覆盖：

- 日/周/月聚合
- `metric = tokens / cost`
- `grouping = total / agent / model`
- unknown model 返回 0 cost

```swift
@Test func usageAggregatorGroupsByDayAndModel() async throws {
    let snapshot = try await UsageAggregator().build(from: sampleEvents, configuration: sampleConfig)
    #expect(snapshot.buckets.isEmpty == false)
    #expect(snapshot.series.count == 2)
}
```

**Step 2: 运行测试确认失败**

Run: `swift test --filter usageAggregatorGroupsByDayAndModel`
Expected: FAIL。

**Step 3: 写最小实现**

- `UsagePricingResolver`
- `UsageAggregator`
- 热力图 bucket 计算
- `Top N + Others` model 分组策略

**Step 4: 运行测试确认通过**

Run: `swift test --filter usageAggregatorGroupsByDayAndModel`
Expected: PASS。

**Step 5: Commit**

```bash
git add Sources/VibeBarCore/UsagePricingResolver.swift Sources/VibeBarCore/UsageAggregation.swift Tests/VibeBarCoreTests/UsageAggregationTests.swift
git commit -m "feat(usage): add pricing resolver and aggregator"
```

### Task 8: 实现独立的 usage 刷新 view model

**Files:**
- Create: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/UsageMonitorViewModel.swift`
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/AppDelegate.swift`

**Step 1: 写失败测试或验收标准**

由于 App 层暂不易自动化，先写明确行为：

- 默认 5 分钟调度
- 主线程只发布结果
- 刷新未结束时合并为 pending
- 启动后优先加载 cache，再后台刷新

**Step 2: 运行构建确认当前尚未接入**

Run: `swift build`
Expected: PASS，但还没有 usage monitor。

**Step 3: 写最小实现**

- 新增 `UsageMonitorViewModel.shared`
- 异步调用三个 loader + 聚合器
- 读写 `UsageSnapshotStore`
- 跟随 `AppSettings` 的 cadence 和 visualization 配置刷新

**Step 4: 运行构建确认通过**

Run: `swift build`
Expected: PASS。

**Step 5: Commit**

```bash
git add Sources/VibeBarApp/UsageMonitorViewModel.swift Sources/VibeBarApp/AppDelegate.swift
git commit -m "feat(app): add background usage monitor"
```

### Task 9: 增加 Usage tab 与设置界面

**Files:**
- Create: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/UsageSettingsView.swift`
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/SettingsView.swift`
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/SettingsWindowController.swift`
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/L10nStrings.swift`

**Step 1: 写失败验收标准**

- 新 tab 顺序为 `General / CLI / Appearance / Usage / About`
- `Cmd+4` 对应 Usage，`Cmd+5` 对应 About
- 切换到 Usage 时窗口尺寸适配图表内容

**Step 2: 运行应用确认当前无该入口**

Run: `swift run VibeBarApp`
Expected: 当前没有 `Usage` tab。

**Step 3: 写最小实现**

- 扩展 `SettingsTab`
- 新增 `UsageSettingsView`
- 配置 sources、refresh cadence、style、metric、granularity、grouping
- 增加图表预览

**Step 4: 运行应用确认通过**

Run: `swift run VibeBarApp`
Expected: 可看到 `Usage` tab，切换正常。

**Step 5: Commit**

```bash
git add Sources/VibeBarApp/UsageSettingsView.swift Sources/VibeBarApp/SettingsView.swift Sources/VibeBarApp/SettingsWindowController.swift Sources/VibeBarCore/L10nStrings.swift
git commit -m "feat(settings): add usage settings tab"
```

### Task 10: 实现热力图、柱状图、折线图视图

**Files:**
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/UsageSettingsView.swift`
- Create: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/UsageHeatmapView.swift`
- Create: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/UsageBarChartView.swift`
- Create: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/UsageLineChartView.swift`

**Step 1: 写失败验收标准**

- GitHub 热力图只展示 token
- 柱状图支持 day/week/month + token/USD + stack by agent/model
- 折线图支持 day/week/month + token/USD + split by agent/model

**Step 2: 运行应用观察当前 preview 为空或占位**

Run: `swift run VibeBarApp`
Expected: 当前 preview 还未完整实现。

**Step 3: 写最小实现**

- 使用 `Charts` 实现 bar/line
- 使用自绘网格实现 heatmap
- 添加空状态与无数据提示

**Step 4: 运行应用确认通过**

Run: `swift run VibeBarApp`
Expected: 三种图表能随配置变化。

**Step 5: Commit**

```bash
git add Sources/VibeBarApp/UsageSettingsView.swift Sources/VibeBarApp/UsageHeatmapView.swift Sources/VibeBarApp/UsageBarChartView.swift Sources/VibeBarApp/UsageLineChartView.swift
git commit -m "feat(usage): add usage visualizations"
```

### Task 11: 替换菜单插件管理区为 usage 模块

**Files:**
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/StatusItemController.swift`

**Step 1: 写失败验收标准**

- 菜单不再显示插件管理区
- 菜单显示 usage 模块
- 点击 usage 模块跳转 `Settings > Usage`
- wrapper 管理入口也不再出现在菜单

**Step 2: 运行应用确认当前菜单仍有插件区**

Run: `swift run VibeBarApp`
Expected: 当前菜单仍显示 plugin 状态区。

**Step 3: 写最小实现**

- 删除 `rebuildMenuItems()` 中 plugin/wrapper 管理区构建逻辑
- 增加 usage 模块
- 新增 `onUsageSettings()` 或等价跳转
- 菜单仅保留结果展示，不提供配置动作

**Step 4: 运行应用确认通过**

Run: `swift run VibeBarApp`
Expected: 菜单显示 usage 模块，点击可进入 Usage tab。

**Step 5: Commit**

```bash
git add Sources/VibeBarApp/StatusItemController.swift
git commit -m "feat(menu): replace plugin section with usage module"
```

### Task 12: 清理设置页内重复插件管理实现并做回归

**Files:**
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/CLISettingsView.swift`
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/SettingsView.swift`
- Modify: `/Users/yelog/workspace/swift/VibeBar/CHANGELOG.md`

**Step 1: 写失败验收标准**

- 插件管理只剩设置页一处明确入口
- 没有悬空未使用的旧 plugin UI 代码
- 编译与基本手动回归通过

**Step 2: 运行构建与测试**

Run: `swift build`
Expected: PASS。

Run: `swift test`
Expected: PASS。

**Step 3: 写最小实现**

- 清理菜单移除后不再使用的插件 UI 辅助代码
- 确保 CLI 设置页仍是插件管理唯一入口
- 更新 `CHANGELOG.md`

**Step 4: 运行最终回归**

Run: `swift run VibeBarApp`
Expected:
- `Usage` tab 可配置
- 菜单 usage 模块渲染正常
- 插件管理只在设置页
- 菜单打开无明显卡顿

**Step 5: Commit**

```bash
git add Sources/VibeBarApp/CLISettingsView.swift Sources/VibeBarApp/SettingsView.swift CHANGELOG.md
git commit -m "refactor(settings): consolidate plugin management and finalize usage feature"
```
