# Notch Auto Expand On State Change Design

**Date:** 2026-04-19

**Status:** Confirmed

## Goal

当刘海模式中的 Session 从“运行中”变为“等待中”或“空闲”时，自动展开刘海，并只展示触发状态变更的那个 Session，让用户可以直接点击它回到对应终端。

## Problem

- 当前刘海展开只支持鼠标 hover 和通知点击，没有“状态变更驱动”的自动展开入口。
- `StatusItemController` 已经能检测 `running -> awaitingInput` 和 `running -> idle`，但这些转换目前只用于通知和 hooks。
- 刘海展开后默认会渲染完整 Session 列表和 usage 区域；如果直接复用这套内容，自动展开时会让面板变长，干扰用户当前操作。

## Goals

- 在刘海模式下，对 `running -> awaitingInput` 和 `running -> idle` 自动展开。
- 自动展开时只展示触发变化的单个 Session。
- 点击该 Session 后复用现有跳转终端逻辑。
- 提供一个默认开启的设置开关，允许用户关闭这项行为。

## Non-Goals

- 不改变通知点击后的展开内容。
- 不改变用户手动 hover 展开时的完整面板内容。
- 不新增独立的弹窗、toast 或新的 Session 卡片组件。

## Chosen Approach

采用“一次性聚焦态展开”的方式。

具体行为：

1. `StatusItemController` 在检测到 `running -> awaitingInput` 或 `running -> idle` 时，如果当前入口模式是刘海且设置开关开启，则调用新的刘海自动展开入口。
2. `NotchDisplayController` 记录一个可选的 `focusedSessionID` 作为展开态上下文。
3. 刘海处于这次自动展开时，`NotchExpandedBodyView` 只渲染对应 Session，并隐藏其他 Session 与 usage 区域。
4. 该聚焦态只在本次自动展开期间有效；刘海收起后清空。后续用户手动展开仍看到完整面板。
5. 如果目标 Session 在渲染时已经不存在，则回退到普通完整内容，避免空白展开。

## Why This Approach

- 复用现有状态转换检测和 Session 点击跳转链路，改动集中在状态传递和视图裁剪。
- 不需要额外引入新的通知卡片或第二套 Session UI，视觉和交互都保持一致。
- 聚焦态只在自动展开时生效，能够在“及时提醒”和“不打断用户”之间取得平衡。

## UI / UX Details

- 自动展开内容只保留顶部栏和单条 Session 行。
- 聚焦态下不显示分组切换控件，避免为了一个 Session 仍占用额外空间。
- 聚焦态下隐藏 usage 卡片，控制面板高度，降低遮挡概率。
- Session 行保持现有 hover、按下态和点击跳转行为，避免学习成本。
- 如果刘海已经展开，新的自动展开请求不切换当前内容，避免打断用户正在进行的操作。

## Settings Design

- 位置：`General > System`
- 排布：放在“在刘海区域显示 VibeBar”下面，语义上归属同一组刘海行为设置。
- 开关文案：`状态变更时自动展开刘海`
- 描述文案：`当 Session 从运行中变为等待中或空闲时，自动展开刘海，并只显示该 Session，便于直接回到对应终端。`
- 默认值：开启。
- 当刘海展示关闭时，该开关显示为禁用态，但保留说明文案，表达“此功能依赖刘海模式”。

## Implementation Notes

- 将聚焦 Session 状态保留在 `NotchDisplayController`，而不是放进每次刷新的 payload 中，避免刘海展开期间被后续 `update(payload:)` 意外清掉。
- `NotchPanelViewState` 和 `NotchExpandedBodyView` 只接收一个可选的 `focusedSessionID`，不引入额外 view model。
- `StatusItemController` 的状态转换逻辑继续保持单一入口，自动展开和通知共享同一批转换检测，避免重复判断。

## Testing & Verification

- `AppSettings` 新增开关默认值和持久化行为要有测试覆盖。
- `swift test --filter AppSettingsTests` 通过。
- `swift build` 通过，确认 `StatusItemController`、刘海视图与设置页改动可编译。
- 手动验证：
  - 刘海模式开启时，`running -> awaitingInput` 自动展开并只显示对应 Session。
  - 刘海模式开启时，`running -> idle` 自动展开并只显示对应 Session。
  - 点击该 Session 能跳回原终端。
  - 收起后再手动 hover 展开，恢复完整列表。
  - 关闭设置开关后不再自动展开。
