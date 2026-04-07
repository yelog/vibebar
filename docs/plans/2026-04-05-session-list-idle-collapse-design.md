# Session List Idle Collapse Design

**Date:** 2026-04-05

**Status:** Confirmed

## Summary

本次设计调整 session 下拉列表的两条规则：

1. session 继续按最近变化时间倒序排列。
2. 只有进入 `idle` 之后持续超过 30 分钟的 session 才自动折叠为单行。

这里的关键点是把“排序时间”和“idle 持续时间”拆开处理。现有 `updatedAt` 适合继续作为排序键，但不适合直接判断“空闲了多久”，因为多个来源会在 idle 期间持续刷新它。

## Goals

- 明确 session 列表排序语义：按 `updatedAt` 从大到小。
- 分组模式下，组内 session 也显式按 `updatedAt` 从大到小排序。
- 为 session 增加稳定的 `idleSince` 语义，用来判断 idle 是否超过 30 分钟。
- notch 展开面板和原生菜单使用同一套折叠规则。
- 折叠后的 session 只显示“Session 名称 + 终端类型 badge”的第一行。

## Non-Goals

- 本次不改变 group header 的顺序，仍按 `ToolKind.allCases` 展示。
- 本次不折叠 `running`、`awaitingInput`、`unknown` 状态的 session。
- 本次不新增用户设置项，折叠阈值固定为 30 分钟。
- 本次不重构 session summary 聚合逻辑，只调整列表展示相关链路。

## Current State

- 全量 session 在 [`MonitorViewModel`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/AppModel.swift) 中已经按 `updatedAt` 倒序排序。
- 分组视图会先按 tool 分桶，再直接使用输入数组顺序，因此组内排序目前只是“隐式继承”全局顺序，而不是显式规则。
- notch 的 [`sessionRow`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/NotchContentView.swift) 和原生菜单的 [`SessionMenuItemView`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/StatusItemController.swift) 都固定渲染三行。
- `updatedAt` 在不同来源中的含义并不一致：
  - wrapper 会持续写快照，即使已经进入 `idle`，`updatedAt` 仍会继续刷新。
  - Claude / Gemini transcript 检测会在每次扫描时把 `updatedAt` 写成当前时间。
  - 插件和 agent 路径的 `updatedAt` 更接近事件时间，但也不等价于“进入 idle 的时间”。

## Chosen Approach

采用“`updatedAt` 负责排序，`idleSince` 负责折叠”的双时间字段方案。

### Data Model

在 [`SessionSnapshot`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/Models.swift) 中新增：

- `idleSince: Date?`

语义如下：

- 当前状态不是 `idle` 时，`idleSince == nil`
- 当前状态是 `idle` 时，`idleSince` 表示“本次进入 idle 的起点”
- 当 session 从 `idle` 恢复为 `running` / `awaitingInput` / `unknown` 时，清空 `idleSince`

由于字段是可选值，本次不需要升级 envelope version；旧文件解码后自然得到 `nil`。

### Sorting

排序规则不变，但要从“现状正确”升级为“显式正确”：

- 全局列表：按 `updatedAt desc, pid asc`
- 分组列表：
  - group 顺序仍按 `ToolKind.allCases`
  - group 内 session 显式按 `updatedAt desc, pid asc`

这样可以避免后续有别的调用方传入未排序数组时，组内顺序 silently 漂移。

### Idle Timestamp Semantics

#### Wrapper / Agent Event Sources

这些来源最适合记录真实状态迁移边界：

- 从非 idle 切到 idle：设置 `idleSince = now`
- 保持 idle：保留已有 `idleSince`
- 切回 running / awaitingInput / unknown：清空 `idleSince`

这适用于：

- [`VibeBarCLI`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCLI/main.swift)
- [`VibeBarAgent`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarAgent/main.swift)
- 本地交互 resolve 后的内存回写路径

#### Transcript / Session-File Sources

这些来源通常不是事件驱动，而是通过“当前状态 + 最近活动时间”推导：

- `CodexSessionDetector`：
  - 当状态为 `idle` 时，`idleSince` 使用 rollout 的最近 activity 时间
- `ClaudeTranscriptDetector` / `GeminiTranscriptDetector`：
  - 当状态为 `idle` 时，`idleSince` 使用 `lastOutputAt ?? lastInputAt`
- `OpenCodeHTTPDetector`：
  - 当状态为 `idle` 时，优先使用 HTTP API 返回的 session `updated` 时间

#### Process Scan Fallback

`processScan` 路径没有可靠的“何时进入 idle”信息，因此：

- 可继续产出 `status == .idle`
- 但 `idleSince = nil`
- 这类 session 不自动折叠

这是保守策略，优先避免误折叠。

### Merge Rules

[`MonitorViewModel.mergeDetectedDetails`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/AppModel.swift) 需要补充 `idleSince` 合并语义：

- 如果 file-backed session 已有可靠 `idleSince`，而 detector 没有更好的值，则保留原值
- 如果 detector 能提供更准确的 `idleSince`，则允许回填
- 当 hydrated interaction 把 session 强制提升为 `awaitingInput` 时，必须清空 `idleSince`
- 本地 resolve interaction 后把状态恢复到 `running` 时，也必须清空 `idleSince`

## Presentation Layer

建议在 App 层新增共享 presentation helper，例如：

- `SessionListPresentation`

职责：

- 统一排序函数
- 统一按 tool 分组
- 统一 `isCondensed(session:now:)` 判断

这样 notch 和原生菜单不需要各自复制“30 分钟 idle 折叠”逻辑。

## UI Behavior

### Condensed Rule

只有满足以下条件时才折叠：

```swift
session.status == .idle &&
session.idleSince != nil &&
now.timeIntervalSince(session.idleSince!) > 30 * 60
```

### Condensed Layout

折叠后只保留第一行：

- Session 名称
- terminal / origin / session manager badge

不再显示：

- 第二行：状态、时长、secondary text
- 第三行：目录

### UI Surfaces

需要同时覆盖两条实际展示路径：

- [`NotchContentView`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/NotchContentView.swift)
- [`StatusItemController`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/StatusItemController.swift)

[`MenuContentView`](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/MenuContentView.swift) 虽然当前不是主渲染路径，也应同步到同一规则，避免后续重新接线时出现行为分叉。

## Error Handling

- 若 `idleSince == nil`，即使状态是 `idle` 也不自动折叠。
- 老 session 文件缺少 `idleSince` 时仍然可以正常显示，只是不会立即触发折叠。
- 若某个来源错误地把 idle session 刷新了 `updatedAt`，只会影响排序，不影响折叠时长。

## Testing

- 模型/展示层测试：
  - 全局排序按 `updatedAt desc`
  - 分组内排序按 `updatedAt desc`
  - `idleSince` 超过 30 分钟才折叠
  - `running` / `awaitingInput` / `unknown` 不折叠
- 检测器测试：
  - Codex / Gemini 在 idle 状态下产出正确 `idleSince`
- 合并测试：
  - detector 缺少 `idleSince` 时保留 file session 的值
  - interaction hydrate / resolve 会清空 `idleSince`
- 验证命令：
  - `swift test`
  - `swift build`
