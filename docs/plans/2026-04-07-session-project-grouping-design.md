# Session Project Grouping Design

**Date:** 2026-04-07

**Status:** Confirmed

## Goal

让 VibeBar 的 session 列表在保留现有排序规则的前提下，新增“按项目（文件夹）分组”能力，并针对项目分组优化列表行信息密度：

- 分组头显示当前文件夹名称，而不是完整路径
- session 第一行显示当前 agent CLI 图标，便于识别工具来源
- 项目分组下不再重复显示第三行目录

## Problem

- 当前 session 分组被直接建模为“按工具分组”，数据结构和 UI 都把 `Group` 绑定在 `ToolKind` 上。
- `groupSessionsByTool: Bool` 只能表达“平铺 / 按工具”两种状态，无法自然扩展到“按项目分组”。
- 现有 UI 用 `isGrouped` 统一控制分组态样式，导致“分组时隐藏工具图标、继续显示目录”被写死，不适用于项目分组。
- 分组头如果直接展示完整路径，在菜单和 notch 面板中会很容易截断。

## Goals

- 新增可扩展的 session 分组模式，至少支持：
  - 不分组
  - 按工具分组
  - 按项目分组
- 按项目分组时，以 `session.cwd` 的规范化完整路径作为分组键。
- 按项目分组时，分组标题只显示当前目录名（basename）。
- 按项目分组时，session 第一行重新显示 agent/tool 图标。
- 按项目分组时，第三行目录隐藏。
- 保持现有排序规则：
  - 状态优先级：`awaitingInput > running > idle > unknown`
  - 同状态按 `currentStatusSince` 越新越靠前
  - 组间顺序按组内 top session 排序

## Non-Goals

- 本次不把“项目”提升为 Git 仓库根目录语义。
- 本次不新增按仓库根自动合并子目录 session 的逻辑。
- 本次不改变 session 摘要聚合或状态颜色规则。
- 本次不增加新的筛选器或搜索能力。

## Chosen Approach

采用“可扩展分组模式 + `cwd` 路径分组”的方案。

### Grouping Model

在 App 层引入独立的分组模式枚举，例如：

- `none`
- `tool`
- `project`

同时将 `SessionListPresentation.Group` 从只持有 `tool` 的结构，提升为可表达不同 group kind 的通用模型。项目分组内部建议包含：

- `id`：使用规范化完整路径，保证唯一性
- `displayName`：当前目录名
- `secondaryLabel`：仅在同名冲突时用于轻量区分
- `sessions`

### Why Use Full Path As Key

显示名只用 basename 不足以唯一标识项目。不同路径可能同名，例如：

- `/Users/dev/mobile/app`
- `/Users/dev/server/app`

因此：

- 分组键必须是完整路径
- UI 默认只显示 basename
- 如果 basename 冲突，再为组头补充轻量 disambiguation

### Row Presentation Context

不能继续把“是否分组”压缩成 `Bool`。推荐引入更明确的展示上下文，例如：

- `flat`
- `toolGroup`
- `projectGroup`

规则如下：

- `flat`
  - 显示工具图标
  - 显示第三行目录
- `toolGroup`
  - 隐藏工具图标
  - 显示第三行目录
- `projectGroup`
  - 显示工具图标
  - 隐藏第三行目录

这样可以避免 notch、AppKit menu、备用 SwiftUI 菜单三套代码各自写条件分叉。

## Data Flow

1. `AppSettings` 提供统一的 `sessionGroupingMode`
2. `SessionListPresentation` 根据模式产出平铺列表或分组列表
3. 各 UI 容器根据 group kind 渲染对应的组头
4. session 行根据 `rowPresentationContext` 决定是否显示工具图标和目录

## UI Behavior

### Project Group Header

- 图标：文件夹图标
- 主标题：当前目录名
- 次级信息：仅在 basename 冲突时显示轻量区分文案
- 右侧：session 数与状态点

### Session Row In Project Group

- 第一行：工具图标 + session name + badges
- 第二行：`currentTask` 或其他次级摘要
- 第三行：不显示目录

### Unknown Directory Fallback

如果 `session.cwd` 缺失或为空：

- 归入一个统一的“未知目录”分组
- 使用稳定 id，例如 `project:unknown`
- 组标题显示本地化的未知目录文案

## Settings Migration

现有 `groupSessionsByTool` 是布尔值，需要兼容迁移：

- 旧值 `true` -> 新模式 `.tool`
- 旧值 `false` -> 新模式 `.none`

这样不会破坏已有用户的设置习惯。项目分组作为新增选项默认不主动开启。

## Testing

- `SessionListPresentation`
  - 按项目分组时按完整路径分桶
  - basename 冲突时生成次级区分信息
  - 组内和组间排序仍遵守当前规则
- `SessionDisplayFormatter`
  - `projectGroup` 下不再输出目录行
  - `projectGroup` 下仍保留第二行 currentTask
- UI/集成层
  - 项目分组下 session 行显示工具图标
  - 工具分组下 session 行继续隐藏工具图标

## Verification

- 设置切到“按项目分组”后，session 列表按 `cwd` 分组
- 分组头只显示文件夹名，不显示完整路径
- 同项目组内可直接看出每个 session 属于哪个 agent CLI
- 项目分组下 session 第三行目录不再出现
- 同名文件夹不会被错误合并
