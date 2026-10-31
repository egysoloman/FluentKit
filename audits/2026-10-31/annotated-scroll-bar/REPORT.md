# AnnotatedScrollBar 实现（2026-10-31）

Gallery 目录中 AnnotatedScrollBar 原为 **missing**，现新增公开 `FluentAnnotatedScrollView`
（滚动视图 + 注释滚动条），覆盖记为 **partial**。

## WinUI 参照

`src/controls/dev/AnnotatedScrollBar/`：

- 映射：`UpdateScrollOffsetToLabelOffsetFactor` = (轨道高 - 滑块高) / 可滚动高 × (1 - 视口 / (视口 + 可滚动高))。
- 标签：容器位于 offset × factor，TextBlock 边距 0,-5,0,-2、右对齐、Body 样式；
  `CollapseCollidingAndOutOfBoundsLabels` 从下往上处理：越界隐藏，碰撞时保留下方标签，第一项除非与最后可见项冲突否则保留。
- 滑块 30×3、圆角 1.5、AccentFillDefault；悬停幽灵滑块 AccentFillDisabled；最小宽度 44。
- 详细标签 ToolTip：MinHeight 40、MaxWidth 360，触摸时上移 22（`s_toolTipTouchOffset`）。
- `ScrollTo`：点击/拖动跳转，增减按钮按 SmallChange（默认视口 / 8）；先触发可取消的 Scrolling。
- 增减按钮 RepeatButton、8pt 字形，文字色随指针状态变化。

## 实现

- 公开 `FluentAnnotatedScrollView(labels:smallChange:detailLabel:onScrolling:content:)`；内部 NSScrollView
  隐藏系统滚动条，条在尾侧（RTL 在左），双向同步滚动位置。
- 指针移动显示幽灵滑块和详细标签，点击、拖动跳转；增减按钮按住连发（500ms 延迟、50ms 间隔）。
- 内容不足以滚动或祖先被禁用时不响应。

## 验证（结果在 `results/`）

- `swift test -Xswiftc -warnings-as-errors`：**213 项通过**，新增 `AnnotatedScrollBarTests` 6 项。
  测试过程中发现并修正：-5 边距最初加在容器位置上，导致首个标签被判越界。
- 质量门禁、Gallery 挂载检查、原生验证、完整 Gallery 构建通过。
- [截图审计](results/visual.json)：light/dark/RTL × 初始、悬停、点击共 9 张，人工查看。

## 局限

- WinUI 中它是可挂到任意 ScrollView 的 IScrollController；这里固定为组合控件。
- 增减按钮滚动没有动画（WinUI 在动画开启时用 AddScrollVelocity）；标签/详细标签只支持文字模板。
- Gallery 示例行实际高度与 `frame` 设定不一致，详细标签与跳转后的行号有偏差（属示例布局问题，留待细节阶段）。
