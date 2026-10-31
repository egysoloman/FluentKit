# 声明式布局 API 修复（2026-10-31）

今天实现新控件时反复遇到的布局 API 问题，逐一复现后修复。

## 1. `.frame(width:height:)` 不被遵守

- 现象：AnnotatedScrollBar 示例中 `FluentText(...).padding(6).frame(height: 32)` 的行实际只有 29pt，
  详细标签显示 “Row 226” 而跳转后顶部是第 250 行。
- 复现：`ForEachRowHeightTests`——在计算 fitting size 的上下文（如 `FluentForEach`）中 5 行高度均为 29。
  在固定尺寸窗口中的 VStack 里能得到 32，掩盖了问题。
- 原因：frame 约束优先级为 `.defaultHigh`（750），与文字的内容 hugging（同为 750）相同，平局由求解器任意决定。
- 修复：显式尺寸约束改为 999——高于任何 hugging / compression resistance，但仍低于 required，不会产生冲突。
  WinUI 的 Width/Height 与 SwiftUI 的 frame 都是确定性的。
- 原生验证中“集合单元格拥有 112pt 高度、嵌套 frame 仍是可覆盖的理想值”这一检查原先断言优先级恰好为 750；
  其意图是“高优先级但非 required”，已改为断言该意图（≥ 750 且 < required）。结果：单元格内 96pt 的 frame 现在真正保持 96pt。
- 修复后重跑 AnnotatedScrollBar 审计：详细标签与跳转后的顶行一致（[截图](results/asb-visual/light-clicked.png)）。

## 2. `FluentForEach` 在 `FluentHStack` 中仍纵向排列

- 复现：`LayoutAPIRegressionTests.testForEachFollowsAHorizontalStack`。
- 原因：ForEach 内部固定使用纵向 NSStackView，不看所在容器。
- 修复：加入栈时采用外层栈的方向与对齐；`spacing` 改为可选，省略时继承外层栈的间距（不在栈中时仍为 8），显式值优先。
  调用方源码兼容。
- **行为变化**：直接放在 `FluentVStack` 里、未写 spacing 的 ForEach，间距由 8 变为该 VStack 的间距（默认 12）。

## 3. 单子视图的 `FluentVStack`/`FluentHStack`

已于 `3689adb` 修复（`@_disfavoredOverload` 泛型重载）。

## 示例清理

SemanticZoom 示例中为绕开上述问题写的显式按钮与多余的 `FluentAnyView` 包装已改回自然写法。

## 验证（结果在 `results/`）

- `swift test -Xswiftc -warnings-as-errors`：**245 项通过**，新增 4 项布局回归测试。
- 原生验证、质量门禁、完整 Gallery 构建通过。
