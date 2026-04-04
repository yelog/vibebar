# Codex Session Detection Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 为 VibeBar 增加高可信的 Codex session 检测链路，并结构化识别终端 Client 与终端复用器归属。

**Architecture:** 先扩展 `SessionSnapshot` 和检测配置，给会话模型补齐 `title + terminalContext`；再新增 `TerminalContextResolver` 和 `CodexSessionDetector`，分别解决“终端归属识别”和“Codex 本地状态恢复”；最后把 hook、session 文件和 process scan 合并到现有刷新链路里，并用测试锁定关键规则。

**Tech Stack:** Swift 6.2, Foundation, AppKit-free core models, Swift Package Manager, XCTest

---

### Task 1: Extend session models for terminal context

**Files:**
- Modify: `Sources/VibeBarCore/Models.swift`
- Modify: `Sources/VibeBarCore/AgentEvents.swift`
- Test: `Tests/VibeBarCoreTests/HookContextTests.swift`

**Step 1: Write the failing test**

在 `HookContextTests` 中新增一个测试，断言 `TerminalContext` 和扩展后的 `SessionSnapshot` 可正确编码/解码。

**Step 2: Run test to verify it fails**

Run: `swift test --filter HookContextTests`
Expected: FAIL with missing `TerminalContext` or missing fields.

**Step 3: Write minimal implementation**

- 在 `Models.swift` 中新增：
  - `TerminalClientKind`
  - `SessionManagerKind`
  - `SessionOriginKind`
  - `TerminalContext`
- 在 `SessionSnapshot` 中新增：
  - `title`
  - `terminalContext`
- 在 `AgentEvents.swift` 中保留 metadata 兼容性，不改现有 JSON key。

**Step 4: Re-run focused test**

Run: `swift test --filter HookContextTests`
Expected: PASS

### Task 2: Add terminal environment resolver

**Files:**
- Create: `Sources/VibeBarCore/TerminalContextResolver.swift`
- Modify: `Sources/VibeBarCore/DetectorSupport.swift`
- Test: `Tests/VibeBarCoreTests/HookContextTests.swift`

**Step 1: Write the failing test**

为下面几类输入补纯函数测试：

- `TERM_PROGRAM=ghostty` -> `clientKind = .ghostty`
- `KITTY_WINDOW_ID=22` -> `clientKind = .kitty`
- `TMUX=/tmp/...` + `TMUX_PANE=%1` -> `sessionManagerKind = .tmux`
- `ZELLIJ=0` + `ZELLIJ_SESSION_NAME=dev` -> `sessionManagerKind = .zellij`

**Step 2: Run test to verify it fails**

Run: `swift test --filter HookContextTests`
Expected: FAIL with missing resolver or incorrect mapping.

**Step 3: Write minimal implementation**

- 在 `DetectorSupport` 增加：
  - 父进程链读取
  - 单进程环境变量读取
  - tty 解析工具
- 在 `TerminalContextResolver` 中实现：
  - metadata 输入解析
  - env 输入解析
  - 父进程名称兜底

**Step 4: Re-run focused test**

Run: `swift test --filter HookContextTests`
Expected: PASS

### Task 3: Add Codex local session detector

**Files:**
- Create: `Sources/VibeBarCore/CodexSessionDetector.swift`
- Modify: `Sources/VibeBarCore/CLISettingsConfiguration.swift`
- Modify: `Sources/VibeBarCore/CompositeSessionDetector.swift`
- Test: `Tests/VibeBarCoreTests/CodexSessionDetectorTests.swift`

**Step 1: Write the failing test**

新增 fixture 测试，给一个最小 `session_index.jsonl + rollout.jsonl` 输入，断言检测器输出：

- 正确 `sessionID`
- 正确 `title`
- 非空 `updatedAt`
- 状态可从 rollout 活动推断为 `running`

**Step 2: Run test to verify it fails**

Run: `swift test --filter CodexSessionDetectorTests`
Expected: FAIL with missing detector or parse logic.

**Step 3: Write minimal implementation**

- 新增 `CodexSessionDetector`
- 读取 `~/.codex/session_index.jsonl`
- 扫描 `~/.codex/sessions/**/rollout-*.jsonl`
- 容错解析坏行 JSON
- 新增 Codex 的 detection method，例如 `sessionFile`
- 在 `CompositeSessionDetector` 中按高于 `processScan` 的优先级接入

**Step 4: Re-run focused test**

Run: `swift test --filter CodexSessionDetectorTests`
Expected: PASS

### Task 4: Merge hook metadata into structured session snapshots

**Files:**
- Modify: `Sources/VibeBarAgent/main.swift`
- Modify: `Sources/VibeBarCore/SessionFileStore.swift`
- Test: `Tests/VibeBarCoreTests/HookContextTests.swift`

**Step 1: Write the failing test**

增加一个测试，断言带终端 metadata 的 `AgentEvent` 落盘后能恢复 `terminalContext`。

**Step 2: Run test to verify it fails**

Run: `swift test --filter HookContextTests`
Expected: FAIL because `vibebar-agent` 仍只写备注。

**Step 3: Write minimal implementation**

- 在 `vibebar-agent` 中把 metadata 交给 `TerminalContextResolver`
- 写入 `title`、`terminalContext`
- 保持现有 `notes` 输出兼容

**Step 4: Re-run focused test**

Run: `swift test --filter HookContextTests`
Expected: PASS

### Task 5: Refine Codex state resolution and refresh merge

**Files:**
- Modify: `Sources/VibeBarCore/CodexSessionDetector.swift`
- Modify: `Sources/VibeBarApp/AppModel.swift`
- Test: `Tests/VibeBarCoreTests/CodexSessionDetectorTests.swift`

**Step 1: Write the failing test**

补状态决策测试，覆盖：

- rollout 活动新鲜 -> `running`
- 明确等待用户事件 -> `awaiting_input`
- 进程存活但近期无活动 -> `idle`
- 无活动且进程不存在 -> `unknown`

**Step 2: Run test to verify it fails**

Run: `swift test --filter CodexSessionDetectorTests`
Expected: FAIL due to incomplete state mapping.

**Step 3: Write minimal implementation**

- 抽一个纯函数做状态决策
- 在 `AppModel.merge` 中确保 Codex session file 来源不会被 process scan 误覆盖
- 保持 wrapper 和已有 plugin 逻辑不回归

**Step 4: Re-run focused test**

Run: `swift test --filter CodexSessionDetectorTests`
Expected: PASS

### Task 6: Build and smoke-test the full chain

**Files:**
- Modify: `README.md`
- Modify: `CLAUDE.md`

**Step 1: Update docs**

- 更新 README 中 Codex 推荐接入方式说明
- 更新架构说明，补充 Codex 本地 session 检测链路

**Step 2: Run full validation**

Run: `swift test`
Expected: PASS

Run: `swift build`
Expected: PASS

**Step 3: Manual verification**

- 用已存在的 `~/.codex` 数据确认可以看到 Codex session title
- 用 `tmux` 或环境变量 fixture 确认 `sessionManagerKind` 可识别
- 检查 `~/Library/Application Support/VibeBar/sessions/*.json` 是否包含 `terminalContext`

**Step 4: Commit**

```bash
git add docs/plans/2026-04-04-codex-session-detection-design.md \
        docs/plans/2026-04-04-codex-session-detection.md \
        Sources/VibeBarCore/Models.swift \
        Sources/VibeBarCore/AgentEvents.swift \
        Sources/VibeBarCore/DetectorSupport.swift \
        Sources/VibeBarCore/TerminalContextResolver.swift \
        Sources/VibeBarCore/CodexSessionDetector.swift \
        Sources/VibeBarCore/CompositeSessionDetector.swift \
        Sources/VibeBarCore/CLISettingsConfiguration.swift \
        Sources/VibeBarAgent/main.swift \
        Sources/VibeBarApp/AppModel.swift \
        Tests/VibeBarCoreTests/HookContextTests.swift \
        Tests/VibeBarCoreTests/CodexSessionDetectorTests.swift \
        README.md \
        CLAUDE.md
git commit -m "feat(codex): add structured session detection"
```
