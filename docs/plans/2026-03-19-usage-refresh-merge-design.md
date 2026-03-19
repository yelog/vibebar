# Usage Refresh Merge Design

**Goal:** 将 Usage 设置中的“自动刷新”和“完整校验”合并为一个统一刷新入口，同时保留“清缓存重建”作为异常处理操作。

**Decision:** 保留当前 loader 的安全版 full refresh 语义，不再向用户暴露第二套刷新入口或独立的完整校验频率。后台定时刷新和手动刷新都统一走同一条刷新路径；“清缓存重建”继续执行删除本地 snapshot/file cache 后重建的重型流程。

**Why:** 当前实现中，自动刷新与完整校验在 Claude/Codex/Gemini 上都已演进为“枚举当前文件集合 + 复用未变化结果 + 重解析变更文件”，耗时已经接近。继续保留两个用户可见的刷新概念只会增加理解成本，而不会带来明显性能收益。

**Scope:**
- 保留 `usageRefreshCadence` 作为唯一刷新频率设置。
- 设置页只保留一个“刷新”按钮和一组“上次刷新/下次刷新/耗时”信息。
- 保留“清缓存重建”按钮与说明。
- 停止在 `UsageMonitorViewModel` 中使用 `usageFullRefreshInterval` 参与调度，但暂不强行删除该设置字段，避免扩大改动范围。
