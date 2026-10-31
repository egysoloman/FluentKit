# ListView / GridView 打磨（2026-10-31）

对照 WinUI 源码：`themes/generic.xaml` 的 `ListViewHeaderItem` 模板、`ListViewBase.ScrollIntoView`、
`ItemsStackPanel.AreStickyGroupHeadersEnabled`。

## 变更

| 项 | WinUI | FluentKit 之前 | 现在 |
| --- | --- | --- | --- |
| 分组头高度 | MinHeight 44 + Margin 4 = 48 | 34 | `FluentCollectionLayout.defaultHeaderHeight = 48` |
| 分组头模板 | Padding 12,8,12,0；内容下 8pt 一条 1pt `SystemControlForegroundBaseLowBrush` 分隔线 | 纯文本 | 同 WinUI；高对比度下分隔线用 textPrimary |
| 粘性分组头 | 默认开启（AreStickyGroupHeadersEnabled） | 无 | 默认开启，`.areStickyGroupHeadersEnabled(false)` 关闭 |
| ScrollIntoView | Default（最小滚动）/ Leading | 无 | `.scrollIntoView(_:alignment:)`，FluentCollection / ListView / GridView 均可用 |

ScrollIntoView 细节：
- 请求以 `FluentBinding<ItemID?>` 传入，执行后置回 nil（一次性命令语义，与 WinUI 方法调用对应）。
- 项目尚未在快照中、或视口尚未布局时请求保留，下一次更新再执行。
- Leading 对齐与最小滚动都会扣除粘性分组头的高度，避免目标项被固定的分组头遮住
  （AppKit 原生 `scrollToItems(.top)` 不考虑粘性头，所以改为自己计算 clip 偏移）。

## 验证
- `CollectionPolishTests`（4 项）：默认粘性 + 48pt、模板几何（12/8 内边距、分隔线位置）、Leading 滚动后清空请求、
  Default 最小滚动 + 未知项等待。
- 全量 249 测试通过；FluentKitValidation PASS（原 34pt 断言改为 48pt 默认值）；质量门通过；Gallery 构建成功。

## 未做
- ListView Header/Footer（随内容滚动的页眉页脚）。
- ScrollIntoView 的动画滚动（WinUI 默认无动画，暂不需要）。
