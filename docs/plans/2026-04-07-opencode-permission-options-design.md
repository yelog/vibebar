# OpenCode Permission Options Design

**Date:** 2026-04-07

**Status:** Confirmed

## Goal

让 VibeBar 在 OpenCode 权限请求场景中按源工具原始选项展示与回写，不再把 `allow once / allow always / reject` 压扁成通用的“允许 / 拒绝”。

## Problem

- OpenCode 插件当前只把权限请求上报成抽象 `kind: "permission"`，没有把原始选项传给 App。
- App 对 `permission` 做了通用硬编码，永远渲染“允许 / 拒绝”。
- 插件回写权限时只支持 `allow -> once` 和 `deny -> reject`，缺少 `always`。
- 菜单栏 `NSView` 行容器会拦截点击，可能吞掉行内按钮事件。

## Decision

采用“原始选项直通”方案：

1. OpenCode 插件把原始权限选项写入 `PendingInteraction.options`。
2. App 优先按 interaction 自带 `options` 原样渲染，保留顺序和语义。
3. App 点击后回传被选中的 option id。
4. OpenCode 插件按 option id 精确映射到 `once / always / reject`。
5. 菜单栏行视图在点击子按钮时不再触发整行 `openSession`。

## Scope

本次只修 OpenCode 的 permission interaction：

- OpenCode 权限请求：显示 `Allow once`、`Allow always`、`Reject`
- 其他工具已有 permission 交互：保持兼容
- question 类型：继续沿用现有 options 直通逻辑

## Files

- Modify: `plugins/opencode-vibebar-plugin/index.js`
- Modify: `Sources/VibeBarApp/SessionDisplayFormatter.swift`
- Modify: `Sources/VibeBarApp/StatusItemController.swift`
- Modify: `Tests/VibeBarAppTests/SessionDisplayFormatterTests.swift`

## Verification

- OpenCode 权限请求出现时，VibeBar 显示三个原始选项。
- 点击 `Allow once` 后，请求继续执行。
- 点击 `Allow always` 后，OpenCode 收到 `always`。
- 点击 `Reject` 后，请求被拒绝。
- 菜单栏点击按钮时不会误触发行打开行为。
