# Notch Footer Actions Design

**Date:** 2026-03-30

**Status:** Confirmed

## Summary

本次设计重做 VibeBar 刘海展开面板底部操作区，解决“退出”按钮视觉体量明显大于“刷新 / 设置”，导致整行失衡的问题。

确认后的方向：

1. 底部三枚操作统一为同级小尺寸按钮，不再把“退出”作为右侧大按钮强调。
2. 保留当前信息架构，即左侧放“刷新 / 设置”，右侧放“退出”，只调整视觉层级和控件实现。
3. 收敛现有 SwiftUI 与 AppKit 混搭按钮，统一为同一套 SwiftUI 样式，确保尺寸、圆角、字重和内边距一致。

## Goals

- 修复刘海展开面板底部按钮视觉不协调的问题。
- 让“退出”按钮与“刷新 / 设置”保持同级关系，弱化过强的危险操作暗示。
- 统一底部操作按钮的实现方式，降低后续样式维护成本。
- 保持当前底部操作区的结构和可发现性，不影响已有使用习惯。

## Non-Goals

- 不重做刘海面板整体布局、尺寸或动画。
- 不修改上方 session 列表和 usage 卡片的排版。
- 不把“退出”改成图标按钮或隐藏到二级菜单。
- 不引入新的确认弹窗或行为变更。

## Current State

- 刘海展开面板由 [NotchContentView.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/NotchContentView.swift) 渲染底部操作区。
- 当前“刷新”和“设置”使用 SwiftUI 的 `.bordered` 小按钮。
- 当前“退出”使用单独的 [NotchQuitButton.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/NotchQuitButton.swift) 包装 `NSButton`。
- 由于三枚按钮不属于同一控件体系，“退出”在默认内边距、字重、图标布局和整体宽度上都明显更重。

## Root Cause

问题不在文案本身，而在控件实现分叉：

1. 左侧是系统小号 SwiftUI bordered button。
2. 右侧是 AppKit `NSButton`，默认 bezel 和内容留白更大。
3. 两者在深色面板里的边框、基线和交互反馈也不一致。
4. 最终导致“退出”即使只放在右侧，也会被感知成主按钮。

## Chosen Approach

采用“同级小胶囊按钮 + 单一 SwiftUI 样式”的方案。

### Layout

- 继续保留 `刷新 / 设置 / 退出` 三个入口。
- 底部布局仍为左侧两个操作、右侧一个退出，中间用 `Spacer` 拉开。
- 按钮间距略微收紧，保持底部一行更像轻量工具栏，而不是主次按钮组合。

### Visual Style

- 三枚按钮统一为紧凑小尺寸，目标高度约 `26-28pt`。
- 统一圆角、横向 padding、图标尺寸和文字字重。
- 常态使用低对比度浅色描边和浅填充，保持克制。
- 按下时只做轻微提亮，不做红色强调，不把“退出”渲染成危险主操作。

### Implementation

- 在 [NotchContentView.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/NotchContentView.swift) 内新增统一的底部操作按钮构建方法和自定义 `ButtonStyle`。
- `刷新`、`设置`、`退出` 全部改用同一套 SwiftUI `Button` 渲染。
- 移除不再需要的 [NotchQuitButton.swift](/Users/yelog/workspace/swift/VibeBar/Sources/VibeBarApp/NotchQuitButton.swift)，避免后续继续分叉。

## Alternatives Considered

### 1. 保留现有布局，只单独缩小 AppKit 退出按钮

- 优点：改动最小。
- 缺点：实现仍然分叉，后续继续调样式时还会出现不一致。

### 2. 把退出改成图标按钮

- 优点：最节省空间。
- 缺点：可发现性下降，不适合当前已经建立的文字操作习惯。

### 3. 给底部整行再包一层工具栏背景

- 优点：整体感更强。
- 缺点：会让底部存在感过高，和当前刘海信息面板的克制风格不完全一致。

## Validation

修复后需要满足：

1. “刷新 / 设置 / 退出”三枚按钮高度、圆角、字重和图标节奏一致。
2. “退出”不再明显比其它按钮更宽更重。
3. 底部操作区在 440pt 面板宽度内保持一行布局，不出现挤压或跳行。
4. 三枚按钮在刘海展开面板里都能正常点击触发原有行为。
5. 不引入 NSPanel 下按钮失效、焦点异常或 hover/press 样式不统一的问题。

## Risks

- 如果 SwiftUI 自定义按钮样式在 `NSPanel` 中命中区域过小，可能影响点击体验，需要人工确认。
- 中文和英文文案长度不同，若 padding 过大，某些语言下可能让底部布局偏紧。
- 删除 AppKit 包装按钮后，需要确认“退出”在刘海面板里仍可稳定响应。
