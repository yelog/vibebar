# Transcript Terminal Context Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 为 `claude` 和 `gemini` 的 transcript session 补齐终端上下文，并确保 transcript 结果缺少终端信息时仍保留 process scan fallback。

**Architecture:** 在 transcript detector 的进程筛选阶段把 `TerminalContextResolver.resolve(process:context:originHint:)` 的结果挂到进程信息上，再写入 `SessionSnapshot`。在 `CompositeSessionDetector` 中引入“是否所有 session 都已带 terminalContext”的判断，决定是否移除该工具的 `processScan` fallback。通过 core tests 覆盖 detector 与 composite 的回归。

**Tech Stack:** Swift 6.2, Swift Testing, VibeBarCore

---

### Task 1: 给 Claude transcript detector 增加 terminalContext

**Files:**
- Modify: `Sources/VibeBarCore/ClaudeTranscriptDetector.swift`
- Test: `Tests/VibeBarCoreTests/ClaudeTranscriptDetectorTests.swift`

**Step 1:** 为 `detectSessions` / `findClaudeProcesses` 增加测试友好的 `cwdByPID`、`now` 入口。

**Step 2:** 在 Claude 进程筛选时解析 `terminalContext`，写回 `ProcessInfo`。

**Step 3:** 在 transcript/fallback `SessionSnapshot` 构造时透传 `terminalContext`。

**Step 4:** 增加 Claude transcript detector 测试，验证 `kitty` 父进程链能解析出 `clientKind = .kitty`。

### Task 2: 给 Gemini transcript detector 增加 terminalContext

**Files:**
- Modify: `Sources/VibeBarCore/GeminiTranscriptDetector.swift`
- Modify: `Tests/VibeBarCoreTests/GeminiTranscriptDetectorTests.swift`

**Step 1:** 给 `ProcessInfo` 增加 `terminalContext`。

**Step 2:** 在 `findGeminiProcesses` 中解析并保存 `terminalContext`。

**Step 3:** 在 `SessionSnapshot` 构造时透传 `terminalContext`。

**Step 4:** 增加 Gemini transcript detector 测试，验证 `kitty` 父进程链解析。

### Task 3: 调整 composite fallback 条件

**Files:**
- Modify: `Sources/VibeBarCore/CompositeSessionDetector.swift`
- Modify: `Tests/VibeBarCoreTests/CompositeSessionDetectorTests.swift`

**Step 1:** 提炼 helper，判断某检测链路返回的 session 是否都已带 `terminalContext`。

**Step 2:** 用该 helper 替换 `gemini` / `claude` / `opencode` 的 “sessions 非空就移除 fallback” 逻辑。

**Step 3:** 增加 composite 测试，验证 transcript session 缺少 `terminalContext` 时仍保留 `.processScan`。

### Task 4: 运行验证

**Files:**
- Modify: `none`

**Step 1:** 运行新增相关测试。

**Step 2:** 运行 `swift test` 或至少运行 `VibeBarCoreTests`。

**Step 3:** 如无编译错误，整理变更说明与剩余风险。
