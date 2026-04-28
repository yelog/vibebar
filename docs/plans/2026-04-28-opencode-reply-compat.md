# OpenCode Reply Compatibility Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 让 VibeBar 中对 OpenCode `permission` 和 `question` 选项的点击，能兼容当前插件 client 形态并成功回写到 OpenCode。

**Architecture:** 保留现有插件 interaction 队列与 ack 机制，只修复插件内部的 reply 兼容层。优先走存在的 SDK 方法，缺失时回退到 OpenCode 官方 HTTP reply/reject 接口，避免继续依赖不存在的 client 分组 API。

**Tech Stack:** JavaScript OpenCode plugin, Swift 6.2 verification, Node syntax check

---

### Task 1: Add plugin reply compatibility layer

**Files:**
- Modify: `plugins/opencode-vibebar-plugin/index.js`

**Step 1: Add reply base URL resolution helper**

- Reuse plugin context and interaction transport data to resolve `serverUrl` / fallback base URL.

**Step 2: Add generic HTTP JSON POST helper**

- Create a small helper for OpenCode reply endpoints with timeout and `application/json`.

**Step 3: Fix permission reply order**

- Try `sdkClient.permission.reply(...)` when available.
- Else try legacy `sdkClient.postSessionIdPermissionsPermissionId(...)`.
- Else POST `/permission/{requestID}/reply`.

**Step 4: Fix question reply order**

- Try `sdkClient.question.reply(...)` when available.
- Else POST `/question/{requestID}/reply`.
- For reject, POST `/question/{requestID}/reject`.

**Step 5: Keep queue and ack semantics unchanged**

- Only send plugin ack after actual reply succeeds.

### Task 2: Verify behavior and regressions

**Files:**
- Verify: `plugins/opencode-vibebar-plugin/index.js`
- Verify: `Tests/VibeBarAppTests/OpenCodeLegacyPermissionBridgeTests.swift`

**Step 1: Syntax check plugin**

Run: `node --check plugins/opencode-vibebar-plugin/index.js`

**Step 2: Run targeted Swift test**

Run: `swift test --filter OpenCodeLegacyPermissionBridgeTests`

**Step 3: Run full test suite**

Run: `swift test`
