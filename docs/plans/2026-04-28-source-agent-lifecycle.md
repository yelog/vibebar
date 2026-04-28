# Source Agent Lifecycle Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 让 `swift run VibeBarApp` 在开发模式下始终使用最新构建的 `vibebar-agent`，并在退出时回收该 agent，避免复用陈旧后台进程导致会话状态异常。

**Architecture:** 在 `AgentLaunchCoordinator` 中引入 source-mode 强制重启策略，在 `AppDelegate` 中引入 source-mode 退出回收逻辑。发布版保持现有“可连通即复用”的保守策略，限制行为变化范围。

**Tech Stack:** Swift 6.2, AppKit lifecycle, Swift Testing

---

### Task 1: Add source-mode restart policy

**Files:**
- Modify: `Sources/VibeBarApp/AgentLaunchCoordinator.swift`
- Test: `Tests/VibeBarAppTests/AgentLaunchCoordinatorTests.swift`

**Step 1: Write the failing test**

- Add a test asserting that in source mode, a reachable existing agent is restarted.

**Step 2: Run test to verify it fails**

Run: `swift test --filter coordinatorRestartsReachableAgentInSourceMode`

**Step 3: Write minimal implementation**

- Thread run mode into `AgentLaunchCoordinator.Environment`.
- Make `ensureAgentAvailable()` restart reachable/running agent when `runMode == .source`.

**Step 4: Run test to verify it passes**

Run: `swift test --filter coordinatorRestartsReachableAgentInSourceMode`

### Task 2: Add source-mode shutdown cleanup

**Files:**
- Modify: `Sources/VibeBarApp/AppDelegate.swift`
- Modify: `Sources/VibeBarApp/AgentLaunchCoordinator.swift`
- Test: `Tests/VibeBarAppTests/AgentLaunchCoordinatorTests.swift`

**Step 1: Write the failing test**

- Add a testable API for source-mode shutdown cleanup behavior.

**Step 2: Run test to verify it fails**

Run: `swift test --filter coordinatorTerminatesExistingAgentInSourceModeOnShutdown`

**Step 3: Write minimal implementation**

- Expose a non-interactive helper to terminate an existing agent.
- In `AppDelegate.applicationWillTerminate`, when `runMode == .source`, invoke that helper even if `agentProcess` is nil.
- Register source-mode `SIGINT` / `SIGTERM` handlers so `Ctrl+C` also cleans up the agent before exit.

**Step 4: Run test to verify it passes**

Run: `swift test --filter coordinatorTerminatesExistingAgentInSourceModeOnShutdown`

### Task 3: Regression verification

**Files:**
- Verify: `Sources/VibeBarApp/AgentLaunchCoordinator.swift`
- Verify: `Sources/VibeBarApp/AppDelegate.swift`
- Verify: `Tests/VibeBarAppTests/AgentLaunchCoordinatorTests.swift`

**Step 1: Run targeted agent lifecycle tests**

Run: `swift test --filter AgentLaunchCoordinatorTests`

**Step 2: Run full test suite**

Run: `swift test`

**Step 3: Manual local verification**

Run:

```bash
pgrep -fl vibebar-agent
swift run VibeBarApp
pgrep -fl vibebar-agent
```

Expected: 开发模式启动后 agent 会是新进程；退出 `VibeBarApp` 后开发模式 agent 不再残留。
