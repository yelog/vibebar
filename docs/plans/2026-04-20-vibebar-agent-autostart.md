# VibeBar Agent Auto-Start Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 让源码模式与发布模式的 `VibeBarApp` 都能自动确保 `vibebar-agent` 可用，并在遗留坏 socket 存在时自动恢复。

**Architecture:** 将 agent 可用性检查、遗留 socket 清理、进程启动决策从 `AppDelegate` 抽到独立协调器。`AppDelegate` 只在启动时调用协调器，在退出时终止自己创建的子进程。协调器使用注入式依赖包裹 `pgrep`、socket 探测、文件删除与 `Process` 启动，保证逻辑可测。

**Tech Stack:** Swift 6.2, Foundation, Darwin UNIX socket, Swift Testing

---

### Task 1: 抽取可测试的 agent 启动协调器

**Files:**
- Create: `Sources/VibeBarApp/AgentLaunchCoordinator.swift`
- Modify: `Sources/VibeBarApp/AppDelegate.swift`
- Test: `Tests/VibeBarAppTests/AgentLaunchCoordinatorTests.swift`

**Step 1: Write the failing test**

```swift
@Test func coordinatorRemovesStaleSocketAndStartsAgentWhenNoProcessExists() throws {
    var didRemoveSocket = false
    var didStartAgent = false

    let coordinator = AgentLaunchCoordinator(
        environment: .init(
            runMode: .source,
            socketPath: "/tmp/vibebar-agent.sock",
            socketReachability: { _ in false },
            isAgentProcessRunning: { false },
            socketFileExists: { _ in true },
            removeSocketFile: { _ in didRemoveSocket = true },
            startAgent: {
                didStartAgent = true
                return nil
            }
        )
    )

    let result = coordinator.ensureAgentAvailable()

    #expect(result.startedNewProcess)
    #expect(didRemoveSocket)
    #expect(didStartAgent)
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter AgentLaunchCoordinatorTests`
Expected: FAIL，因为协调器类型尚不存在。

**Step 3: Write minimal implementation**

```swift
struct AgentLaunchCoordinator {
    struct Environment { ... }
    func ensureAgentAvailable() -> Result { ... }
}
```

实现最小决策分支：
- reachable socket -> no-op
- no process + stale socket -> remove + start
- no process + no socket -> start
- running process + unreachable socket -> no-op

**Step 4: Run test to verify it passes**

Run: `swift test --filter AgentLaunchCoordinatorTests`
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/VibeBarApp/AgentLaunchCoordinator.swift Tests/VibeBarAppTests/AgentLaunchCoordinatorTests.swift
git commit -m "fix(app): auto-recover vibebar-agent on startup"
```

### Task 2: 接入 App 启动链路

**Files:**
- Modify: `Sources/VibeBarApp/AppDelegate.swift`
- Test: `Tests/VibeBarAppTests/AgentLaunchCoordinatorTests.swift`

**Step 1: Write the failing test**

```swift
@Test func coordinatorSupportsSourceModeStartup() throws {
    let coordinator = AgentLaunchCoordinator(
        environment: .init(runMode: .source, ...)
    )

    let result = coordinator.ensureAgentAvailable()
    #expect(result.attemptedStartup)
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter AgentLaunchCoordinatorTests`
Expected: FAIL，因为源码模式仍被过滤。

**Step 3: Write minimal implementation**

```swift
func applicationDidFinishLaunching(_ notification: Notification) {
    ...
    ensureAgentAvailableIfNeeded()
    if VibeBarPaths.runMode == .published {
        UpdateChecker.shared.initialize()
    }
}
```

要求：
- 启动 agent 的逻辑不再局限于 `.published`
- `UpdateChecker.shared.initialize()` 仍保持仅发布模式调用
- 退出时只终止由当前实例新启动的 `Process`

**Step 4: Run test to verify it passes**

Run: `swift test --filter AgentLaunchCoordinatorTests`
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/VibeBarApp/AppDelegate.swift Tests/VibeBarAppTests/AgentLaunchCoordinatorTests.swift
git commit -m "fix(app): start vibebar-agent in source mode"
```

### Task 3: 补齐边界测试并回归验证

**Files:**
- Modify: `Tests/VibeBarAppTests/AgentLaunchCoordinatorTests.swift`

**Step 1: Write the failing tests**

```swift
@Test func coordinatorSkipsStartupWhenSocketIsReachable() throws { ... }
@Test func coordinatorDoesNotDeleteSocketWhenProcessStillExists() throws { ... }
@Test func coordinatorReportsFailureWhenStartThrows() throws { ... }
```

**Step 2: Run test to verify they fail**

Run: `swift test --filter AgentLaunchCoordinatorTests`
Expected: FAIL，未覆盖所有边界。

**Step 3: Write minimal implementation**

补足结果类型与分支返回值，让测试能断言：
- 是否启动了新进程
- 是否删除了遗留 socket
- 是否遇到错误

**Step 4: Run targeted and broader tests**

Run: `swift test --filter AgentLaunchCoordinatorTests`
Expected: PASS

Run: `swift test --filter InteractionActionHandlerTests`
Expected: PASS

Run: `swift test --filter AgentSocketClientTests`
Expected: PASS

**Step 5: Commit**

```bash
git add Tests/VibeBarAppTests/AgentLaunchCoordinatorTests.swift
git commit -m "test(app): cover vibebar-agent startup recovery"
```
