# Usage Analytics Design

**Date:** 2026-03-12

**Status:** Confirmed

## Summary

本次设计覆盖四个变更：

1. 从下拉菜单移除插件管理入口，只在设置界面管理插件与 wrapper。
2. 新增 token usage / 价值统计能力，数据解析逻辑参考 `ccusage` 家族，但不引入 Node 运行时依赖。
3. 在设置页 `About` 左侧新增 `Usage` tab，用于配置 usage 数据来源、刷新频率与展示样式。
4. 在下拉菜单新增 `Usage` 模块，根据设置展示 token usage 统计，并支持点击跳转到设置页 `Usage` tab。

## Goals

- 保持 VibeBar 纯 Swift 原生实现，不依赖外部 `ccusage` CLI。
- 支持默认数据源：`Claude Code`、`Codex`、`OpenCode`。
- 支持三种展示方式：
  - GitHub contributions 风格热力图，仅展示 token 数量。
  - 柱状图，可切换天/周/月，可切换 token/金额，可按 agent/model 分组堆叠。
  - 折线图，可切换天/周/月，可切换 token/金额，可按 agent/model 分组多折线。
- 将 usage 刷新链路与现有 session 检测链路解耦，避免功耗回退。

## Non-Goals

- 首版不直接复刻 `ccusage` 的 `session`、`blocks`、`statusline` 等全部命令能力。
- 首版不依赖 npm、bun、deno 或外部 CLI 安装。
- 首版不开放自定义数据目录，仅使用各工具默认目录和环境变量约定。

## Current State

- 设置页 tab 由 [SettingsView.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/SettingsView.swift) 中的 `SettingsTab` 管理，目前只有 `general / cli / appearance / about`。
- 设置窗口尺寸逻辑分散在 [SettingsView.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/SettingsView.swift) 与 [SettingsWindowController.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/SettingsWindowController.swift)。
- 菜单栏下拉内容由 [StatusItemController.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/StatusItemController.swift) 的 AppKit 菜单构建，不是 SwiftUI 的 [MenuContentView.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/MenuContentView.swift)。
- 插件安装/卸载/更新逻辑集中在 [AppModel.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/AppModel.swift)，但菜单栏与设置页都有管理入口。

## Product Decisions

### Plugin Management

- 下拉菜单不再提供插件与 wrapper 的安装、更新、卸载操作。
- 插件与 wrapper 的管理能力保留在设置页。
- 菜单中保留 `Settings` 入口，由用户进入设置后完成管理。

### Usage Value

- “价值”统一定义为 `USD 估算金额`。
- 若源数据自带金额，则直接使用。
- 若源数据不带金额，则根据 model pricing 按 tokens 估算。
- UI 文案中需明确这是估算值，避免被误解为账单结算金额。

### Scope of Data Sources

- 默认支持：
  - Claude Code
  - Codex
  - OpenCode
- 首版不加入 Aider / Gemini / GitHub Copilot usage 统计。
- 首版只扫描默认路径和工具约定环境变量，不提供自定义目录 UI。

### Grouping Strategy

- `seriesGrouping` 支持：
  - `total`
  - `agent`
  - `model`
- 当按 `model` 分组时，图例与序列采用 `Top N + Others` 策略，避免菜单和设置页图表不可读。

## Chosen Architecture

采用“多源 loader + 归一化事件 + 聚合器 + 快照缓存 + 独立 view model”的原生 Swift 方案。

### Core Models

新增一组 usage 领域模型，放在 `VibeBarCore`：

- `UsageSource`
- `UsageMetric`
- `UsageVisualizationStyle`
- `UsageGranularity`
- `UsageSeriesGrouping`
- `UsageEvent`
- `UsageBucket`
- `UsageSeries`
- `UsageSnapshot`
- `UsageRefreshCadence`

其中 `UsageEvent` 是归一化输入，至少包含：

- `source`
- `timestamp`
- `sessionID`
- `modelName`
- `inputTokens`
- `outputTokens`
- `cacheReadTokens`
- `cacheWriteTokens`
- `totalTokens`
- `costUSD`

### Loaders

为每个来源实现独立 loader：

- `ClaudeUsageLoader`
  - 目录参考 `ccusage`
  - 优先扫描 `~/.config/claude/projects`
  - 兼容 `~/.claude/projects`
- `CodexUsageLoader`
  - 扫描 `CODEX_HOME/sessions/**/*.jsonl`
  - 默认 `CODEX_HOME = ~/.codex`
- `OpenCodeUsageLoader`
  - 扫描 `OPENCODE_DATA_DIR/storage/message/**/*.json`
  - 默认 `OPENCODE_DATA_DIR = ~/.local/share/opencode`

每个 loader 只负责：

- 查找数据目录
- 解析日志/消息文件
- 归一化为 `UsageEvent`
- 返回解析错误和缺失目录信息

### Pricing

新增 `UsagePricingResolver`，采用 `auto` 策略：

- 若 `UsageEvent.costUSD` 非空且大于 0，直接使用。
- 否则按 model pricing 估算。
- pricing 查询应有 TTL 缓存，默认 5 分钟。
- 未知 model 默认按 0 成本处理，并记录 warning。

### Aggregation

新增 `UsageAggregator`，负责：

- 将 `UsageEvent` 按天/周/月聚合为 `UsageBucket`
- 按 `total / agent / model` 生成图表序列
- 输出菜单和设置页都能消费的 `UsageSnapshot`
- 热力图固定按日粒度计算 token 使用量

### Persistence and Cache

新增本地快照存储，例如：

- `~/Library/Application Support/VibeBar/usage/summary.json`
- `~/Library/Application Support/VibeBar/usage/cache.json`

缓存内容包括：

- 最近一次聚合后的 `UsageSnapshot`
- pricing cache
- 各数据源增量扫描信息，例如文件修改时间、已处理偏移量或指纹

### Refresh Model

新增独立的 `UsageMonitorViewModel`，不要复用现有 `MonitorViewModel` 的 session 检测 timer。

要求：

- 后台异步刷新
- 默认每 5 分钟刷新一次
- 菜单关闭时只更新快照，不重建菜单
- 刷新中若再次触发，合并为一次 pending refresh
- 不阻塞主线程

## UI Design

### Settings

新增 `Usage` tab，放在 `About` 左边。

推荐顺序：

- General
- CLI
- Appearance
- Usage
- About

`Usage` tab 内容分为四个 section：

1. Data Sources
   - 多选项：Claude Code / Codex / OpenCode
2. Refresh
   - cadence picker，默认 5 分钟
3. Visualization
   - 样式：GitHub / 柱状图 / 折线图
   - 指标：Tokens / Estimated USD
   - 粒度：Day / Week / Month
   - 分组：Total / Agent / Model
4. Preview
   - 实时预览当前设置对应的 usage 图形

### Menu

下拉菜单中移除现有插件状态区，替换为 `Usage` 模块。

模块行为：

- 显示当前配置对应的紧凑统计图
- 标题显示 `Usage`
- 副信息显示当前 metric 与时间粒度
- 点击后跳转 `Settings > Usage`

菜单不需要承载完整配置能力，只承载：

- 结果预览
- 跳转入口

### Visualization Rules

#### GitHub Heatmap

- 仅显示 token 数量，不显示金额。
- 固定使用日粒度。
- 固定展示最近 52 周。
- 使用量越高颜色越深。

#### Bar Chart

- 支持 day / week / month
- 支持 metric: tokens / estimated USD
- 支持按 agent 堆叠
- 支持按 model 堆叠

#### Line Chart

- 支持 day / week / month
- 支持 metric: tokens / estimated USD
- 支持按 agent 多折线
- 支持按 model 多折线

## Performance Constraints

由于仓库已有功耗优化要求，本功能必须遵守以下约束：

- 不把 usage 统计加入当前 session 的 2s/10s/15s 检测链路。
- 不在菜单打开时做全量磁盘扫描。
- 不在主线程上解析 JSONL / JSON。
- 首版即实现增量或半增量缓存，避免每 5 分钟全量扫描大目录。
- 菜单关闭时不因为 usage 更新而重建整个 `NSMenu`。

## Error Handling

- 数据目录不存在时，不报错中断，只在 Usage UI 中显示“未检测到数据”。
- 单个坏文件解析失败时跳过并记录日志。
- 未知 model 无价格时，成本按 0 处理，并标记估算不完整。
- 任何一个 source 出错，不影响其他 source 聚合。

## Testing Strategy

首版应补最小化自动测试，至少覆盖 `VibeBarCore`：

- Claude loader 对 JSONL 的解析
- Codex loader 对 JSONL 的解析
- OpenCode loader 对 message JSON 的解析
- UsageAggregator 的天/周/月聚合
- 按 agent / model 分组结果
- unknown model 的价格回退
- 热力图 bucket 映射

App 层以手工验证为主：

- 设置页切换不同样式是否正确预览
- 菜单点击跳转 `Usage` tab
- 删除插件管理区后菜单结构是否正确
- 大目录场景下菜单打开是否仍然流畅

## Rollout Plan

推荐分三阶段：

1. 数据层与缓存
2. 设置页与图表
3. 菜单替换与联调

## Confirmed Assumptions

- “价值”统一按 `USD 估算` 展示。
- 菜单中的 wrapper 管理入口也一并移除，只保留设置页管理。
- 首版只支持默认路径，不做自定义数据目录。
- 按 model 分组时采用 `Top N + Others`。
