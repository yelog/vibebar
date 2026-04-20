# Notch Focused Hover Reveal Design

**Date:** 2026-04-19

**Status:** Confirmed

## Goal

当状态变化触发刘海自动展开并进入“聚焦单个 Session”视图后，一旦用户把鼠标移入该窗口，立即切换为完整窗口内容，方便继续查看全部 Session 和 usage 信息。

## Problem

- 当前状态变化自动展开会通过 `focusedSessionID` 把内容限制为单个 Session。
- 自动展开后的 3 秒保留期内，鼠标移入窗口只会清理 hold 并交给 hover 状态机接管。
- 由于面板物理上已经是 `.expanded`，hover 状态机不会再次触发“展开完整内容”的逻辑。
- 结果是用户把鼠标移入窗口后，面板继续停留在聚焦态，而不是切回完整窗口。

## Goals

- 保持状态变化自动展开时的聚焦单 Session 体验。
- 当鼠标移入该已展开窗口时，立即切换为完整窗口。
- 切换后继续使用现有 hover 规则管理停留与收起。
- 不影响普通 hover 展开，也不影响通知点击展开。

## Non-Goals

- 不修改状态变化自动展开的触发条件。
- 不修改 3 秒最短展示期本身。
- 不新增新的面板类型或独立弹层。

## Chosen Approach

在 `NotchDisplayController` 中增加一条“用户接管聚焦态”的逻辑：当鼠标进入已自动展开的窗口时，如果当前仍存在 `focusedSessionID`，就立即清理它并刷新面板内容与尺寸，切回完整窗口。

具体规则：

1. 状态变化自动展开时仍然设置 `focusedSessionID`，保持当前聚焦态行为不变。
2. `reconcilePointerPresence()` 检测到鼠标进入窗口时，先检查当前是否处于聚焦态。
3. 如果是聚焦态，则立即清理 `focusedSessionID`，并重新测量完整窗口尺寸。
4. 如果面板当前已经处于 `.expanded`，则立即刷新内容并更新面板 frame，显示完整窗口。
5. 切换完成后，继续走现有 `.pointerEnteredHotZone` 的 hover 逻辑。

## Why This Approach

- 问题本质在控制器层：当前少了一步“从聚焦态退回完整态”的状态切换，直接在 `NotchDisplayController` 修复最集中。
- 不需要改 `NotchHoverStateMachine`，因为 hover 状态机已经正确表达了“窗口是否展开”，问题只在展开后的内容模式。
- 保持原有聚焦态和完整态复用同一面板，避免引入第二套 UI 结构。

## UX Details

- 状态变化自动展开时，仍然先显示单个 Session，降低打扰。
- 用户把鼠标移入窗口后，立即看到完整窗口，不需要额外等待或再经过一次 hover 延迟。
- 如果用户始终不把鼠标移入窗口，面板继续按现有保留期和自动收起逻辑工作。
- 点击 Session 的直接跳转行为保持不变。

## Implementation Notes

- 增加一个专门的“退出聚焦态”小 helper，负责：
  - 清理 `focusedSessionID`
  - 清理 auto-expand hold
  - 在已展开状态下重新测量完整内容尺寸
  - 刷新 `NotchPanelViewState` 和面板 frame
- 只在当前是“状态变化导致的聚焦态”时执行，不影响普通完整窗口。
- 如果鼠标进入发生在展开动画尚未结束时，只需要先清理聚焦态；动画完成后的现有 remeasure 路径会自然切到完整尺寸。

## Testing & Verification

- 为聚焦态状态切换增加一个小型单元测试辅助，覆盖“开始聚焦”和“切回完整态”逻辑。
- 手动验证：
  - 状态变化自动展开时仍先显示单个 Session。
  - 鼠标移入窗口后立即切换成完整窗口。
  - 切换后 usage 区域和其他 Session 恢复可见。
  - 3 秒保留期和普通 hover 收起逻辑仍然正常。
