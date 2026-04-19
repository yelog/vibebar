# Notch Auto Expand Hold Delay Design

**Date:** 2026-04-19

**Status:** Confirmed

## Goal

当刘海因为 Session 状态变化而自动展开时，不要立刻收起，而是至少保持 3 秒，让用户有时间看到内容或将鼠标移动过去进行操作。

## Problem

- 当前自动展开完成后，`NotchDisplayController.expandImmediately()` 会立刻调用 `reconcilePointerPresence()`。
- 如果鼠标不在刘海热区，现有 hover 状态机会立即进入 `pendingCollapse`，并在 `200ms` 后收起。
- 这条链路对 hover 展开是合理的，但对“状态变更驱动的自动展开”过快，用户几乎没有可见性和操作窗口。

## Goals

- 仅对“状态变更触发的自动展开”增加最短展示期。
- 最短展示期为 3 秒。
- 3 秒内即使鼠标不在刘海区域，也不自动收起。
- 3 秒后恢复现有 hover 收起逻辑。
- 不影响点击 Session 后直接跳转并收起的行为。

## Non-Goals

- 不修改普通 hover 展开/收起的全局时序。
- 不修改通知点击后的展开行为。
- 不重写 `NotchHoverStateMachine` 的状态模型。

## Chosen Approach

采用“自动展开保留期”方案，只在 `StatusItemController -> NotchDisplayController.expandForStateChange(...)` 这条链路上生效。

具体规则：

1. 当状态变化触发自动展开时，在 `NotchDisplayController` 中记录一个保留截止时间 `autoExpandHoldUntil = now + 3s`。
2. 保留期内如果鼠标不在刘海区域，不进入自动收起流程。
3. 同时安排一个到期回调；到期后重新检查鼠标位置。
4. 如果到期时鼠标仍不在面板内，则走现有收起判定；如果用户已将鼠标移入面板，则完全切回当前 hover 模式。
5. 面板收起、隐藏或用户点击 Session 后，清理保留期上下文和定时器。

## Why This Approach

- 改动集中在 `NotchDisplayController`，不需要改动 `NotchHoverStateMachine` 的公共状态定义。
- 普通 hover 场景仍保持当前 `350ms` 展开、`200ms` 收起体感，不会因为这次需求整体变钝。
- 语义上也更符合产品目标：这是对“自动展开提醒”的保护，而不是全局交互规则变更。

## UX Details

- 自动展开后面板至少可见 3 秒。
- 用户若在这 3 秒内把鼠标移入刘海区域，面板继续保持展开，并由现有 hover 逻辑接管。
- 用户若什么都不做，3 秒后面板再根据当前鼠标位置决定是否收起。
- 用户点击聚焦 Session 时，仍立即跳转到终端，不额外等待保留期结束。

## Implementation Notes

- 在 `NotchDisplayController` 中新增：
  - 自动展开保留时长常量
  - 可选的 `autoExpandHoldUntil`
  - 可选的 `autoExpandHoldWorkItem`
- 在 `reconcilePointerPresence()` 或收起调度前判断保留期是否仍有效。
- 保留期结束后触发一次统一的重新检查，避免复制收起逻辑。
- 若刘海已处于展开状态，仍保持当前策略：新的状态变更不打断用户当前操作。

## Testing & Verification

- 手动验证自动展开后至少保持 3 秒。
- 3 秒内鼠标不移动时不收起，3 秒后才允许自动收起。
- 3 秒内鼠标移入面板后，面板继续保持展开。
- 点击 Session 仍可直接跳转并收起。
- 普通 hover 展开/收起体感不变。
