# Notch Footer Actions Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 重做刘海展开面板底部操作区，让“退出”按钮与“刷新 / 设置”统一为同级小尺寸按钮，消除底部视觉失衡。

**Architecture:** 保持底部操作区原有信息架构不变，只在 `NotchContentView` 内收敛按钮实现和样式。通过一个统一的 SwiftUI 按钮构建方法和轻量 `ButtonStyle` 覆盖三枚按钮，顺手删除不再需要的 AppKit 专用 `NotchQuitButton` 包装。

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, Swift Package Manager

---

### Task 1: 写入设计定稿并同步实现计划

**Files:**
- Create: `docs/plans/2026-03-30-notch-footer-actions-design.md`
- Create: `docs/plans/2026-03-30-notch-footer-actions.md`

**Step 1: 补齐设计背景与决策**

记录当前底部按钮不协调的原因、用户确认的方向，以及最终采用的同级小按钮方案。

**Step 2: 写清实现边界**

明确本次只调整底部操作区，不修改面板整体布局、动画或行为。

**Step 3: 写清验证要求**

记录统一高度、统一视觉重量和点击行为保持不变这三类验收点。

### Task 2: 收敛底部按钮为统一 SwiftUI 样式

**Files:**
- Modify: `Sources/VibeBarApp/NotchContentView.swift`

**Step 1: 抽出统一按钮构建方法**

在 `NotchContentView` 内新增一个底部按钮 helper，统一 `Label`、字体、padding、固定高度和点击区域。

**Step 2: 新增轻量按钮样式**

增加一个仅用于刘海底部操作区的 `ButtonStyle`，提供统一的浅描边、浅填充和按下反馈。

**Step 3: 替换底部三枚按钮**

将“刷新 / 设置 / 退出”都切换到同一套 SwiftUI `Button` 和自定义样式，保留原有动作回调和左右布局结构。

**Step 4: 保持 NSPanel 可点击**

给新按钮保留清晰的 `contentShape`、固定高度和 `focusable(false)`，避免在刘海 `NSPanel` 中出现命中异常。

### Task 3: 移除旧的退出按钮包装实现

**Files:**
- Delete: `Sources/VibeBarApp/NotchQuitButton.swift`

**Step 1: 确认无引用后删除旧文件**

在 `NotchContentView` 完成替换后，删除不再被使用的 AppKit 包装按钮文件，避免后续继续被误用。

### Task 4: 构建验证

**Files:**
- None

**Step 1: 运行目标构建**

Run: `swift build --target VibeBarApp`
Expected: BUILD SUCCEEDED

**Step 2: 记录人工验证点**

最终说明中明确需要人工确认：
- 刘海展开面板底部三枚按钮视觉已统一
- “退出”不再显著大于其它按钮
- 三枚按钮点击行为保持正常
