# Agent Stale Running Recovery Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 消除 Agent 进程探测线程泄漏，并让 OpenCode 已完成但插件心跳中断的会话可靠恢复为 `idle`。

**Architecture:** 先修复共享子进程执行器的超时收敛，再让 Agent heartbeat 优先复用事件 metadata 和已保存终端上下文。OpenCode 插件使用 assistant finish 发送直接完成信号，SQLite detector 提供独立的持久化终态，AppModel 只在插件状态过期且 detector 证据更新时执行状态校正。

**Tech Stack:** Swift 6.2、Foundation `Process`/`Pipe`、Swift Testing、Node.js `node:test`、SQLite JSON1、Unix domain socket。

---

### Task 1: 修复子进程超时收敛

**Files:**
- Modify: `Sources/VibeBarCore/DetectorSupport.swift:388-464`
- Create: `Tests/VibeBarCoreTests/DetectorSupportProcessTests.swift`

**Step 1: 写失败测试**

将 `runProcessOutput` 调整为 `internal`，并允许测试传入短 timeout。测试覆盖：

```swift
@Test func processOutputReturnsAfterSuccessfulCommand() {
    let output = DetectorSupport.runProcessOutput(
        executablePath: "/bin/sh",
        arguments: ["-c", "printf ready"],
        timeout: 1
    )
    #expect(String(data: output ?? Data(), encoding: .utf8) == "ready")
}

@Test func repeatedProcessTimeoutsRemainBounded() {
    let startedAt = Date()
    for _ in 0..<80 {
        let output = DetectorSupport.runProcessOutput(
            executablePath: "/bin/sh",
            arguments: ["-c", "sleep 5"],
            timeout: 0.01
        )
        #expect(output == nil)
    }
    #expect(Date().timeIntervalSince(startedAt) < 5)
}
```

**Step 2: 运行测试并确认失败或暴露资源耗尽**

Run: `swift test --filter DetectorSupportProcessTests`

Expected: 新测试无法访问 private 方法，或重复超时后测试明显变慢/遗留后台工作。

**Step 3: 实现最小修复**

- 将 stderr 设置为 `FileHandle.nullDevice`。
- 在 `Process.run()` 前设置 `terminationHandler` 并用独立 semaphore 表示进程终止。
- 后台任务只负责 `readDataToEndOfFile()`，完成后保存输出并 signal，不调用 `waitUntilExit()`。
- 正常路径等待 termination 和 output 两个信号。
- 超时路径依次调用 terminate、等待宽限、kill、等待最终终止和 reader 收敛。
- 仅在进程正常终止且 output reader 完成时返回数据。

**Step 4: 运行定向测试**

Run: `swift test --filter DetectorSupportProcessTests`

Expected: PASS，80 次超时在时间上有界。

**Step 5: 运行受影响 Core 测试**

Run: `swift test --filter VibeBarCoreTests`

Expected: PASS。

### Task 2: 移除 Agent heartbeat 的重复进程扫描

**Files:**
- Modify: `Sources/VibeBarAgent/main.swift:211-236`
- Test: `Tests/VibeBarCoreTests/HookContextTests.swift`

**Step 1: 写 metadata 终端上下文回归测试**

为 `TerminalContextResolver` 增加测试，使用空 process chain 和 OpenCode 插件实际发送的 metadata：

```swift
let context = TerminalContextResolver.resolve(metadata: [
    "_tty": "ttys001",
    "KITTY_WINDOW_ID": "3",
    "KITTY_LISTEN_ON": "unix:/tmp/kitty-test",
    "__CFBundleIdentifier": "net.kovidgoyal.kitty",
    "source": "cli",
])

#expect(context?.clientKind == .kitty)
#expect(context?.tty == "ttys001")
#expect(context?.clientWindowID == "3")
```

**Step 2: 运行测试确认当前 metadata 解析能力**

Run: `swift test --filter HookContextTests`

Expected: PASS；该测试锁定后续 Agent 快速路径依赖的能力。

**Step 3: 修改 Agent 上下文解析顺序**

在 `apply(event:)` 中：

```swift
let metadataContext = TerminalContextResolver.resolve(
    metadata: event.metadata,
    originHint: originHint(for: event)
)
let detectedContext: TerminalContext?
if metadataContext == nil && previous?.terminalContext == nil, let pid = event.pid {
    detectedContext = TerminalContextResolver.resolve(
        metadata: event.metadata,
        processChain: storeProcessChain(for: pid),
        originHint: originHint(for: event)
    )
} else {
    detectedContext = metadataContext
}
let terminalContext = TerminalContextResolver.merge(
    primary: detectedContext,
    fallback: previous?.terminalContext
)
```

这样 heartbeat 在已有 metadata 或历史上下文时不调用 `DetectorSupport.makeContext()`。

**Step 4: 构建 Agent**

Run: `swift build --target VibeBarAgent`

Expected: PASS，Swift 6 strict concurrency 无新增错误。

### Task 3: 增加 OpenCode 直接完成事件

**Files:**
- Modify: `plugins/opencode-vibebar-plugin/index.js:772-776`
- Modify: `plugins/opencode-vibebar-plugin/index.test.js`

**Step 1: 写失败测试**

增加三个测试：

- assistant `finish: "tool-calls"` 不发 `idle`。
- assistant `finish: "stop"` 发 `idle`。
- pending question 时 assistant `finish: "stop"` 仍保持 `awaiting_input`。

事件示例：

```js
await fixture.plugin.event({
  event: {
    type: "message.updated",
    properties: {
      info: { id: "assistant-msg", role: "assistant", finish: "stop" },
    },
  },
});
assert.deepEqual(statusSequence(fixture.events), ["idle"]);
```

**Step 2: 运行测试确认失败**

Run: `node --test plugins/opencode-vibebar-plugin/index.test.js`

Expected: `finish: "stop"` 测试 FAIL，当前实现只保存 role。

**Step 3: 实现 finish 状态映射**

在 `message.updated` 分支：

- 继续维护 `messageRoles`。
- 仅处理 `role === "assistant"` 且 `finish` 为非空字符串。
- `finish === "tool-calls"` 直接返回。
- 有 pending interaction 时 emit `awaiting_input`。
- 否则清除 permission pending，强制设置 `idle` 并 emit。

**Step 4: 运行插件测试**

Run: `node --test plugins/opencode-vibebar-plugin/index.test.js`

Expected: PASS。

### Task 4: 从 SQLite 提取可靠 OpenCode 状态

**Files:**
- Modify: `Sources/VibeBarCore/OpenCodeHTTPDetector.swift:279-487`
- Modify: `Tests/VibeBarCoreTests/OpenCodeHTTPDetectorTests.swift`

**Step 1: 扩展 SQLite fixture 并写失败测试**

测试数据库增加 `message` 表和 JSON `data`。覆盖：

- 最新 assistant message `finish=stop` 返回 `idle`。
- 最新 assistant message `finish=tool-calls` 返回 `running`。
- 最新 message 为 user 返回 `running`。
- 无 message 或 JSON 无法解析时退回现有 CPU 启发式。

**Step 2: 运行 detector 测试确认失败**

Run: `swift test --filter OpenCodeHTTPDetectorTests`

Expected: 新增终态测试 FAIL，当前 SQLite fallback 只读取 session 表和 CPU。

**Step 3: 实现状态查询**

给 `SQLiteSessionInfo` 增加可选的可靠状态。按 session ID 查询：

```sql
SELECT
  json_extract(data, '$.role'),
  json_extract(data, '$.finish')
FROM message
WHERE session_id = ?
ORDER BY time_created DESC, id DESC
LIMIT 1
```

映射规则：

- 最新 assistant 且 finish 非空、非 `tool-calls`：`idle`。
- 最新 user、assistant 无 finish、assistant `tool-calls`：`running`。
- 无有效记录：`nil`，继续使用 CPU fallback。

构建快照时优先使用可靠状态，并让 `statusSince`/`idleSince` 使用 SQLite 更新时间。

**Step 4: 运行 detector 测试**

Run: `swift test --filter OpenCodeHTTPDetectorTests`

Expected: PASS。

### Task 5: 校正 stale plugin running

**Files:**
- Modify: `Sources/VibeBarApp/AppModel.swift:1552-1665`
- Modify: `Tests/VibeBarAppTests/AppModelTests.swift`

**Step 1: 写失败测试**

构造同 PID 的两条快照：

- file session：OpenCode plugin、`running`、updatedAt 比 now 早 46 秒。
- detected session：OpenCode sessionFile、`idle`、updatedAt 晚于 plugin。

断言 merge 后状态为 `idle`，且标题等插件高质量 metadata 保留。

再增加反例：

- plugin heartbeat 未过期时不覆盖。
- detected 状态比 plugin 旧时不覆盖。
- Claude plugin 不应用此规则。
- OpenCode `awaiting_input` 不应用此规则。

**Step 2: 运行测试确认失败**

Run: `swift test --filter AppModelTests`

Expected: stale OpenCode plugin 仍为 `running`。

**Step 3: 实现窄范围校正**

在按 PID 匹配 detected session 后、通用 metadata merge 之后，仅当以下条件全部成立时采用 detected 状态：

- file session 和 detected session 都是 OpenCode。
- file session 来源是 plugin，状态是 `running`。
- `now - fileSession.updatedAt > pluginStaleTTL`。
- detected 状态是 `idle`。
- detected `updatedAt > fileSession.updatedAt`。

同步更新 `statusSince`、`idleSince`，清除 pending interaction ID；不替换插件标题、任务摘要和终端上下文。

**Step 4: 运行 App 测试**

Run: `swift test --filter AppModelTests`

Expected: PASS。

### Task 6: 完整验证与现场恢复

**Files:**
- Verify only; do not modify unrelated files.

**Step 1: 运行完整自动化测试**

Run: `swift test`

Expected: PASS。

Run: `node --test plugins/opencode-vibebar-plugin/index.test.js`

Expected: PASS。

**Step 2: 构建所有 target**

Run: `swift build`

Expected: PASS。

**Step 3: 检查变更范围**

Run: `git diff --check`

Expected: 无 whitespace 错误。

Run: `git status --short`

Expected: 只包含本方案涉及文件和用户已有改动；不回滚其他变更。

**Step 4: 重启本地 VibeBar Agent**

通过 VibeBar 自身的 Agent launch coordinator 或重启 VibeBarApp 触发受控重启，不直接删除 session 数据。

Expected: 原有约 3200 个 socket 和阻塞线程被释放，新 Agent 开始接收 heartbeat。

**Step 5: 进行现场压力验证**

- 保持至少三个 OpenCode 会话运行 2 分钟。
- 确认 session JSON 的 `updatedAt` 每约 15 秒刷新。
- 对比 Agent 的线程数和 Unix socket 数，确认不随 heartbeat 单调增长。
- 触发一个短 OpenCode 请求，确认最终 assistant 输出后一个刷新周期内显示 `idle`。
- 暂时阻断插件事件，确认 SQLite 终态能在 stale 窗口后校正旧 `running`。

Expected: 无持续 FD/线程增长，完成状态可直接更新并可自愈。

> 本计划不执行 commit；只有用户明确要求时才暂存或提交文件。
