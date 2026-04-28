# OpenCode Reply Compatibility Design

**Date:** 2026-04-28

**Status:** Confirmed

## Goal

修复 VibeBar 中点击 OpenCode `permission` / `question` 选项后，OpenCode 端没有收到回复、仍停留在原始选项界面的问题。

## Problem

- VibeBar 现在已经能正确展示 OpenCode 插件上报的 `options`，说明 interaction 展示链路是通的。
- 但点击后的回写链路依赖 `plugins/opencode-vibebar-plugin/index.js` 中的 SDK 调用。
- 当前插件代码尝试调用 `sdkClient.permission.reply(...)` 和 `sdkClient.question.reply(...)`。
- 官方插件类型实际给到的是 `@opencode-ai/sdk` 的旧 client 形态，不保证存在上述分组 API。
- 在当前环境中，runtime client 只有旧的 `postSessionIdPermissionsPermissionId(...)`，没有 `client.permission`，也没有 `client.question`。
- 结果是 `question` 回写完全失效，`permission` 回写也依赖不稳定兼容路径，导致点击后 OpenCode 端仍保持 pending。

## Decision

采用“插件内双栈兼容”方案：

1. 继续保留当前插件内 interaction 队列和 ack 机制。
2. `permission` 回写优先尝试分组 SDK API；缺失时退回旧 SDK permission API；再缺失时退回官方 HTTP reply 接口。
3. `question` 回写优先尝试分组 SDK API；缺失时退回官方 HTTP reply / reject 接口。
4. 对 `reject` 的 `question` 显式调用 reject 路径，而不是一律构造 answers。
5. 保持 agent / app 现有“等待插件 ack 后再真正清理 interaction”的时序不变。

## Scope

- Modify: `plugins/opencode-vibebar-plugin/index.js`
- Verify: `node --check plugins/opencode-vibebar-plugin/index.js`
- Verify: targeted Swift tests and full `swift test`

## Verification

- `question` 类型选项点击后，OpenCode 原界面不再停留在待选状态。
- `permission` 的 `Allow once` / `Allow always` / `Reject` 均能继续回写。
- 插件仍然只在成功 reply 后发送 ack，避免 VibeBar 和 OpenCode 状态提前失真。
