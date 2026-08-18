# Duplicate Session ID Crash Fix Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 消除 OpenCode 检测产生重复 `SessionSnapshot.id` 的根因，并保证任何异常检测数据都不能再通过字典构造导致 VibeBarApp 崩溃。

**Architecture:** 在 OpenCode SQLite fallback 中只建立无歧义的一对一进程/会话关联；在 `CompositeSessionDetector` 输出边界按最终 session ID 再归并一次；App 层所有依赖唯一 ID 的字典构造改为可检测或可确定处理重复值。保持 `SessionSnapshot.id` 的逻辑会话语义，不把 PID 拼入已有 OpenCode session ID。

**Tech Stack:** Swift 6.2、Swift Package Manager、Swift Testing、Foundation、SQLite3、AppKit

---

## Correctness Invariants

实施后必须始终满足：

1. `CompositeSessionDetector.detectSessions()` 返回值中 `SessionSnapshot.id` 唯一。
2. OpenCode 进程仅在有显式 `-s/--session` 参数，或该 CWD 只有一个未关联进程时，才复用 SQLite session ID。
3. 多个无法区分的同 CWD OpenCode 进程使用 `opencode-http-pid-<pid>`，不猜测它们分别对应哪个数据库 session。
4. `sessionsAreSemanticallyEqual` 遇到重复 ID 返回 `false`，绝不 trap。
5. 状态通知逻辑遇到重复 ID 时确定性选取一条记录，绝不 trap，也不对同一个 ID 重复触发状态转换。

## Non-Goals

- 不修改 `SessionSnapshot` 公共模型。
- 不把 PID 添加到已有 `opencode-http-<sessionID>`，避免破坏逻辑会话身份。
- 不引入新的持久化格式或迁移。
- 不基于进程启动时间猜测多个同 CWD 进程分别对应哪个 SQLite session；当前数据不足以可靠完成这种关联。
- 不顺带重写 OpenCode HTTP API 或进程识别逻辑。

### Task 1: Make Semantic Comparison Non-Crashing

**Files:**
- Modify: `Sources/VibeBarApp/AppModel.swift:477-498`
- Test: `Tests/VibeBarAppTests/AppModelTests.swift:716-772`

**Step 1: Write the failing regression test**

在现有 semantic refresh 测试旁新增：

```swift
@Test func semanticRefreshResultRejectsDuplicateSessionIDsWithoutCrashing() {
    let base = makeSemanticSession(id: "duplicate")
    var duplicate = base
    duplicate.pid += 1

    #expect(MonitorViewModel.sessionsAreSemanticallyEqual([], [base, duplicate]) == false)
    #expect(MonitorViewModel.sessionsAreSemanticallyEqual([base, duplicate], []) == false)
}
```

测试必须同时覆盖重复值出现在 `lhs` 和 `rhs` 的情况，因为当前实现两侧都使用 `Dictionary(uniqueKeysWithValues:)`。

**Step 2: Run the test and verify the current implementation crashes/fails**

Run:

```bash
swift test --filter semanticRefreshResultRejectsDuplicateSessionIDsWithoutCrashing
```

Expected: 测试进程因 `Duplicate values for key` 失败，证明回归测试命中原始 fatal error。

**Step 3: Replace the trapping dictionary initialization**

在 `sessionsAreSemanticallyEqual` 中显式构建索引并检查重复 ID：

```swift
nonisolated static func sessionsAreSemanticallyEqual(
    _ lhs: [SessionSnapshot],
    _ rhs: [SessionSnapshot]
) -> Bool {
    guard lhs.count == rhs.count else { return false }

    var lhsByID: [String: SessionSnapshot] = [:]
    lhsByID.reserveCapacity(lhs.count)
    for session in lhs {
        guard lhsByID.updateValue(session, forKey: session.id) == nil else {
            return false
        }
    }

    var rhsByID: [String: SessionSnapshot] = [:]
    rhsByID.reserveCapacity(rhs.count)
    for session in rhs {
        guard rhsByID.updateValue(session, forKey: session.id) == nil else {
            return false
        }
    }

    for (id, lhsSession) in lhsByID {
        guard let rhsSession = rhsByID[id],
              sessionIsSemanticallyEqual(lhsSession, rhsSession) else {
            return false
        }
    }
    return true
}
```

不要使用 `uniquingKeysWith` 静默覆盖，因为 semantic comparison 应把重复 ID 视为无效且已变化的数据。

**Step 4: Run focused AppModel tests**

Run:

```bash
swift test --filter semanticRefreshResult
```

Expected: 所有 semantic refresh 测试通过，包括重复 ID 回归测试。

**Step 5: Commit the isolated defensive fix**

```bash
git add Sources/VibeBarApp/AppModel.swift Tests/VibeBarAppTests/AppModelTests.swift
git commit -m "fix(app): avoid duplicate session id comparison crash"
```

### Task 2: Enforce Unique IDs at the Composite Detector Boundary

**Files:**
- Modify: `Sources/VibeBarCore/CompositeSessionDetector.swift:185-202`
- Test: `Tests/VibeBarCoreTests/CompositeSessionDetectorTests.swift`

**Step 1: Write a failing detector-boundary test**

使用现有 provider 注入接口，让 OpenCode provider 返回相同 ID、不同 PID 的记录：

```swift
@Test func compositeDetectorReturnsOneSessionForDuplicateLogicalIDAcrossProcesses() async throws {
    let detector = CompositeSessionDetector(
        codexSessionEnabled: false,
        openCodeHTTPEnabled: true,
        geminiTranscriptEnabled: false,
        claudeTranscriptEnabled: false,
        processScanTools: [],
        openCodeSessionProvider: { _ in
            [
                SessionSnapshot(
                    id: "opencode-http-ses-shared",
                    tool: .opencode,
                    pid: 101,
                    status: .idle,
                    source: .sessionFile,
                    startedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
                    cwd: "/Users/test/project",
                    command: ["opencode"],
                    title: "Shared session"
                ),
                SessionSnapshot(
                    id: "opencode-http-ses-shared",
                    tool: .opencode,
                    pid: 202,
                    status: .idle,
                    source: .sessionFile,
                    startedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    updatedAt: Date(timeIntervalSince1970: 1_700_000_090),
                    cwd: "/Users/test/project",
                    command: ["opencode"]
                ),
            ]
        }
    )

    let sessions = await detector.detectSessions(
        context: DetectorSupport.DetectionContext(processes: [])
    )

    let session = try #require(sessions.first)
    #expect(sessions.count == 1)
    #expect(session.id == "opencode-http-ses-shared")
    #expect(session.title == "Shared session")
}
```

**Step 2: Run the test and verify it fails**

Run:

```bash
swift test --filter compositeDetectorReturnsOneSessionForDuplicateLogicalIDAcrossProcesses
```

Expected: FAIL，`sessions.count` 当前为 `2`。

**Step 3: Add a second merge pass by final session ID**

保留现有按 `tool + pid` 的第一阶段归并，因为它负责合并同一进程的 transcript/process/API 信息。第一阶段完成后，再按最终 `id` 分组并复用 `mergeGroup`：

```swift
private func mergeAndDeduplicate(sessions: [SessionSnapshot]) -> [SessionSnapshot] {
    var groupedByProcess: [String: [SessionSnapshot]] = [:]
    for session in sessions {
        let key = session.pid > 0 ? "\(session.tool.rawValue)-\(session.pid)" : session.id
        groupedByProcess[key, default: []].append(session)
    }

    let mergedByProcess = groupedByProcess.values.compactMap(mergeGroup)
    var groupedByID: [String: [SessionSnapshot]] = [:]
    for session in mergedByProcess {
        groupedByID[session.id, default: []].append(session)
    }

    return groupedByID.values.compactMap(mergeGroup)
}
```

如果测试暴露完全同分候选导致结果不稳定，则在 `selectBest` 的最后增加稳定 tie-break：优先 `updatedAt` 更新者，再优先较小 PID。不要改变现有 source priority、richness 或状态优先规则。

**Step 4: Add an invariant assertion in the test**

在测试中追加：

```swift
#expect(Set(sessions.map(\.id)).count == sessions.count)
```

并在已有“保留 unmatched live process”测试中追加同样断言，防止第二次归并误删不同 ID 的正常进程。

**Step 5: Run all composite detector tests**

Run:

```bash
swift test --filter CompositeSessionDetectorTests
```

Expected: 全部通过；同 PID 不同来源仍能合并，不同 PID 不同 ID 仍全部保留，相同 ID 最终只保留一条。

**Step 6: Commit the detector invariant**

```bash
git add Sources/VibeBarCore/CompositeSessionDetector.swift Tests/VibeBarCoreTests/CompositeSessionDetectorTests.swift
git commit -m "fix(core): deduplicate detected sessions by logical id"
```

### Task 3: Prevent Ambiguous OpenCode SQLite Associations

**Files:**
- Modify: `Sources/VibeBarCore/OpenCodeHTTPDetector.swift:280-379`
- Test: `Tests/VibeBarCoreTests/OpenCodeHTTPDetectorTests.swift`

**Step 1: Add a failing same-CWD fixture test**

复用 `OpenCodeHTTPDetectorTests` 已有临时 SQLite fixture，写入一个 root session，并创建两个没有 `-s/--session` 参数、CWD 相同的进程：

```swift
@Test func sqliteFallbackDoesNotReuseOneSessionForAmbiguousSameCWDProcesses() throws {
    let fixture = try OpenCodeDetectorFixture()
    defer { fixture.cleanup() }

    let cwd = "/Users/test/shared-project"
    try fixture.insertSession(
        id: "ses-shared",
        directory: cwd,
        createdAt: 1_700_000_100_000,
        updatedAt: 1_700_000_200_000
    )

    let first = makeOpenCodeProcess(pid: 101, elapsedSeconds: 300, args: "opencode")
    let second = makeOpenCodeProcess(pid: 202, elapsedSeconds: 200, args: "opencode")
    let detector = OpenCodeHTTPDetector(dataDirectory: fixture.dataDirectory)

    let sessions = detector.loadSessionsFromSQLite(
        processes: [first, second],
        cwds: [101: cwd, 202: cwd],
        now: Date(timeIntervalSince1970: 1_700_000_300)
    )

    #expect(sessions.count == 2)
    #expect(sessions.allSatisfy { $0.sessionId == nil })
}
```

根据现有 fixture helper 的实际名称调整初始化和 `insertSession` 参数，不新增第二套 SQLite 测试基建。

**Step 2: Run the test and verify it fails**

Run:

```bash
swift test --filter sqliteFallbackDoesNotReuseOneSessionForAmbiguousSameCWDProcesses
```

Expected: FAIL，当前两条结果都会得到 `ses-shared`。

**Step 3: Add a failing explicit-session precedence test**

新增场景：两个进程 CWD 相同，其中一个参数为 `opencode -s ses-shared`。期望只有显式进程关联 `ses-shared`，另一个进程得到 `nil`：

```swift
#expect(sessions.first { $0.process.pid == 101 }?.sessionId == "ses-shared")
#expect(sessions.first { $0.process.pid == 202 }?.sessionId == nil)
```

这保证显式 session 参数始终优先于 CWD fallback，且已认领 session 不会再次分配。

**Step 4: Refactor SQLite association into two passes**

在 `loadSessionsFromSQLite` 中按以下顺序处理，并保持最终结果与输入 `processes` 顺序一致：

1. 第一遍解析所有进程的显式 `-s/--session`，成功查询后写入 `resultByPID`，并把 session ID 放入 `claimedSessionIDs`。
2. 对未关联进程批量读取 CWD，按规范化 CWD 分组。
3. 只有某个 CWD 恰好对应一个未关联进程时，才调用现有 `querySessionByCwd`。
4. CWD 查询结果若已在 `claimedSessionIDs` 中，则拒绝复用。
5. 其他进程生成 `sessionId: nil` 的 `SQLiteSessionInfo`，后续自然得到 `opencode-http-pid-<pid>`。

核心结构应保持局部，不新增公共类型：

```swift
var resultByPID: [Int32: SQLiteSessionInfo] = [:]
var claimedSessionIDs = Set<String>()

// Pass 1: explicit IDs.
for process in processes {
    guard let sessionID = parseSessionIdFromArgs(process.args),
          let info = querySessionById(database: database, sessionId: sessionID) else {
        continue
    }
    resultByPID[process.pid] = makeSQLiteSessionInfo(process: process, query: info, fallbackCWD: cwds[process.pid])
    claimedSessionIDs.insert(sessionID)
}

let unresolved = processes.filter { resultByPID[$0.pid] == nil }
let unresolvedByCWD = Dictionary(grouping: unresolved) { cwds[$0.pid] }

for (cwd, candidates) in unresolvedByCWD {
    guard let cwd, !cwd.isEmpty, cwd != "/", candidates.count == 1,
          let process = candidates.first,
          let info = querySessionByCwd(database: database, cwd: cwd),
          let sessionID = info.sessionId,
          !claimedSessionIDs.contains(sessionID),
          shouldReuseCwdFallback(info: info, process: process, now: now) else {
        continue
    }
    resultByPID[process.pid] = makeSQLiteSessionInfo(process: process, query: info, fallbackCWD: cwd)
    claimedSessionIDs.insert(sessionID)
}

return processes.map { process in
    resultByPID[process.pid] ?? unmatchedSQLiteSessionInfo(
        process: process,
        cwd: cwds[process.pid],
        now: now
    )
}
```

`makeSQLiteSessionInfo` 和 `unmatchedSQLiteSessionInfo` 仅在重复构造代码明显降低可读性时提取为 private helper；否则直接在函数内构造，避免不必要抽象。

**Step 5: Preserve existing freshness behavior**

确保无歧义 CWD fallback 仍调用 `shouldReuseCwdFallback`，以下现有行为不能回归：

- 新进程不继承很久以前创建的同项目 session。
- 显式 session ID 可直接查询。
- reliable SQLite message status 继续覆盖 CPU fallback。
- 找不到 session 时仍返回进程级 snapshot，而不是丢弃进程。

**Step 6: Run all OpenCode detector tests**

Run:

```bash
swift test --filter OpenCodeHTTPDetectorTests
```

Expected: 新增同 CWD 与显式优先测试通过，现有 freshness/status/CWD 测试全部通过。

**Step 7: Commit the source correction**

```bash
git add Sources/VibeBarCore/OpenCodeHTTPDetector.swift Tests/VibeBarCoreTests/OpenCodeHTTPDetectorTests.swift
git commit -m "fix(opencode): avoid ambiguous sqlite session reuse"
```

### Task 4: Make Notification State Indexing Defensive

**Files:**
- Modify: `Sources/VibeBarApp/StatusItemController.swift:329-423`
- Create: `Tests/VibeBarAppTests/StatusItemSessionIndexTests.swift`

**Step 1: Write a pure helper regression test**

不要实例化 `StatusItemController`，因为其初始化会创建真实 `NSStatusItem` 并绑定全局 model。为索引逻辑增加一个 `nonisolated static` internal helper，并直接测试：

```swift
@Test func statusItemSessionIndexKeepsOneDeterministicValueForDuplicateID() throws {
    let older = makeStatusItemSession(
        id: "duplicate",
        pid: 101,
        status: .running,
        updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let newer = makeStatusItemSession(
        id: "duplicate",
        pid: 202,
        status: .idle,
        updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
    )

    let indexed = StatusItemController.indexSessionsByID([older, newer])

    #expect(indexed.count == 1)
    #expect(indexed["duplicate"]?.pid == 202)
    #expect(indexed["duplicate"]?.status == .idle)
}
```

测试 helper 可在新测试文件内提供最小 `makeStatusItemSession` fixture，或复用已有可见 fixture；不要扩大生产 API。

**Step 2: Run the test and verify it fails to compile**

Run:

```bash
swift test --filter statusItemSessionIndexKeepsOneDeterministicValueForDuplicateID
```

Expected: FAIL，因为 `indexSessionsByID` 尚不存在。

**Step 3: Implement deterministic non-trapping indexing**

在 `StatusItemController` 中增加：

```swift
nonisolated static func indexSessionsByID(
    _ sessions: [SessionSnapshot]
) -> [String: SessionSnapshot] {
    sessions.reduce(into: [:]) { result, session in
        guard let existing = result[session.id] else {
            result[session.id] = session
            return
        }

        if session.updatedAt > existing.updatedAt ||
            (session.updatedAt == existing.updatedAt && session.pid < existing.pid) {
            result[session.id] = session
        }
    }
}
```

选择规则必须与输入顺序无关：先选 `updatedAt` 更新者；时间相同选较小 PID。

**Step 4: Use one canonical list throughout transition handling**

在 `notifyStateTransitionsIfNeeded` 开始处构建：

```swift
let currentSessionsByID = Self.indexSessionsByID(sessions)
let canonicalSessions = Array(currentSessionsByID.values)
let currentStates = currentSessionsByID.mapValues(\.status)
```

随后将该函数内以下计算全部改为基于 `canonicalSessions` 或字典 key：

- `waitingIDs`
- `idleIDs`
- `currentSessionIDs`
- 最终状态转换循环

这样防御逻辑不仅避免字典 trap，也避免相同 ID 在同一次刷新中触发两次 hook/notification。

**Step 5: Add input-order stability coverage**

在测试中反转输入并确认结果相同：

```swift
let reversed = StatusItemController.indexSessionsByID([newer, older])
#expect(reversed["duplicate"]?.pid == indexed["duplicate"]?.pid)
```

**Step 6: Run focused tests**

Run:

```bash
swift test --filter StatusItemSessionIndexTests
```

Expected: 全部通过，无需创建真实菜单栏 UI。

**Step 7: Commit the consumer defense**

```bash
git add Sources/VibeBarApp/StatusItemController.swift Tests/VibeBarAppTests/StatusItemSessionIndexTests.swift
git commit -m "fix(app): handle duplicate ids in session notifications"
```

### Task 5: Integration Verification

**Files:**
- Verify only; no planned source changes

**Step 1: Run the complete test suite**

Run:

```bash
swift test
```

Expected: 全部测试通过，无 crash、compile error 或 Swift 6 concurrency warning promoted to error。

**Step 2: Build the debug application**

Run:

```bash
swift build --product VibeBarApp
```

Expected: `Build complete!`。

**Step 3: Reproduce the original process topology**

准备两个位于同一 CWD、没有显式 `-s/--session` 的 OpenCode 进程。不要删除用户现有 OpenCode 数据库或 session 文件。

Run:

```bash
swift run VibeBarApp
```

Expected:

- 应用连续运行至少两个正常刷新周期，不出现 `Duplicate values for key`。
- 两个歧义进程以 PID fallback 身份显示，或经其他更可靠来源正常归并。
- 不出现同一个 `opencode-http-ses_*` ID 的重复 UI 项。
- 菜单栏状态变化和通知不会重复触发。

**Step 4: Verify normal OpenCode association paths**

分别验证：

1. 单个无端口 OpenCode 进程仍可通过唯一 CWD 获取标题和状态。
2. `opencode -s ses_xxx` 仍使用 `opencode-http-ses_xxx`。
3. 两个不同 CWD 的 OpenCode 进程仍显示为两个 session。
4. HTTP endpoint 返回的 session 与 SQLite fallback 不会导致重复 ID。

Expected: 正常场景的信息完整度没有因保守处理歧义场景而下降。

**Step 5: Inspect the final diff**

Run:

```bash
git status --short
git diff --check
git diff
```

Expected: 仅包含本计划列出的源文件、测试和计划文档；`git diff --check` 无输出。

**Step 6: Optional final integration commit**

仅当执行过程中还有未包含在前述提交中的测试或小修正时执行：

```bash
git add <only-the-remaining-intended-files>
git commit -m "test: cover duplicate session id crash regression"
```

不要 amend 既有提交，不要提交无关工作区变化。

## Acceptance Criteria

- 原始崩溃 session ID 场景不再触发 `NativeDictionary.swift: Duplicate values for key`。
- Core detector 输出 ID 唯一性有自动化测试保护。
- OpenCode SQLite fallback 不会把一个 session ID 分给多个同 CWD 进程。
- AppModel semantic comparison 和 StatusItem notification indexing 都能安全处理人为构造的重复 ID。
- `swift test` 和 `swift build --product VibeBarApp` 均通过。
- 正常的单进程 CWD fallback、显式 session ID、HTTP detector 和 process fallback 行为不回归。
