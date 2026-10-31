# ParallaxView 实现与托管视图布局修复（2026-10-31）

Gallery 目录中 ParallaxView 原为 **missing**，现新增公开 `FluentParallaxView`，覆盖记为 **partial**。

## WinUI 参照

`src/controls/dev/ParallaxView/`：

- `ParallaxView.cpp` `UpdateExpressionAnimation`（夹紧）：X ≤ start → 0；start < X < end →
  -min(maxRatio, shift / (end - start)) × (X - start)；X ≥ end → -min(maxRatio × (end - start), shift)。未夹紧时不截断。
- `UpdateStart/EndOffsetExpression`（ParallaxView 不在源内、Relative）：start = startOffset - 越界量，
  end = max(0, 内容 + endOffset - 视口) + 越界量；Absolute 直接使用给定偏移。
- `ScrollInputHelper::UpdateOutOfBoundsPanSize`：不可缩放的 ScrollViewer 越界量为视口的 10%。
- `ArrangeOverride`：子元素至少比 ParallaxView 大 shift。

## 实现

- 公开 `FluentParallaxView(horizontal:vertical:background:content:)` 与 `FluentParallaxAxis`、
  `FluentParallaxSourceOffsetKind`。按最常见用法组合：背景在后，内容在前方的 NSScrollView 中，
  背景跟随滚动位置（因此触控板、滚轮、触摸、弹性越界都适用）。
- 数学部分独立为 `FluentParallaxMath`，可单独测试。

## 发现并修复的问题（影响今天新增的多个控件）

`FluentViewHost` 关闭了 `translatesAutoresizingMaskIntoConstraints`。由控件按 frame 摆放的托管视图在
Auto Layout 运行后会被缩回内容的固有尺寸（本控件的背景从 320×400 变成 17×17）。之前的 Pivot、
SwipeControl、SemanticZoom、AnnotatedScrollView、RefreshContainer 测试与截图因示例内容都带了显式尺寸而未暴露。
现已为这些按 frame 布局的托管视图重新启用该属性，并新增 `ManualHostLayoutTests`
（已确认去掉修复后该测试失败）。

## 验证（结果在 `results/`）

- `swift test -Xswiftc -warnings-as-errors`：**222 项通过**，新增 `ParallaxViewTests` 3 项、`ManualHostLayoutTests` 1 项。
- 质量门禁、Gallery 挂载检查、原生验证、完整 Gallery 构建通过。
- [截图审计](results/visual.json)：light/dark × 顶部、中段、末尾；背景位移 4.8 → 80 → 155（内容滚动 0 → 380 → 760），
  断言背景比内容慢且不超过 shift。

## 局限

- WinUI 的 Source 可以是任意 ScrollViewer、ParallaxView 也可在源内；这里固定为“背景 + 内容滚动视图”组合。
- 未支持源的缩放系数（ZoomFactor）。
