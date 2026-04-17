# Codex Realtime State Chain Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 为 VibeBar 增加参考 CodeIsland 的 Codex 实时状态链路，让 Codex CLI 会话通过 hooks 实时写入 `vibebar-agent`，并保留 `CodexSessionDetector` 作为恢复与兜底。

**Architecture:** 不引入第二套 `AppState`/socket reducer，而是沿用 VibeBar 现有 `AgentEvent -> vibebar-agent -> SessionFileStore -> AppModel.merge` 主链路。Codex 新增一条 `hook -> bridge -> AgentEvent` 的实时输入，再把 `CodexSessionDetector` 提升为“补标题、补 session 恢复、补 idle/running 精度”的后备层。UI 只扩展现有设置页，把 Codex 从 `session_file + process_scan` 升级为 `hook + session_file + process_scan`。

**Tech Stack:** Swift 6.2, Foundation, SQLite3, Swift Testing, macOS 13+, Swift Package Manager

---

### Task 1: Add Codex hook as a first-class detection method

**Files:**
- Modify: `Sources/VibeBarCore/CLISettingsConfiguration.swift`
- Modify: `Sources/VibeBarApp/CLISettingsView.swift`
- Modify: `Sources/VibeBarApp/AppModel.swift`
- Test: `Tests/VibeBarCoreTests/CLISettingsConfigurationTests.swift`

**Step 1: Write the failing test**

在 `CLISettingsConfigurationTests.swift` 增加 Codex 默认检测顺序断言：`[.hook, .sessionFile, .processScan]`，并断言 `availableMethods(for: .codex)` 包含 `.hook`。

**Step 2: Run test to verify it fails**

Run: `swift test --filter CLISettingsConfigurationTests`
Expected: FAIL because `.hook` does not exist yet.

**Step 3: Write minimal implementation**

- 在 `DetectionMethodPreference` 中新增 `.hook`
- Codex 默认方法改为 `hook -> sessionFile -> processScan`
- `CLISettingsView.methodDescription` 增加 Codex hook 文案
- `AppModel.RefreshConfiguration` 不再用 `pluginDisabledTools` 这种只适配 Claude/OpenCode 的名字，改成表达“agent 事件源是否启用”的更通用字段

**Step 4: Re-run focused test**

Run: `swift test --filter CLISettingsConfigurationTests`
Expected: PASS

### Task 2: Make the managed `vibebar` binary reusable by Codex hooks

**Files:**
- Modify: `Sources/VibeBarCore/WrapperCommandInstaller.swift`
- Modify: `Sources/VibeBarCore/Paths.swift`
- Create: `Tests/VibeBarCoreTests/WrapperCommandInstallerTests.swift`

**Step 1: Write the failing test**

新增一个 focused test，断言可以拿到一个稳定的“managed vibebar 可执行路径”给 hooks 使用，而不依赖 `~/.local/bin` 是否已加入 PATH。

**Step 2: Run test to verify it fails**

Run: `swift test --filter WrapperCommandInstallerTests`
Expected: FAIL because there is no public API for hook-safe managed binary path.

**Step 3: Write minimal implementation**

- 在 `WrapperCommandInstaller` 增加仅供集成链路使用的 helper，例如：
  - `ensureManagedBinaryAvailable()`
  - `managedBinaryPathForIntegrations()`
- 保证 Codex hooks 能直接调用 Application Support 下的绝对路径二进制
- 不把“安装到 PATH”与“给 hook 使用 managed binary”绑死

**Step 4: Re-run focused test**

Run: `swift test --filter WrapperCommandInstallerTests`
Expected: PASS

### Task 3: Add Codex hook installer and status detection

**Files:**
- Create: `Sources/VibeBarCore/CodexHookInstaller.swift`
- Create: `Sources/VibeBarApp/CodexHookViewModel.swift`
- Modify: `Sources/VibeBarApp/CLISettingsView.swift`
- Test: `Tests/VibeBarCoreTests/CodexHookInstallerTests.swift`

**Step 1: Write the failing test**

围绕临时目录 fixture 增加测试，覆盖：

- 首次安装会写入 `~/.codex/hooks.json`
- 会确保 `~/.codex/config.toml` 含 `[features] codex_hooks = true`
- 重复安装不会重复追加 managed hooks
- 卸载只删自己的条目，不破坏用户原有 hook

**Step 2: Run test to verify it fails**

Run: `swift test --filter CodexHookInstallerTests`
Expected: FAIL because installer does not exist yet.

**Step 3: Write minimal implementation**

- `CodexHookInstaller` 负责：
  - 检测 Codex 是否已安装
  - 生成 hook command，格式为 `"<managed-vibebar-abs-path>" codex-hook`
  - 写入/更新 `~/.codex/hooks.json`
  - 修复 `~/.codex/config.toml` 的 `codex_hooks = true`
- 先接入 6 个事件：
  - `SessionStart`
  - `SessionEnd`
  - `UserPromptSubmit`
  - `PreToolUse`
  - `PostToolUse`
  - `Stop`
- `CodexHookViewModel` 负责 settings 页 install / uninstall / refresh 状态

**Step 4: Re-run focused test**

Run: `swift test --filter CodexHookInstallerTests`
Expected: PASS

### Task 4: Add a dedicated Codex hook bridge instead of overloading `notify`

**Files:**
- Create: `Sources/VibeBarCore/CodexHookEventBridge.swift`
- Modify: `Sources/VibeBarCLI/main.swift`
- Test: `Tests/VibeBarCoreTests/CodexHookEventBridgeTests.swift`

**Step 1: Write the failing test**

为 bridge 纯函数增加测试，覆盖：

- `SessionStart` -> `AgentEvent(eventType: "session_start", status: .running)`
- `Stop` -> `AgentEvent(eventType: "stop", status: .idle)`
- `SessionEnd` -> `AgentEvent(eventType: "session_end", status: nil)`
- 保留 `session_id`、`cwd`、`hook_event_name`、`thread_name`、`prompt`、`tool_name`
- 注入 `_ppid`、TTY、tmux、bundle id 后能进入 metadata

**Step 2: Run test to verify it fails**

Run: `swift test --filter CodexHookEventBridgeTests`
Expected: FAIL because `codex-hook` subcommand does not exist.

**Step 3: Write minimal implementation**

- 在 core 中做一个可测试 bridge，把 stdin JSON + env + argv 映射成 `AgentEvent`
- 在 `vibebar` CLI 增加 `codex-hook` 子命令
- 不复用当前 `notify codex stop` 语义，避免 `Stop` 被误解析成 `session_end`
- bridge 直接把结果发到现有 `agent.sock`

**Step 4: Re-run focused test**

Run: `swift test --filter CodexHookEventBridgeTests`
Expected: PASS

### Task 5: Move agent-side event semantics into a testable reducer

**Files:**
- Create: `Sources/VibeBarCore/AgentEventReducer.swift`
- Modify: `Sources/VibeBarAgent/main.swift`
- Test: `Tests/VibeBarCoreTests/AgentEventReducerTests.swift`

**Step 1: Write the failing test**

增加 reducer tests，覆盖：

- `session_start` 创建/更新 session 为 `.running`
- `stop` 只改为 `.idle`，不删除 session
- `session_end` 删除 session
- `PostToolUse`/`PreToolUse` 维持 `.running`
- metadata 可回填 `title`、`currentTask`、`lastUserMessage`

**Step 2: Run test to verify it fails**

Run: `swift test --filter AgentEventReducerTests`
Expected: FAIL because reducer does not exist and current logic lives inside `VibeBarAgent/main.swift`.

**Step 3: Write minimal implementation**

- 把 `vibebar-agent` 里 Codex 相关状态变更逻辑迁到 core reducer
- `VibeBarAgent/main.swift` 只负责：
  - 读 socket
  - decode envelope / event
  - 调 reducer
  - 写 `SessionFileStore`
- 对终止事件做显式映射，不再用 `contains("stop")` 这类宽匹配清 session

**Step 4: Re-run focused test**

Run: `swift test --filter AgentEventReducerTests`
Expected: PASS

### Task 6: Upgrade Codex session fallback from “recent activity” to “turn-complete aware”

**Files:**
- Modify: `Sources/VibeBarCore/CodexSessionDetector.swift`
- Modify: `Sources/VibeBarCore/DetectorSupport.swift`
- Test: `Tests/VibeBarCoreTests/CodexSessionDetectorTests.swift`

**Step 1: Write the failing test**

在已有 `CodexSessionDetectorTests` 之外补：

- transcript tail 出现 `task_complete` -> idle anchor 取该时间
- transcript tail 出现 `turn_aborted` -> idle
- transcript tail 出现 `turn_failed` -> idle
- `state_5.sqlite` 里 `threads.rollout_path` 命中时优先使用该 rollout

**Step 2: Run test to verify it fails**

Run: `swift test --filter CodexSessionDetectorTests`
Expected: FAIL because detector does not yet use terminal-turn completion or SQLite lookup.

**Step 3: Write minimal implementation**

- 在 `CodexSessionDetector` 中增加“terminal turn completion timestamp”解析
- 新增从 `~/.codex/state_5.sqlite` 查 `threads.rollout_path` 的路径优先级
- 保留现有：
  - `CODEX_THREAD_ID` 关联
  - CWD fallback
  - in-flight tool call
  - CPU fallback

**Step 4: Re-run focused test**

Run: `swift test --filter CodexSessionDetectorTests`
Expected: PASS

### Task 7: Fix Codex merge priority between hook sessions, wrapper sessions, and session-file sessions

**Files:**
- Modify: `Sources/VibeBarApp/AppModel.swift`
- Modify: `Sources/VibeBarCore/CompositeSessionDetector.swift`
- Test: `Tests/VibeBarAppTests/AppModelTests.swift`

**Step 1: Write the failing test**

增加 merge tests，覆盖：

- 同 PID 下 `.plugin` Codex session 优先保留实时状态
- `.sessionFile` 只补齐 title / statusSince / idleSince / terminalContext
- `.wrapper` 不得覆盖更新更高优先级的 Codex hook session
- hook disabled 时 `.plugin` Codex session 会被过滤掉，但 `.sessionFile` 仍可显示恢复态

**Step 2: Run test to verify it fails**

Run: `swift test --filter AppModelTests`
Expected: FAIL because current merge path is still tuned around wrapper/plugin generic behavior.

**Step 3: Write minimal implementation**

- 在 `AppModel.merge()` 中增加来源优先级，而不是只按 `updatedAt`
- 对 Codex 明确规则：
  - `.plugin` 为实时真源
  - `.sessionFile` 为补全源
  - `.processScan` 为最低优先级兼容源
- 如有需要，在 `CompositeSessionDetector` 中避免 Codex fallback 误抑制 hook 实时链路

**Step 4: Re-run focused test**

Run: `swift test --filter AppModelTests`
Expected: PASS

### Task 8: Wire settings UX and end-to-end validation

**Files:**
- Modify: `Sources/VibeBarApp/CLISettingsView.swift`
- Modify: `Sources/VibeBarCLI/main.swift`
- Modify: `README.md`
- Modify: `AGENTS.md`

**Step 1: Finish UI wiring**

- 在 Codex 设置页显示：
  - CLI 安装状态
  - hook 安装状态
  - detection method toggle
  - “实时 hook / session file 兜底 / process scan 兼容”说明

**Step 2: Run focused tests**

Run: `swift test --filter CodexHookInstallerTests`
Expected: PASS

Run: `swift test --filter CodexHookEventBridgeTests`
Expected: PASS

Run: `swift test --filter AgentEventReducerTests`
Expected: PASS

Run: `swift test --filter CodexSessionDetectorTests`
Expected: PASS

Run: `swift test --filter AppModelTests`
Expected: PASS

**Step 3: Run full validation**

Run: `swift test`
Expected: PASS

Run: `swift build`
Expected: PASS

**Step 4: Manual verification**

- 安装 Codex hook 后启动 `codex`
- 验证 `SessionStart -> running`
- 做一次工具调用，验证仍保持 `running`
- 等 Codex 停止输出，验证 `Stop -> idle` 而不是消失
- 退出会话，验证 `SessionEnd` 后 session 被移除
- 杀掉 VibeBar 后重开，验证 `CodexSessionDetector` 能从 `~/.codex` 恢复会话标题和状态锚点

### Phase 2: Explicitly deferred from MVP

**Do not implement in MVP unless the above chain is stable:**

- Codex `PermissionRequest` / `AskUserQuestion` 的可点击回传
- `providerSessionID` 之类新的跨来源稳定 identity 字段
- 为 Codex 单独引入第二套长期驻留 socket server
- 复制 CodeIsland 的完整 `AppState` reducer 模型

这些点都可能是后续增强，但不应该阻塞第一版“精确状态监控”上线。

Plan complete and saved to `docs/plans/2026-04-16-codex-realtime-state-chain.md`. Two execution options:

**1. Subagent-Driven (this session)** - 我按任务逐个实现、逐步验证、每个阶段回报结果。

**2. Parallel Session (separate)** - 你开一个新会话，按这份计划分批执行。

**Which approach?**
