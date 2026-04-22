# OpenCode SDK-Only Replies Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 让 VibeBar 中点击 OpenCode 候选项后，通过 OpenCode 插件进程内 SDK 回写并推动 OpenCode 继续执行。

**Architecture:** OpenCode 插件仍负责把 `permission.asked` / `question.asked` 转成 VibeBar interaction；VibeBar UI 点击后只把 decision 返回同一个插件；插件使用 `ctx.client` 提供的 SDK 方法完成真实 reply。HTTP reply fallback 被移除，agent/App 状态不再把“点击已送达”误判为“OpenCode 已确认”。OpenCode 同一轮连续发多个 permission 时，插件用串行队列逐个交给 VibeBar，避免 agent 按 session 合并时冲掉前面的请求。

**Tech Stack:** JavaScript OpenCode plugin bridge, Swift 6.2 agent/App, Swift Testing

---

### Task 1: OpenCode 插件改为 SDK-only reply

**Files:**
- Modify: `plugins/opencode-vibebar-plugin/index.js`

**Steps:**
1. 在 permission/question interaction 的 `transport_context` 中保留 OpenCode 原始 `sessionID`。
2. 移除 `postJSON` / `buildServerURL` reply fallback。
3. permission 优先调用 `sdkClient.permission.reply(...)`，缺失时调用默认 SDK 的 `postSessionIdPermissionsPermissionId(...)`。
4. question 只调用 `sdkClient.question.reply(...)`，缺失时明确记录失败。
5. SDK reply 成功后由插件发回无 decision 的 ack；后续 `permission.replied` / `question.replied` 事件继续幂等确认。
6. 对连续 `permission.asked` / `question.asked` 使用 FIFO 队列，当前项处理成功后再展示下一项。

### Task 2: 避免 VibeBar 点击后假 running

**Files:**
- Modify: `Sources/VibeBarAgent/main.swift`
- Modify: `Sources/VibeBarApp/OpenCodeLegacyPermissionBridge.swift`
- Test: `Tests/VibeBarAppTests/OpenCodeLegacyPermissionBridgeTests.swift`

**Steps:**
1. agent 收到 UI decision 时只唤醒插件，不立刻删除 OpenCode plugin interaction。
2. 插件 SDK reply 成功后发回无 decision 的 ack response 时，再清理 interaction 并清除 session pending。
3. legacy plugin permission 的 `always` 保持为 `optionID: "always"`，避免 ack-only。

### Task 3: 验证

**Commands:**
- `node --check plugins/opencode-vibebar-plugin/index.js`
- `swift test --filter OpenCodeLegacyPermissionBridgeTests`
- `swift test`
