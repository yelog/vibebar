# OpenCode SQLite Usage Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 让 VibeBar 在 OpenCode 使用 SQLite 存储时仍能正确统计最近的 token usage。

**Architecture:** 在 `OpenCodeUsageLoader` 中新增 SQLite 读取路径，优先从 `opencode.db` 的 `message` 表提取 usage 字段；当数据库不可用时回退到现有的 `storage/message/*.json` 解析逻辑。缓存层继续使用现有 `UsageFileCacheStore`，但为数据库增加组合签名。

**Tech Stack:** Swift 6.2, Foundation, SQLite3, Swift Testing

---

### Task 1: 为 OpenCode loader 建立 SQLite 主路径

**Files:**
- Modify: `Sources/VibeBarCore/OpenCodeUsageLoader.swift`
- Modify: `Package.swift`

**Step 1: 写失败测试**

在 `Tests/VibeBarCoreTests/UsageLoaderFixtureTests.swift` 增加 SQLite fixture，验证 `opencode.db` 中的 `message.data.tokens` 可被解析为 `UsageEvent`。

**Step 2: 运行测试确认失败**

Run: `swift test --filter opencodeLoaderParsesSQLiteMessages`

Expected: FAIL，因为当前 loader 只读 JSON 文件。

**Step 3: 实现最小 SQLite 读取逻辑**

- 给 `VibeBarCore` 链接 `sqlite3`
- 在 `OpenCodeUsageLoader` 中新增：
  - `loadFromDatabase`
  - 数据库 statement 执行与结果映射
  - `opencode.db` + `opencode.db-wal` 的 cache 签名
- 保留旧 JSON 逻辑，作为 fallback

**Step 4: 运行测试确认通过**

Run: `swift test --filter opencodeLoaderParsesSQLiteMessages`

Expected: PASS

### Task 2: 保留旧 JSON 兼容性

**Files:**
- Modify: `Sources/VibeBarCore/OpenCodeUsageLoader.swift`
- Test: `Tests/VibeBarCoreTests/UsageLoaderFixtureTests.swift`

**Step 1: 确认旧 JSON fixture 仍然有效**

Run: `swift test --filter opencodeLoaderParsesMessageFiles`

Expected: PASS

**Step 2: 增加“数据库优先”测试**

在同一个临时 root 里同时放入 `opencode.db` 和旧 `storage/message/*.json`，断言 loader 只返回数据库数据。

**Step 3: 运行测试确认通过**

Run: `swift test --filter opencodeLoaderPrefersSQLiteOverLegacyFiles`

Expected: PASS

### Task 3: 回归验证

**Files:**
- Test: `Tests/VibeBarCoreTests/UsageLoaderFixtureTests.swift`

**Step 1: 跑 usage loader 相关测试**

Run: `swift test --filter UsageLoaderFixtureTests`

Expected: PASS

**Step 2: 跑 core 编译验证**

Run: `swift build --target VibeBarCore`

Expected: PASS
