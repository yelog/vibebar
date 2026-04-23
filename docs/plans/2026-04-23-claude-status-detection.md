# Claude Status Detection Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 修复 Claude Code 空闲会话因焦点切换或瞬时 CPU 抖动被误判为 `running`，并确保安装 plugin 时由 plugin 作为 Claude 状态真源。

**Architecture:** 收紧 `ClaudeTranscriptDetector` 的 `running` 启发式，移除 CPU 直接触发 `running` 的逻辑，只保留 transcript 真实新活动驱动的运行态。再在 `MonitorViewModel.mergeDetectedDetails` 中为 Claude 增加 plugin 状态保护，让 transcript 只补充标题、摘要和终端上下文，不再覆盖 plugin 的状态字段。最后补两组回归测试覆盖无 plugin 和有 plugin 两条链路。

**Tech Stack:** Swift 6.2, Swift Testing, VibeBarCore, VibeBarApp

---

### Task 1: 为 Claude transcript 增加误判回归测试

**Files:**
- Modify: `Tests/VibeBarCoreTests/ClaudeTranscriptDetectorTests.swift`

**Step 1:** 新增一个只含历史 transcript 活动、但进程 CPU 高于阈值的测试样本。

**Step 2:** 调用 `ClaudeTranscriptDetector.detectSessions(context:cwdByPID:now:)` 或等价测试入口，验证该会话不会被识别成 `running`。

**Step 3:** 运行 `swift test --filter ClaudeTranscriptDetectorTests`，先确认测试在现状下失败或暴露问题。

### Task 2: 收紧 Claude transcript 的 running 判定

**Files:**
- Modify: `Sources/VibeBarCore/ClaudeTranscriptDetector.swift`

**Step 1:** 删除 `parseTranscript(path:cpuUsage:now:)` 中 `cpuUsage >= 0.5` 直接返回 `running` 的分支。

**Step 2:** 保留“最近 transcript 有新活动”的 `running` 判定，让 `awaitingInput` 继续由最后一条消息类型决定。

**Step 3:** 运行 `swift test --filter ClaudeTranscriptDetectorTests`，确认 Task 1 的回归测试转绿。

### Task 3: 为 Claude plugin 优先级增加合并回归测试

**Files:**
- Modify: `Tests/VibeBarAppTests/AppModelTests.swift`

**Step 1:** 新增一个 `merged` 为 Claude plugin 会话、`detectedSession` 为 Claude transcript 会话的合并测试。

**Step 2:** 验证合并后 Claude 的 `status`、`statusSince`、`idleSince`、`lastOutputAt`、`lastInputAt` 仍保持 plugin 原值。

**Step 3:** 同时验证 transcript 的 `title`、`lastUserMessage`、`runningSummary`、`terminalContext` 仍可正常回填。

**Step 4:** 运行 `swift test --filter AppModelTests`，先确认测试在现状下失败或暴露问题。

### Task 4: 保护 Claude plugin 的状态字段不被 transcript 覆盖

**Files:**
- Modify: `Sources/VibeBarApp/AppModel.swift`

**Step 1:** 在 `mergeDetectedDetails(into:from:)` 附近增加 Claude 专用保护逻辑。

**Step 2:** 当 `merged` 为 Claude plugin、`detectedSession` 为 Claude transcript 时，仅允许回填元数据，不允许覆盖状态字段。

**Step 3:** 尽量复用现有合并结构，避免引入新的全局策略或额外模型字段。

**Step 4:** 运行 `swift test --filter AppModelTests`，确认 Task 3 的回归测试转绿。

### Task 5: 全量验证与手动检查

**Files:**
- Modify: `none`

**Step 1:** 运行 `swift test --filter ClaudeTranscriptDetectorTests`。

**Step 2:** 运行 `swift test --filter AppModelTests`。

**Step 3:** 运行 `swift build`，确保 app 与 core 目标都能编译通过。

**Step 4:** 手动验证 Claude 长时间空闲后切换焦点，不再出现 `running / completed / running` 抖动。

## Notes

- 不自动创建 git commit，除非用户明确要求。
- 若后续确认 Claude plugin 已稳定安装，可再考虑把 Claude 默认配置进一步收敛为“plugin 主状态 + transcript 辅助信息”。
