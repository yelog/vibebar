# Transcript Terminal Context Design

**Goal:** 修复 `claude` transcript session 不显示终端/Tab、无法跳转的问题，并同步覆盖 `gemini` 的同类缺陷。

**Architecture:** transcript 型 detector 继续负责读取 transcript/session name/status，但在生成 `SessionSnapshot` 时同步基于进程链解析 `terminalContext`。`CompositeSessionDetector` 不再用“只要检测到 session 就关闭 process scan fallback”，而是改成“只有该检测链路已经拿到 terminalContext 才关闭 fallback”，避免 transcript-only 结果吞掉终端关联能力。

**Scope:**
- 修改 `ClaudeTranscriptDetector`
- 修改 `GeminiTranscriptDetector`
- 修改 `CompositeSessionDetector`
- 增加 detector / composite 回归测试

**Approaches Considered:**

### Approach A: 只要求用户启用 Claude plugin

优点：
- 改动最小
- `claude-plugin` 已经会上报终端环境变量

缺点：
- 不能修复 plugin disabled、plugin 未安装、或 Gemini transcript-only 的场景
- 产品行为会依赖用户环境配置，不稳定

### Approach B: transcript detector 直接补 terminalContext，并按 terminalContext 决定是否保留 process fallback

优点：
- 直接修复 `claude` 当前问题
- `gemini` 自动一起修复
- 对未来 transcript / log 型 detector 也更稳健

缺点：
- 需要改 detector 与 composite 两处逻辑

### Approach C: 保持 transcript detector 不动，只在 merge 后对缺失 terminalContext 的 session 再跑一次全局补全

优点：
- 逻辑集中在聚合层

缺点：
- 会把 detector 的职责进一步耦合到 App 聚合链路
- 测试边界更差，也更难复用

**Recommendation:** 选择 Approach B。terminal 关联应尽量在 detector 产出 `SessionSnapshot` 时完成；Composite 只负责决定是否仍需 process fallback 和合并结果。

**Validation:**
- `ClaudeTranscriptDetector` 在 `kitty` 父进程链下能产出 `clientKind = .kitty`
- `GeminiTranscriptDetector` 在 `kitty` 父进程链下能产出 `clientKind = .kitty`
- transcript provider 返回无 `terminalContext` 时，`CompositeSessionDetector` 仍保留 `.processScan` fallback
- `swift test` 通过
