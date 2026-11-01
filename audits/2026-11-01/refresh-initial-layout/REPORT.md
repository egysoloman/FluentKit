# RefreshContainer 首帧约束与动态滚动范围

基线 `1d36b41`，修复提交 `4fc002b`，继续 FOLLOW-UP 第 19 项的初始化告警。没有修改或替换 Fluent IME，也没有合成 NSScrollView.scrollWheel 事件。

## 独立复现

原 `testHorizontalRefreshContentFollowsLiveScrollerStyle` 仍为 XCTest 通过，但报告约束冲突，见 `before-test.log`。独立窗口 `InitialLayoutAudit.swift` 在 AppKit 的已解析 `LAYOUT_CONSTRAINTS_NOT_SATISFIABLE` 断点停止，见 `before-debugger.log`。实际冲突是内容 FluentViewHost 的 autoresizing mask `width == 0` 与横向 ForEach stack 的必需最小间距；发生在 NSWindow 初始布局，不能归为测试错误或靠最终截图证明没有发生。

继续核查内容自己的状态更新：20→2→40→0→20 项，四种拉动方向、LTR/RTL，不调整窗口也不手动强迫父级布局。原代码的滚动范围保持旧值，还会压缩明确指定的单元尺寸；同一新回归在原代码上有 344 处断言失败，见 `before-content-update-tests.log`。初版去掉旧 frame 固定约束后，单元尺寸已恢复，但滚动范围仍有 24 处失败，见 `content-update-tests.log`。这是两条必要修复，不能只关闭首帧警告。

## 修复和源码对照

内容宿主保留 Auto Layout 所有权。滚动轴按自然尺寸求解，并设置低于显式 frame 优先级的视口最小尺寸；交叉轴跟随实际视口，位置固定在 document 起点。移除会把内容锁定在零或过期尺寸的 autoresizing mask。内容宿主自行刷新后，如果尺寸变化，则安排外层重新计算 document 的滚动范围；普通滚动不触发这条更新。

WinUI `src/controls/dev/PullToRefresh/RefreshContainer/RefreshContainer.cpp` 的 OnApplyTemplate / OnPullDirectionChangedImpl 把内容与可视化器分离；`ScrollViewerIRefreshInfoProviderAdapter.cpp` 适配现有 ScrollViewer。此修复是 AppKit 布局所有权问题，未把平台适配代码当作需要逐句移植的上游实现。拉动门槛、刷新状态和 deferral 行为继续由原有源码对照回归守护。

## 验证

14 项相关测试通过，日志中无约束冲突。新增两项回归覆盖上述自主内容更新，以及同实例切换四方向、刷新期间内容增长、deferral 完成、窄→宽缩放、overlay/legacy 滚动条切换。未降低 ForEach 的必需间距，也未静音诊断。

最终完整 489 项测试、原生验证、Debug/Release 构建、Xcode Gallery 构建及 Release 门禁全部通过，完整 XCTest 日志无 AppKit 约束诊断；证据在 `../release-0.2.0/`。最终独立初始布局探针的同一个已解析断点 0 命中，正常退出，见 `after/debugger.log`。`run-initial.sh <SwiftPM products> <新输出目录>` 要求同一个 AppKit 断点解析成功、0 次命中且进程正常退出。

初版测试的 Swift async RunLoop 与 NSEdgeInsets Equatable 编译错误分别保留在 `content-update-tests-first.log`、`targeted-tests-compile.log`；均已修正测试代码。真实鼠标插拔、触摸设备和跨屏仍按原队列验收，本批不将程序化 scrollerStyle 切换视作这些硬件事件。
