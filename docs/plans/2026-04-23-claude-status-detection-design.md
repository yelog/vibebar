## 背景

当前 Claude Code 的会话状态主要来自 transcript 检测链路。当 Claude 长时间空闲停留在终端中时，VibeBar 仍可能在 `idle`、`completed`、`running` 之间来回跳变。

用户观察到两类现象：

1. 长时间没有新输出时，只是把焦点切回 Claude Code，VibeBar 就会把会话识别为 `running`。
2. 状态切到 `running` 后，时长没有从当前时刻重新开始，而是沿用较早的时间锚点。

## 现状分析

Claude transcript 状态推断位于 `Sources/VibeBarCore/ClaudeTranscriptDetector.swift`。

当前 `running` 判定包含两条启发式：

1. `cpuUsage >= 0.5`
2. transcript 最近 2.5 秒内有新活动

第一条是主要误判来源。Claude 进程在窗口切焦点、终端重绘、状态栏刷新或其它短暂前台活动时，`ps` 采样到的 CPU 可能瞬时超过阈值，即使 Claude 实际没有继续处理任务，也会被推断成 `running`。

同时，当前 `running` 的 `statusSince` 取的是 transcript 最近活动时间，而不是这次 CPU 抖动发生的时间。因此一旦会话被 CPU 启发式错误标成 `running`，UI 会显示“运行中”，但时长不会从当前时刻刷新。

UI 侧还会把 `running -> idle` 过渡短暂显示成 `completed`。因此底层的 `running <-> idle` 抖动会被放大为“运行中 / 完成 / 运行中”来回切换。

## 方案对比

### 方案 A：插件优先，transcript 只补充元数据

做法：

1. Claude plugin 作为状态真源，负责 `status`、`statusSince`、`idleSince`。
2. transcript 只回填 `title`、`lastUserMessage`、`runningSummary`、`terminalContext` 等辅助信息。
3. 当同一 Claude 会话同时存在 plugin 与 transcript 数据时，禁止 transcript 覆盖 plugin 状态字段。

优点：

1. 状态来源最接近真实运行时事件。
2. 不再受 CPU 抖动、窗口切换影响。
3. 与 OpenCode/Codex 当前“实时事件优先”的方向一致。

缺点：

1. 依赖用户安装 Claude plugin。
2. 未安装 plugin 的场景仍需要 transcript 兜底。

### 方案 B：仅修 transcript 推断

做法：

1. 去掉 CPU 直接判定 `running` 的逻辑。
2. 仅在 transcript 最近有新消息或明确 retry/system 活动时判定为 `running`。
3. 其余场景落到 `awaitingInput` 或 `idle`。

优点：

1. 不依赖 plugin，单点修复即可缓解大部分误判。
2. 改动面小。

缺点：

1. 仍然是启发式，不如 plugin 可靠。
2. 只能改善无 plugin 场景，不能从架构上明确状态主次。

### 方案 C：只做 UI 消抖

做法：

1. 给 Claude 的 `running/idle` 切换加 debounce。
2. 或者在 Claude transcript 来源上隐藏 `completed` 过渡显示。

优点：

1. UI 观感可以暂时稳定。

缺点：

1. 根因仍然存在。
2. 状态与时长仍可能错误，只是更不明显。
3. 容易掩盖真正的检测缺陷。

## 结论

采用“方案 A + 方案 B”的组合：

1. Claude plugin 优先作为状态真源。
2. Claude transcript 移除 CPU 触发 `running` 的逻辑。
3. transcript 保留标题、摘要、上下文补充能力，但不再在有 plugin 的情况下改写状态。

这样既能修复当前误判，也能保证未安装 plugin 的场景有更稳的降级行为。

## 设计细节

### 1. Claude transcript 状态收紧

修改 `ClaudeTranscriptDetector.parseTranscript`：

1. 删除 `cpuUsage >= 0.5` 触发 `running` 的分支。
2. `running` 仅在 transcript 最近出现新活动时成立。
3. 如果最后一个有效状态来自用户输入，则优先落到 `awaitingInput`。
4. 其余情况落到 `idle`。

这会让“切焦点导致 CPU 抖动”的场景不再改变状态。

### 2. Claude plugin 状态优先级收紧

修改 `MonitorViewModel.mergeDetectedDetails`：

1. 当 `merged` 为 Claude plugin 会话、`detectedSession` 为 Claude transcript 会话时，禁止 transcript 覆盖：
   `status`、`statusSince`、`idleSince`、`lastOutputAt`、`lastInputAt`。
2. 仍允许 transcript 回填标题、用户消息、retry 摘要、终端上下文。

这样有 plugin 时，UI 状态只跟随实时事件，不再被 transcript 启发式反向改写。

### 3. 时长显示保持一致

`DurationBadgeFormatter` 与 `SessionSnapshot.currentStatusSince` 不需要单独改动。

根因是错误状态和错误时间锚点被输入到 UI。只要上游不再把空闲会话误标为 `running`，时长显示就会自然恢复正常。

## 验证方案

补充测试：

1. Claude transcript 在没有新 transcript 活动、只有 CPU 抖动时，不应返回 `running`。
2. Claude plugin 会话在合并 transcript 数据后，状态字段保持 plugin 原值。
3. Claude transcript 仍可继续回填 `runningSummary`、`lastUserMessage`、`title`。

手动验证：

1. 启动 VibeBar 与 Claude Code。
2. 让 Claude 会话长时间空闲。
3. 多次在其它窗口与 Claude 窗口之间切换焦点。
4. 确认 VibeBar 不会因为切焦点把 Claude 变成 `running`。
5. 若安装 plugin，再确认状态只由 plugin 事件驱动。

## 提交说明

按当前会话要求先实现代码与测试，不自动创建 git commit。
