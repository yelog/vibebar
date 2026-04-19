# Session Default Project Grouping Design

**Date:** 2026-04-19

**Status:** Confirmed

## Goal

让 Session 列表在默认情况下按项目分类，而不是按工具分类，同时不覆盖已有用户已经保存的分组偏好。

## Problem

- 当前 `AppSettings.loadSessionGroupingModeWithMigration()` 会在缺少新键 `sessionGroupingMode` 时，回退到旧键 `groupSessionsByTool`。
- `groupSessionsByTool` 又在 `UserDefaults.register(defaults:)` 中被注册为 `true`。
- 结果是新安装用户即使从未设置过分组方式，也会被判定为“按工具分组”。

## Goals

- 新用户默认按项目分组。
- 已保存 `sessionGroupingMode` 的用户保持现状。
- 旧版本用户如果真的保存过 `groupSessionsByTool`，仍按原含义迁移。

## Non-Goals

- 不修改 Session 菜单 UI。
- 不改变项目分组和工具分组的展示逻辑。
- 不重置已有用户偏好。

## Chosen Approach

采用“仅在真实存在旧键时才迁移，否则回退到 `.project` 默认值”的方式。

具体规则：

1. 如果存在 `sessionGroupingMode`，直接使用它。
2. 如果不存在新键，但旧键 `groupSessionsByTool` 真实存在，则迁移：
   - `true` -> `.tool`
   - `false` -> `.none`
3. 如果两个键都不存在，则写入并返回 `.project`。

## Why This Approach

- 改动范围只在设置加载路径，风险最小。
- 不影响菜单和刘海面板读取 `sessionGroupingMode` 的现有逻辑。
- 能区分“旧用户显式保存过旧键”和“新用户只是命中了注册默认值”这两种情况。

## Implementation Notes

- 从 `UserDefaults.register(defaults:)` 中移除 `groupSessionsByTool` 的默认注册，避免新用户被误判为旧设置。
- 将 `loadSessionGroupingModeWithMigration()` 调整为接收可注入的 `UserDefaults`，方便单元测试覆盖迁移分支。

## Testing & Verification

- 无任何相关偏好时，默认返回 `.project`，并写入 `sessionGroupingMode`。
- 旧键为 `true` 时迁移为 `.tool`，并清除旧键。
- 旧键为 `false` 时迁移为 `.none`，并清除旧键。
- 已存在新键时优先使用新键，不受旧键影响。
