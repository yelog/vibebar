# OpenCode Two-Line Display Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 让 OpenCode 运行中会话稳定显示两行信息，第一行是最后一次用户输入，第二行是当前运行摘要。

**Architecture:** 展示层在 `SessionDisplayFormatter` 中为 OpenCode 运行态建立独立的首行/次行规则，Notch、状态栏和菜单统一复用。合并层在 `AppModel` 中允许 HTTP/SQLite 检测结果覆盖插件的低质量占位摘要。插件层补齐 assistant progress part 的摘要提取，减少只得到“处理中”的情况。

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, Node.js plugin, Testing

---

### Task 1: 调整 OpenCode 的首行/次行语义

**Files:**
- Modify: `Sources/VibeBarApp/SessionDisplayFormatter.swift`
- Modify: `Sources/VibeBarApp/MenuContentView.swift`
- Test: `Tests/VibeBarAppTests/SessionDisplayFormatterTests.swift`

**Step 1: 写失败测试**

为 OpenCode 运行态添加断言：
- 第一行优先显示 `lastUserMessage`
- 第二行显示 `runningSummary`
- 菜单补充行不要重复展示首行已经使用的用户消息

**Step 2: 运行测试确认失败**

Run: `swift test --filter SessionDisplayFormatterTests`

Expected: 新增的 OpenCode 两行展示断言失败

**Step 3: 实现最小改动**

在 `SessionDisplayFormatter` 中：
- 为 OpenCode `running/awaiting_input` 提供“用户消息优先”的首行规则
- 保持其它工具现有逻辑不变

在 `MenuContentView` 中：
- 改为复用 formatter 产出的次行
- 只在首行未占用用户消息时展示补充用户消息行

**Step 4: 运行测试确认通过**

Run: `swift test --filter SessionDisplayFormatterTests`

Expected: PASS

### Task 2: 提升 OpenCode 运行摘要回填质量

**Files:**
- Modify: `Sources/VibeBarApp/AppModel.swift`
- Test: `Tests/VibeBarAppTests/AppModelTests.swift`

**Step 1: 写失败测试**

添加合并用例：
- 插件已有 `runningSummary = "处理中"` 或与 `title/currentTask/lastUserMessage` 重复
- 检测层提供更具体的运行摘要
- 合并后应使用更具体的摘要

**Step 2: 运行测试确认失败**

Run: `swift test --filter AppModelTests`

Expected: 新增的 OpenCode 摘要替换断言失败

**Step 3: 实现最小改动**

在 `mergeDetectedDetails` 中加入 OpenCode 特殊规则，仅当已有摘要明显是低质量占位时，才允许检测结果覆盖。

**Step 4: 运行测试确认通过**

Run: `swift test --filter AppModelTests`

Expected: PASS

### Task 3: 增强 OpenCode 插件实时摘要

**Files:**
- Modify: `plugins/opencode-vibebar-plugin/index.js`

**Step 1: 实现摘要提取**

扩展 `message.part.updated` 处理逻辑，支持：
- `text`
- `reasoning`
- `tool`
- `patch`
- `step-start`
- `step-finish`

**Step 2: 校验语法**

Run: `node --check plugins/opencode-vibebar-plugin/index.js`

Expected: 无输出，退出码 `0`

### Task 4: 运行回归验证

**Files:**
- Modify: `Tests/VibeBarAppTests/SessionDisplayFormatterTests.swift`
- Modify: `Tests/VibeBarAppTests/AppModelTests.swift`

**Step 1: 跑针对性测试**

Run: `swift test --filter SessionDisplayFormatterTests`

Expected: PASS

Run: `swift test --filter AppModelTests`

Expected: PASS

**Step 2: 做一次语法校验**

Run: `node --check plugins/opencode-vibebar-plugin/index.js`

Expected: PASS
