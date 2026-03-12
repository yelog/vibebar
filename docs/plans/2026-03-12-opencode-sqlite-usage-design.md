# OpenCode SQLite Usage Design

**Goal:** 修复 OpenCode 在新存储格式下最近 usage 被统计为 0 的问题。

**Background:** 当前 `OpenCodeUsageLoader` 只扫描 `~/.local/share/opencode/storage/message/*.json`。用户机器上的 OpenCode 已改为持续写入 `~/.local/share/opencode/opencode.db`，导致最近几天的 token 数据完全未进入 VibeBar 的 usage 聚合链路。

## Design

### Source Priority

1. 优先读取 `opencode.db`
2. 当数据库不存在或读取失败时，回退到旧的 `storage/message/*.json`

这样可以兼容新旧两种 OpenCode 存储格式，同时避免双读造成的重复统计。

### Database Read Path

- 打开 `root/opencode.db`
- 查询 `message` 表
- 从 `data` JSON 中提取：
  - `modelID`
  - `cost`
  - `tokens.input`
  - `tokens.output`
  - `tokens.cache.read`
  - `tokens.cache.write`
- 使用 `time_created` 作为事件时间
- 跳过 token 全为 0 的 message

### Caching

- 继续复用现有 `UsageFileCacheStore`
- 对数据库生成一个合成 cache key
- cache 签名使用 `opencode.db` 与 `opencode.db-wal` 的组合大小和最新修改时间

这样在 OpenCode 数据未变化时，不需要重复扫描整库。

### Error Handling

- 数据库不存在：正常回退 JSON 目录
- 数据库读取失败：记录 warning，并回退 JSON 目录
- JSON 回退也失败：返回 warning，不阻塞整个 usage 刷新

### Testing

- 增加 SQLite fixture 测试，验证能从 `message` 表读出 usage event
- 保留现有 JSON fixture 测试，验证旧格式仍可工作
- 增加“数据库优先于旧 JSON”的测试，避免重复统计和回归
