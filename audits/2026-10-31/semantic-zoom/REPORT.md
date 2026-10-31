# SemanticZoom 实现（2026-10-31）

Gallery 目录中 SemanticZoom 原为 **missing**，现新增公开 `FluentSemanticZoom`，覆盖记为 **partial**。
同时在共享输入基础层加入捏合驱动 `FluentMagnifyGestureDriver`（触控板 magnify 事件 + macOS 27
直接触摸的 `NSMagnificationGestureRecognizer`）。

## WinUI 参照

- `dxaml/xcp/dxaml/lib/SemanticZoom_Partial.cpp`：`_zoomMin = 0.5`、`_zoomMax = 1.0`；
  `_lower/_upperThresholdDelta = 0.05`；`CanChangeViews` 阻止所有切换；
  `OnKeyDown` 经 `ScrollViewer::GetKeyboardMessageZoomAction`（Ctrl + Subtract/Add/OemMinus/OemPlus）；
  Ctrl+滚轮仅在 ScrollViewer.ZoomMode 启用时生效（默认关闭）；`OnPointerMoved` 只对非触摸指针显示
  缩小按钮；切换视图时隐藏按钮。
- `dxaml/xcp/dxaml/themes/generic.xaml`：缩小按钮 12×12，右下边距 19，默认 `IsZoomOutButtonEnabled=False`；
  ZoomOutButtonVisible → Hidden 的过渡在 3 秒后开始；两个视图用 FadeIn/FadeOut 切换。

## 实现

- 公开 `FluentSemanticZoom(isZoomedInViewActive:canChangeViews:isZoomOutButtonEnabled:allowsWheelZoom:onViewChangeCompleted:zoomedInView:zoomedOutView:)`；
  缩小视图通过 `FluentSemanticZoomProxy.zoomIn(to:)` 回传目标分组，`onViewChangeCompleted` 交给应用滚动到位
  （WinUI 中由 ISemanticZoomInformation 完成，这里改为显式回调）。
- 捏合：当前视图在 0.5…1（缩小视图镜像为 1…2）内跟随缩放，超过 5% 切换，否则回弹。
- 键盘：Ctrl 或 ⌘ 加减号/加号（含小键盘）；可选 Ctrl+滚轮。
- 切换动画：淡出并缩放离开视图、淡入另一视图，0.25s 减速；Reduce Motion 下直接切换。
- 绑定双向同步；替换绑定后丢弃旧绑定已排队的通知；焦点在内部时转移到新视图。

## 验证（结果在 `results/`）

- `swift test -Xswiftc -warnings-as-errors`：**207 项通过**，新增 `SemanticZoomTests` 7 项。
- 质量门禁、Gallery 挂载检查、原生验证、完整 Gallery 构建通过。
- [截图审计](results/visual.json)：light/dark/RTL × 放大视图、显示缩小按钮、缩小视图共 9 张；
  断言鼠标移动显示按钮、Ctrl+减号缩小并隐藏按钮、选择分组后放大并带回目标。人工查看了按钮位置与 RTL 缩小视图。

## 发现的 API 问题（留待细节阶段）

- `FluentVStack`/`FluentHStack` 只有一个 `FluentForEach` 子项时无法通过类型检查，需要包一层 `FluentAnyView`。
- `FluentForEach` 放在 `FluentHStack` 内仍按纵向排列。

## 局限

- 捏合截图未覆盖（AppKit 无公开方式合成 magnify 事件），由单元测试验证；未在触摸屏上实测。
- 切换动画是近似：WinUI 在两视图间做连续缩放并按项目位置对齐（`StartViewChangeFrom/To`），这里只做淡入淡出与缩放。
