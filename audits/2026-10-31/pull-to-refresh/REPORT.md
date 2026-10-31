# PullToRefresh（RefreshContainer）实现（2026-10-31）

Gallery 目录中 PullToRefresh 原为 **missing**，现新增公开 `FluentRefreshContainer`，覆盖记为 **partial**。

## WinUI 参照

`src/controls/dev/PullToRefresh/`：

- `RefreshVisualizer.cpp`：状态 Idle/Peeking/Interacting/Pending/Refreshing 及其转换
  （`RefreshInfoProvider_InteractionRatioChanged`、`..._InteractingForRefreshChanged`：Pending 时松手刷新，
  其他状态松手回到 Idle，刷新中不被打断）；指示器 30（`DEFAULT_INDICATOR_SIZE`）、最低不透明度 0.4；
  旋转 = 起始角 + 2π × clamp(比例, 0, 执行比例) / 执行比例；Pending 缩放 1→1.5→1（300ms）；
  刷新中每 500ms 一圈线性旋转；左右方向起始角 ∓π/2；视差 0.5。
- `RefreshContainer.cpp` / 默认动画：拉动尺寸 100、执行比例 0.8；刷新时内容停在 100 × 0.8。
- 主题：前景 Light 黑、Dark 白、高对比度 HighlightText；背景透明。

## 实现

- 公开 `FluentRefreshContainer(pullDirection:isRefreshing:onRefreshRequested:content:)`、
  `FluentRefreshDeferral`、`FluentRefreshPullDirection`、`FluentRefreshVisualizerState`。
- 拉动来自 NSScrollView 自身的弹性越界：触控板与 macOS 27 触摸滚动都适用；
  `willStartLiveScroll`/`didEndLiveScroll` 对应“正在为刷新交互”。四个拉动方向。
- `isRefreshing` 双向：设为 true 即 `RequestRefresh`；延迟对象完成后回到 false。多次完成无副作用。
- 新增本地化字符串 Refresh / Refreshing。

## 验证（结果在 `results/`）

- `swift test -Xswiftc -warnings-as-errors`：**218 项通过**，新增 `RefreshContainerTests` 5 项。
- 质量门禁、Gallery 挂载检查、原生验证、完整 Gallery 构建通过。
- [截图审计](results/visual.json)：light/dark × 空闲、刷新中（内容停在 80）、完成共 6 张，人工查看。

## 发现

- 直接向 NSScrollView 发送带 phase 的合成滚动事件会进入 AppKit 的弹性跟踪循环并等待真实输入，
  审计程序因此挂起；已移除该步骤，拉动状态机由单元测试覆盖。
- `FluentVStack` 只有一个子视图时无法通过类型检查（同 SemanticZoom 报告），示例已绕开。

## 局限

- 真实的触控板/触摸拉动未自动化验证；未在触摸屏上实测。
- 刷新结束回弹为 0.2s 动画，未对照 WinUI 的 InteractionTracker 惯性。
