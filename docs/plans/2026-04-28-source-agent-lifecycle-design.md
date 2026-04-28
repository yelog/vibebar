# Source Agent Lifecycle Design

**Date:** 2026-04-28

**Status:** Confirmed

## Goal

修复 `swift run VibeBarApp` 开发模式下复用陈旧 `vibebar-agent` 导致 OpenCode 会话状态长期错误的问题。

## Problem

- 当前机器上的 `vibebar-agent` 已持续运行自 2026-03-11。
- 当前源码构建出的 `vibebar-agent` 二进制时间为 2026-04-24，但 `agent.sock` 时间更新于 2026-04-28。
- `AgentLaunchCoordinator` 只在“可执行文件 mtime 晚于 socket mtime”时重启已可连通 agent。
- 因为 socket 时间更新更晚，`swift run VibeBarApp` 会持续复用 3 月留下来的旧 agent，而不是重启成当前代码对应的新 agent。
- `AppDelegate.applicationWillTerminate` 只会 terminate 当前 App 自己拉起的子进程；若附着到一个已存在 agent，则退出 App 时不会回收该 agent。
- 用户本机实测：手动 `kill` 掉旧 `vibebar-agent` 后，再启动 `swift run VibeBarApp`，OpenCode 会话状态恢复正常。

## Root Cause

问题不在 OpenCode 当前会话本身，而在 source 开发模式下的 agent 生命周期策略：

1. App 启动时过度保守地复用一个可连通但已陈旧的 agent。
2. App 退出时又不会清理这个“不是本次启动的 agent”。
3. 结果是 `swift run` 多次迭代后，新的 App 代码持续搭配旧 agent 运行，状态逻辑和落盘行为长期不一致。

## Decision

仅对 `VibeBarPaths.runMode == .source` 启用更激进但符合开发预期的策略：

1. 启动 `swift run VibeBarApp` 时，只要发现已有 `vibebar-agent`，就先 terminate 再拉起最新构建的 agent。
2. 退出 `swift run VibeBarApp` 时，不再只终止 `agentProcess`，而是主动结束当前 machine 上的 `vibebar-agent`。
3. 对 source 模式额外接管 `SIGINT` / `SIGTERM`，覆盖 `Ctrl+C` 这类不会可靠走到 AppKit terminate 回调的退出路径。
4. 发布版 `.app` 继续沿用现有保守复用策略，避免扩大正式用户行为变化。

## Scope

- Modify: `Sources/VibeBarApp/AgentLaunchCoordinator.swift`
- Modify: `Sources/VibeBarApp/AppDelegate.swift`
- Test: `Tests/VibeBarAppTests/AgentLaunchCoordinatorTests.swift`

## Verification

- 预先存在一个旧 `vibebar-agent` 时，`swift run VibeBarApp` 会重启它而不是直接复用。
- `Ctrl+C`/退出 `swift run VibeBarApp` 后，`pgrep -fl vibebar-agent` 不再残留开发模式 agent。
- 发布版路径的 existing behavior 不变。
