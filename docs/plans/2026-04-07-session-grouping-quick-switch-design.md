# Session Grouping Quick Switch Design

**Date:** 2026-04-07

**Status:** Confirmed

## Goal

把 session 区域右上角当前的静态分组文案升级为可直接切换的快速入口，并在两处主要入口保持一致：

- 菜单栏原生下拉
- 刘海下拉面板

用户应能直接在列表头部平铺看到并切换：

- 不分组
- 按工具
- 按项目

切换后立即生效，不需要进入设置页。

## Problem

- 当前刘海下拉只在右上角显示静态文本，例如“按项目”，不可交互。
- 原生菜单栏下拉目前没有 session 分组切换入口，只能依赖设置页。
- 已经存在 `sessionGroupingMode` 设置，但缺少“就地切换”的快捷 UI。

## Goals

- 在 session 区域头部提供可点击的三选一切换控件。
- 两处入口的交互语义保持一致。
- 点击后实时切换列表展示，不关闭当前认知链路。
- 保留设置页中的分组模式设置作为长期配置入口。

## Non-Goals

- 本次不改变现有分组逻辑本身。
- 本次不新增更多分组维度。
- 本次不修改 session 排序和折叠规则。

## Chosen UI

采用紧凑型“三段胶囊切换”。

### Why Not A Menu

用户明确要求“把现在支持的不分组、按工具、按项目平铺出来”，所以不适合用下拉菜单或二级 submenu。

### Why Not Reuse System Segmented Picker Directly Everywhere

SwiftUI 的 segmented picker 在刘海面板里可用，但原生菜单里的 `NSMenuItem` 更适合用自定义轻量按钮行，以便：

- 保持尺寸可控
- 避免原生 segmented control 在菜单中显得过重
- 更容易和刘海面板做统一视觉

## Interaction Design

### Layout

左侧：

- `会话`

右侧：

- `不分组`
- `按工具`
- `按项目`

### Visual Rules

- 选中项：更高对比度、实底背景
- 未选中项：低对比度文字，hover 时轻微抬亮
- 整组包裹在低对比度圆角容器内，减少按钮边界噪音

### Behavior

- 点击任一选项后立即写入 `AppSettings.shared.sessionGroupingMode`
- 刘海面板依赖 SwiftUI 观察自动刷新
- 原生菜单依赖现有 `StatusItemController` 对设置变更的监听自动重建菜单
- 菜单切换后保持当前菜单可见，让用户立刻看到结果

## Architecture

### Reusable SwiftUI Control

新增可复用控件：

- `SessionGroupingModeSwitcher`

职责：

- 渲染三段模式选择
- 支持紧凑尺寸
- 接受 `Binding<SessionGroupingMode>`

### Reusable Session Header

新增通用头部视图：

- `SessionSectionHeaderView`

职责：

- 左侧显示 `会话`
- 右侧承载 `SessionGroupingModeSwitcher`

该视图用于：

- `NotchContentView`
- `MenuContentView`
- 原生菜单中的 `NSHostingView`

## Menu Bar Dropdown Integration

在原生菜单里，session 列表开始前插入一个自定义 header item。

这样结构变成：

1. 标题
2. 更新时间副标题
3. separator
4. session section header（含快速切换）
5. session 列表 / no sessions

## Testing & Verification

- 切到 `不分组`，列表立即变为平铺
- 切到 `按工具`，列表立即按工具分组
- 切到 `按项目`，列表立即按项目分组
- 刘海下拉与原生菜单都能独立操作
- 设置页中的值会与快速切换入口保持一致
