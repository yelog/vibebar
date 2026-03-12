# Tooltip Token Format Design

**Goal:** 统一 Token Usage 悬停弹窗中的 token 数字展示，使用紧凑单位并降低视觉噪音。

## Scope

- 只修改 Token Usage 的 hover tooltip。
- 覆盖菜单里的柱状图/折线图 tooltip，以及热力图 hover 文案。
- 不修改卡片底部总量、设置项说明、非 hover 文案。

## Decision

- 使用英文紧凑单位：`K / M / B`。
- 只保留 1 位小数；若结果为 `.0` 则去掉。
- 小于 `1,000` 保持原始整数显示。
- 临界值在四舍五入后若达到下一级单位，自动升级，例如 `999,950 -> 1M`。

## Implementation

- 在 `VibeBarCore` 中新增可复用的 token 紧凑格式化工具。
- `UsageMenuSectionView` 的 tooltip 标题和分项明细改为使用统一 formatter。
- `UsageHeatmapView` 的 hover 文案改为使用统一 formatter。

## Validation

- 为 formatter 增加单元测试，覆盖小值、常见值和临界值。
- 运行针对性测试和一次完整构建，确认菜单和设置页都能编译通过。
