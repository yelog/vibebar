# Session Project Grouping Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 为 VibeBar 的 session 列表新增按项目分组能力，并在项目分组下显示工具图标、隐藏目录行、只展示文件夹名称作为组头。

**Architecture:** 先把 session 分组设置从布尔值升级成枚举分组模式，再把 `SessionListPresentation` 提升为通用分组抽象，同时为 session 行引入明确的展示上下文，以便 notch、原生菜单和备用 SwiftUI 菜单共用一致的项目分组展示规则。

**Tech Stack:** Swift 6.2, Foundation, SwiftUI, AppKit, Swift Testing

---

### Task 1: 升级设置项为分组模式枚举

**Files:**
- Modify: `Sources/VibeBarApp/AppSettings.swift`
- Modify: `Sources/VibeBarApp/SettingsView.swift`
- Modify: `Sources/VibeBarCore/L10nStrings.swift`

**Step 1: 写最小实现**

- 新增 `SessionGroupingMode`
- 用 `sessionGroupingMode` 取代 `groupSessionsByTool`
- 保留旧 key 迁移：
  - `true -> .tool`
  - `false -> .none`
- 设置页把开关改为多选项控件

**Step 2: 运行构建验证**

Run: `swift build`
Expected: PASS

### Task 2: 重构 session 列表分组抽象

**Files:**
- Modify: `Sources/VibeBarApp/SessionListPresentation.swift`
- Test: `Tests/VibeBarAppTests/SessionListPresentationTests.swift`

**Step 1: 先补测试**

- 覆盖按工具分组仍兼容
- 覆盖按项目分组按完整路径分桶
- 覆盖同名目录冲突时生成次级区分信息
- 覆盖组间顺序按 top session 排序

**Step 2: 实现最小逻辑**

- 引入通用 group kind
- 增加项目分组元数据
- 保留当前 session 排序规则不变

**Step 3: 跑定向测试**

Run: `swift test --filter SessionListPresentationTests`
Expected: PASS

### Task 3: 为 session 行增加明确展示上下文

**Files:**
- Modify: `Sources/VibeBarApp/SessionDisplayFormatter.swift`
- Test: `Tests/VibeBarAppTests/SessionDisplayFormatterTests.swift`

**Step 1: 先补测试**

- 覆盖 `flat / toolGroup / projectGroup` 三种上下文
- 断言项目分组下目录文本被抑制
- 断言第二行 currentTask 逻辑保持兼容

**Step 2: 实现最小逻辑**

- 引入行展示上下文枚举
- 用上下文替代 `isGrouped`
- 增加目录是否显示的统一判断

**Step 3: 跑定向测试**

Run: `swift test --filter SessionDisplayFormatterTests`
Expected: PASS

### Task 4: 更新三套 session 列表 UI

**Files:**
- Modify: `Sources/VibeBarApp/NotchContentView.swift`
- Modify: `Sources/VibeBarApp/StatusItemController.swift`
- Modify: `Sources/VibeBarApp/MenuContentView.swift`

**Step 1: 更新组头渲染**

- 工具分组继续显示 tool icon + tool name
- 项目分组显示 folder icon + folder name
- basename 冲突时补充次级区分信息

**Step 2: 更新 session 行渲染**

- 项目分组下第一行显示工具图标
- 项目分组下隐藏第三行目录
- 工具分组保留现有隐藏图标行为

**Step 3: 运行构建验证**

Run: `swift build`
Expected: PASS

### Task 5: 运行最终验证

**Files:**
- Modify: none

**Step 1: 跑定向测试**

Run: `swift test --filter SessionListPresentationTests`
Expected: PASS

Run: `swift test --filter SessionDisplayFormatterTests`
Expected: PASS

**Step 2: 跑构建**

Run: `swift build`
Expected: PASS

**Step 3: 手工检查**

- 平铺模式仍显示工具图标和目录
- 按工具分组时行为不回退
- 按项目分组时组头只显示文件夹名
- 按项目分组时 session 第一行能区分具体 agent CLI
