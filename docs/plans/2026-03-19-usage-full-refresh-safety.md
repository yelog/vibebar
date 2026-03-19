# Usage Full Refresh Safety Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 将 Claude Code / Codex 的 full refresh 改成“全量校验 + 按差异重建 source 结果”，在不引入脏数据残留的前提下复用已有状态与缓存。

**Architecture:** 在 `UsageIncrementalLoader` 中把 full refresh 改成基于当前文件全集的权威重建：重新枚举全部文件、识别 unchanged/changed/deleted、复用当前状态中的 unchanged events、重解析 changed files，并继续用 source replace 语义覆盖旧结果。为避免 parser 逻辑变更导致旧事件残留，同时为 source cache 与 incremental state 增加 parser version / data version 校验，并统一 event id 中文件路径提取逻辑。

**Tech Stack:** Swift 6.2, Foundation, Swift Testing

---

### Task 1: 计划与测试范围

**Files:**
- Modify: `Tests/VibeBarCoreTests/UsageLoaderFixtureTests.swift`

**Step 1: 写一个覆盖“full refresh 删除旧文件事件”的测试**

新增测试场景：
- 先构造 Claude/Codex 文件并完成一次 refresh
- 删除其中一个文件
- 再走 full refresh
- 断言被删除文件对应的 events 不再存在

**Step 2: 运行单测确认当前行为或缺口**

Run: `swift test --filter UsageLoaderFixtureTests`
Expected: 新测试失败，或暴露 full refresh 路径缺少权威替换语义/统一 event path 解析的问题。

### Task 2: parser version 与状态失效

**Files:**
- Modify: `Sources/VibeBarCore/UsageFileCacheStore.swift`
- Modify: `Sources/VibeBarCore/UsageIncrementalState.swift`
- Modify: `Sources/VibeBarCore/ClaudeUsageLoader.swift`
- Modify: `Sources/VibeBarCore/CodexUsageLoader.swift`

**Step 1: 为 source cache 增加 parserVersion**

在 `UsageSourceFileCache` 中增加 `parserVersion` 字段；loader 读缓存时要求 `version` 与 `parserVersion` 同时匹配，否则视为 miss；写缓存时回填当前 parserVersion。

**Step 2: 为 incremental state 增加 per-source parserVersion**

让 `UsageIncrementalState` 能记录每个 source 最近一次写入 state 时使用的 parser version，并在 refresh 决策时据此判断能否安全复用现有 events。

**Step 3: bump state/cache version**

提高 state/cache version，确保历史落盘数据在新逻辑下不会被误用。

### Task 3: 安全版 full refresh

**Files:**
- Modify: `Sources/VibeBarCore/UsageIncrementalLoader.swift`
- Modify: `Sources/VibeBarCore/ClaudeUsageLoader.swift`
- Modify: `Sources/VibeBarCore/CodexUsageLoader.swift`
- Modify: `Sources/VibeBarCore/UsageLoaderSupport.swift`

**Step 1: 提取统一的 event 文件路径解析 helper**

将 Claude/Codex/Gemini/OpenCode event id 中的文件路径提取逻辑统一到 helper，避免继续依赖 `source.rawValue + ":"` 这种不稳定前缀。

**Step 2: full refresh 改成权威差异重建**

在 `UsageIncrementalLoader.loadFull` 中：
- 枚举当前 source 全部文件
- 识别 unchanged/changed/deleted
- unchanged 直接从当前 state 复用对应 events
- changed 重新解析文件
- deleted 不进入新结果
- 返回该 source 的完整 events/signatures

**Step 3: 保持 source replace 语义**

合并阶段继续先剔除 full refresh source 的旧 events，再并入新结果，确保删除类垃圾数据能被清掉。

### Task 4: 回归测试

**Files:**
- Modify: `Tests/VibeBarCoreTests/UsageLoaderFixtureTests.swift`

**Step 1: 增加 parser version 失效测试**

构造旧 version cache/state，断言 refresh 不会盲目信任旧事件。

**Step 2: 增加 Claude event id 删除路径解析测试**

验证删除逻辑对 `claude:` 前缀同样成立。

**Step 3: 跑定向测试**

Run: `swift test --filter UsageLoaderFixtureTests`
Expected: PASS

### Task 5: 集成验证

**Files:**
- Modify: `Sources/VibeBarCore/UsageIncrementalLoader.swift`
- Modify: `Sources/VibeBarCore/UsageIncrementalState.swift`

**Step 1: 跑 usage 相关测试集**

Run: `swift test --filter Usage`
Expected: PASS

**Step 2: 做一次完整构建**

Run: `swift build`
Expected: BUILD SUCCEEDED
