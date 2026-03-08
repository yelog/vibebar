# VibeBar Power Optimization Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 显著降低 VibeBar 在后台运行时的 CPU 唤醒频率、进程扫描次数和无效 UI 重建，解决菜单栏主进程高耗电问题。

**Architecture:** 先砍掉最高频且最重的同步轮询路径，再把检测链路改成共享快照和分层调度，最后收紧 UI 更新与验证基线。原则是优先减少 `/bin/ps`、`lsof`、本地 HTTP 和主线程同步工作，避免一次刷新重复做同一类系统调用。

**Tech Stack:** Swift 6.2、AppKit、Combine、Foundation、Process、Timer、VibeBarCore detectors

---

### Task 1: 建立耗电基线与回归标准

**Files:**
- Modify: `/Users/yelog/workspace/swift/VibeBar/docs/plans/2026-03-06-power-optimization.md`

**Step 1: 记录现状**

Run: `ps -p $(pgrep -f '/Applications/VibeBar.app/Contents/MacOS/VibeBarApp' | head -n 1) -o pid=,%cpu=,time=,command=`
Expected: 能看到 `VibeBarApp` 当前 CPU 与累计时间。

**Step 2: 记录热点调用栈**

Run: `sample $(pgrep -f '/Applications/VibeBar.app/Contents/MacOS/VibeBarApp' | head -n 1) 5 -mayDie > /tmp/vibebar-before.sample.txt`
Expected: 样本里能看到 `MonitorViewModel.refreshNow()`、`ProcessScanner.runPS()`、`DetectorSupport.bulkGetCwds()` 等热点。

**Step 3: 记录验收门槛**

验收目标：
- 活跃会话下 `VibeBarApp` 稳态 CPU 明显低于当前基线
- `sample` 热点不再由 `runPS()` 和 `bulkGetCwds()` 主导
- 菜单关闭时不再每秒重建整套 `NSMenu`

### Task 2: 放宽刷新节奏并移出主线程热路径

**Files:**
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/AppModel.swift`

**Step 1: 调整刷新策略**

把活跃态刷新从 `1s` 改成更保守的分层策略：
- `running/awaitingInput`: `2s` 或 `3s`
- `idle`: `10s`
- 无会话: `15s` 或更高

**Step 2: 避免 Timer 直接在主线程做全量检测**

将 `refreshNow()` 拆成：
- 后台执行检测与合并
- 主线程仅发布 `sessions` 和 `summary`

**Step 3: 增加“上一轮刷新未完成则跳过本轮”保护**

要求：
- 新增 `isRefreshing` 或等价状态
- 若上一次检测未结束，下一次 timer tick 直接丢弃

**Step 4: 手工验证**

Run: `swift build`
Expected: 编译通过。

### Task 3: 让低优先级 processScan 真正成为 fallback

**Files:**
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/CompositeSessionDetector.swift`
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/CLISettingsConfiguration.swift`

**Step 1: 收紧默认配置**

调整默认检测方法：
- `claudeCode`: 默认优先 `plugin`，必要时才手动启用 `processScan`
- `opencode`: 默认优先 `plugin + httpAPI`，不默认开 `processScan`
- `gemini`: 若 `transcriptFile` 已可用，避免默认叠加 `processScan`

**Step 2: 在组合检测器中加入短路逻辑**

要求：
- 若某工具已从高优先级来源拿到有效会话，则本轮跳过该工具的 `processScan`
- `processScan` 只扫描仍无高优结果的工具集合

**Step 3: 手工验证**

场景：
- 开启 `opencode`
- `plugin/httpAPI` 有结果时确认不会再为 `opencode` 跑 `processScan`

### Task 4: 合并重复进程扫描，单轮刷新只取一次进程快照

**Files:**
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/DetectorSupport.swift`
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/ProcessScanner.swift`
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/OpenCodeHTTPDetector.swift`
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/GeminiTranscriptDetector.swift`
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/CompositeSessionDetector.swift`

**Step 1: 引入单轮刷新上下文**

新增轻量上下文对象，至少包含：
- 进程列表快照
- 可选 cwd 缓存
- 可选端口缓存

**Step 2: 让各 detector 复用同一份进程列表**

要求：
- `OpenCodeHTTPDetector` 不再自己调用 `listProcesses()`
- `GeminiTranscriptDetector` 不再自己调用 `listProcesses()`
- `ProcessScanner` 优先消费共享快照

**Step 3: 手工验证**

Run: `sample $(pgrep -f '/Applications/VibeBar.app/Contents/MacOS/VibeBarApp' | head -n 1) 5 -mayDie > /tmp/vibebar-after-process-cache.sample.txt`
Expected: 样本中整轮刷新不再出现多处独立 `listProcesses()` 热点。

### Task 5: 缓存 cwd 与 OpenCode 端口，减少 `lsof`

**Files:**
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/DetectorSupport.swift`
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/OpenCodeHTTPDetector.swift`
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/ProcessScanner.swift`
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/GeminiTranscriptDetector.swift`

**Step 1: 给 cwd 结果加短 TTL 缓存**

要求：
- key 至少包含 `pid`
- 进程仍存活时可复用上次 cwd
- 避免每轮都为同一批 PID 调 `lsof`

**Step 2: 给 OpenCode 监听端口加短 TTL 缓存**

要求：
- `pid -> port`
- 端口探测失败时允许短时间负缓存

**Step 3: 手工验证**

Expected:
- 稳态运行时 `lsof` 次数显著下降
- `sample` 中 `findListeningPort()` 与 `bulkGetCwds()` 热点明显减弱

### Task 6: 收紧 OpenCode HTTP 轮询次数

**Files:**
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/OpenCodeHTTPDetector.swift`

**Step 1: 避免对每个 session 重复请求状态接口**

要求：
- `/session/status` 每个端口只请求一次
- 再从返回结果中映射所有 session 状态

**Step 2: 改为后台异步等待，不在主线程用 semaphore 阻塞**

要求：
- detector 结果允许异步收集
- 不要把 `DispatchSemaphore.wait()` 留在 UI 主线程链路上

**Step 3: 手工验证**

场景：
- 运行一个 `opencode`
- 确认每轮最多 1 次 session 列表请求 + 1 次状态请求

### Task 7: 收紧 Gemini transcript 探测

**Files:**
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/GeminiTranscriptDetector.swift`
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/DetectorSupport.swift`

**Step 1: 无 Gemini 进程时立即短路**

要求：
- 使用共享进程快照先判断
- 没有 Gemini 进程就不要扫 `~/.gemini/tmp`

**Step 2: 给 transcript 目录扫描加缓存**

要求：
- 缓存 `CWD -> transcript`
- 仅在 TTL 到期或 Gemini 进程集变化时重扫目录

**Step 3: 去掉每个 pid 单独 `ps -p pid -o pcpu=` 的设计**

要求：
- 直接复用共享进程快照里的 CPU 数据

**Step 4: 手工验证**

Expected:
- 未运行 Gemini 时，`GeminiTranscriptDetector` 几乎不产生额外 I/O

### Task 8: 只在菜单打开时重建菜单，后台仅更新状态图标

**Files:**
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/StatusItemController.swift`

**Step 1: 拆分 UI 更新责任**

要求：
- 常态刷新只更新 `statusItem.button.image` 和 tooltip
- `rebuildMenuItems()` 仅在 `menuWillOpen`、菜单已打开、或确有必要时执行

**Step 2: 去掉一次刷新里的重复 UI 发布**

要求：
- 尽量把 `sessions` 与 `summary` 合并为一次发布
- 或在 UI 层做去抖/合并，避免同一轮刷新重复 `updateUI()`

**Step 3: 手工验证**

场景：
- 菜单关闭状态下观察 30 秒
- 确认不会每秒重复构造 `NSMenuItem` / `SessionMenuItemView`

### Task 9: 清理重复 session 文件读取

**Files:**
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarCore/SessionFileStore.swift`
- Modify: `/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/AppModel.swift`

**Step 1: 合并 `cleanupStaleSessions()` 与 `loadAll()`**

要求：
- 一轮刷新只读一次 session 目录
- 清理逻辑基于已读结果处理

**Step 2: 手工验证**

Expected:
- Session 文件 I/O 降低
- 行为与现状一致，不误删活动会话

### Task 10: 回归验证与验收

**Files:**
- Modify: `/Users/yelog/workspace/swift/VibeBar/docs/plans/2026-03-06-power-optimization.md`

**Step 1: 编译验证**

Run: `swift build`
Expected: PASS

**Step 2: 运行验证**

Run: `swift run VibeBarApp`
Expected: 功能正常，菜单栏状态更新正常。

**Step 3: 再次采样**

Run: `sample $(pgrep -f 'VibeBarApp' | head -n 1) 5 -mayDie > /tmp/vibebar-final.sample.txt`
Expected:
- 主热点不再是 `ProcessScanner.runPS()`
- `bulkGetCwds()`、`findListeningPort()`、`rebuildMenuItems()` 占比明显下降

**Step 4: 记录结果**

在本计划文件末尾追加：
- 优化前后 CPU 对比
- 优化前后 sample 热点对比
- 是否还有残留高耗电路径
