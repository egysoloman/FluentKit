# 为 13 个已实现控件补 Gallery 示例（2026-10-31）

这 13 个控件此前被标为已实现，但没有直接示例，因此 Gallery 中显示为 partial：
ToggleButton、RepeatButton、StackPanel、Grid、SplitView、NavigationView、TabView、TeachingTip、TitleBar、
CommandBarFlyout、RichEditBox、Clipboard、StoragePickers。

## 结果

- 每个都增加了直接示例，Gallery 注册检查在 light/dark/RTL 下挂载通过，覆盖状态由 partial 变为 **implemented**。
- 目录统计：implemented 36、partial 66、macOS alternative 16、not applicable 3、missing 0。
- [示例截图](results/visual)：13 张浅色渲染，全部人工查看。

## 截图发现并修复

Grid 示例在可用空间较大时，第一列占据了几乎全部多余宽度，行被拉到上下两端。WinUI Grid 默认的 `*` 行列平分空间、
子元素在单元格内拉伸。`FluentGrid` 改为在列间、行间加等宽/等高约束并设置单元格填充；新增 `GridStarSizingTests`。

## 验证（结果在 `results/`）

- `swift test -Xswiftc -warnings-as-errors`：**241 项通过**。
- 原生验证、质量门禁、完整 Gallery 构建通过。

## 说明

“implemented” 只表示控件有直接示例并能在三种外观下挂载；视觉还原、交互状态仍按各控件的验收记录，
Windows 对照与 VoiceOver 仍为 pending。
