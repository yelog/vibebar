# 启动自动更新误弹窗设计

## 背景

用户开启“自动检查更新”和“开机启动”后，重启 macOS 会在应用启动早期弹出“检查更新失败”。关闭弹窗后，稍晚在“关于”页手动点击“检查更新”又能正常显示当前已是最新版本。

## 问题分析

当前实现有两个叠加问题：

1. `VibeBarApp` 启动后会额外在 5 秒后主动调用一次 `checkForUpdatesInBackground()`。
2. `UpdateChecker.updater(_:didAbortWithError:)` 对更新失败统一弹窗，没有区分后台自动检查和用户手动检查。

这导致开机早期的短暂网络、DNS、代理或系统服务未就绪错误，被直接升级成用户可见弹窗。

## 目标

- 后台自动检查失败时静默处理，只保留日志。
- 只有用户手动点击“检查更新”失败时才弹窗。
- 避免应用自己额外触发启动后 5 秒的后台检查，改为依赖 Sparkle 自身调度。

## 方案

### 1. 记录本次检查来源

在 `UpdateChecker` 中增加一个简单的检查来源状态：

- `userInitiated`
- `automaticBackground`

用户点击“检查更新”时标记为手动；后台检查或 Sparkle 自身调度的检查视为后台。

### 2. 调整失败弹窗策略

在 `updater(_:didAbortWithError:)` 中：

- 对 `SUNoUpdateError` 和用户取消继续忽略。
- 如果本次检查来源是后台，则仅写日志，不弹窗。
- 如果本次检查来源是手动，则显示现有失败弹窗。

### 3. 移除额外的启动后台检查

删除 `startAutoCheckIfNeeded()` 中的 5 秒延迟检查和自建定时器逻辑，不再由应用手动驱动后台检查；保留 Sparkle 的 `automaticallyChecksForUpdates` 与 `updateCheckInterval` 配置，由 Sparkle 自行调度。

## 影响范围

- `Sources/VibeBarApp/UpdateChecker.swift`
- `Sources/VibeBarApp/AppDelegate.swift`

## 验证方式

1. 构建 `VibeBarApp`，确认无编译错误。
2. 手动点击“检查更新”并制造失败场景时，确认仍会弹窗。
3. 开机启动或后台自动检查失败时，确认不再弹窗。
