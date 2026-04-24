# OpenCode Stale Session Fallback Design

**日期：** 2026-04-23

**问题**

当 OpenCode 进程没有暴露 HTTP 端口，且启动参数里也没有显式 `session id` 时，`OpenCodeHTTPDetector` 会退回到 SQLite，并通过 `cwd -> 项目最近 session` 做推断。这会把同项目上一条历史会话的 `title`、`time_created`、`time_updated` 复用到一个刚启动的新进程上。

结果是：

- VibeBar 会显示旧的 session name。
- 运行时长会从旧会话开始计算。
- SQLite fallback 的运行态又只看当前进程 CPU，叠加旧时间戳后，容易表现成“新会话一直在运行”。

**目标**

- 新启动但尚未识别出真实 OpenCode `session id` 的进程，不能继承同项目历史会话标题。
- 新进程不能继承历史会话的创建/更新时间。
- 显式 `-s ses_xxx` 的恢复会话保持现有行为。
- 一旦 SQLite 中出现属于当前进程的新会话，仍能自动补上真实标题。

**备选方案**

1. 为 `cwd -> session` 回填增加基于进程启动时间的新鲜度校验。
   - 优点：只改 SQLite fallback 路径，显式恢复会话不受影响。
   - 缺点：需要引入一个小的时间窗口启发式。
2. 无 `session id` 时彻底禁用 `cwd -> session` 回填。
   - 优点：逻辑最简单，绝不会误用旧标题。
   - 缺点：即使 SQLite 很快写入了当前会话，也无法再补上标题。
3. 保留标题推断，只修正时间戳。
   - 优点：改动最小。
   - 缺点：仍会错误展示旧标题，不能解决核心误判。

**决策**

采用方案 1：仅在按 `cwd` 查到的 SQLite session 足够“新鲜”时，才把它视为当前进程的会话。

**设计**

### 1. 用当前进程启动时间作为回填边界

SQLite fallback 已经拿到了 `ps` 输出里的 `elapsedSeconds`。用它推导当前进程启动时间：

- `processStartedAt = now - elapsedSeconds`

后续所有基于 `cwd` 的 SQLite 匹配，都拿这个时间作为边界，而不是无条件取“该项目最近一条 session”。

### 2. 只接受启动后新建的 SQLite session

当进程参数里没有显式 `session id`，且只能按 `cwd` 查 SQLite 时：

- 若 `session.timeCreated >= processStartedAt - grace`，接受该 session。
- 否则视为历史会话，不把它绑定到当前进程。

这里的 `grace` 只作为很小的时间宽限，用来容忍进程启动和 SQLite 落盘之间的抖动；它不应该大到让分钟前/小时前创建的旧会话重新被采纳。

### 3. 对未识别会话的进程返回“无标题”快照

如果 `cwd` 命中的 SQLite session 被判定为历史数据，则为当前进程生成一个未识别快照：

- `sessionId = nil`
- `title = nil`
- `currentTask = nil`
- `runningSummary = nil`
- `timeCreated/timeUpdated` 不再继承历史 session

这样列表仍能看到当前 OpenCode 进程，但不会借用上一条历史会话的展示信息。

### 4. 显式恢复路径保持不变

当进程参数显式带 `-s` / `--session ses_xxx` 时：

- 继续按 `session id` 直接查询 SQLite
- 继续保留该会话已有标题和时间语义

因为这是用户明确恢复既有会话的路径，不属于误判场景。

**测试策略**

- 增加 SQLite fallback 回归测试，覆盖“同项目旧 session 不应污染新进程”。
- 再补一条正向测试，覆盖“进程启动后新创建的 session 仍可被接受”。

**非目标**

- 不修改 OpenCode HTTP API 检测路径。
- 不修改 AppModel 合并优先级。
- 不重新定义 OpenCode 的 running / idle 语义。

**备注**

按当前会话约束，本设计文档只写入工作区，不自动创建 git commit。
