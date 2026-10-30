# FlipView 导航交互与禁用状态修复

在上一批选择/过渡修复基础上，继续对照本地 WinUI 源码。新增首批 5 项交互测试在
`57c5d46` 上产生 26 个断言失败（`tests-before.log`）。本轮最后补测鼠标跟踪时，又在中间
版本复现了从键盘切换到指针后焦点框残留的问题（`focus-pointer-before.log`）。

## 源码证据与修正

本地来源目录为 `microsoft-ui-xaml-winui3-release-2.3.1/src/`。

| WinUI 来源 | 本次对应行为 |
| --- | --- |
| `controls/dev/CommonStyles/FlipView_themeresources.xaml` 和 `_perf2026.xaml`：8pt glyph、水平按钮 16×38、Margin=1、IsTabStop=False | 修正此前 20×36 的实现与测试；按钮不是键盘停靠点，窄/零尺寸下仍保持非负且不超出控件的几何 |
| `dxaml/xcp/dxaml/lib/FlipView_Partial.cpp` 构造函数、`ChangeVisualState` | 初始按钮隐藏；首项隐藏 Previous，末项隐藏 Next，空集合隐藏两者 |
| `OnPointerEntered`、`OnPointerMoved`、导航按钮 enter/exit 和 timer handler；头文件定义 3000 ms | 指针活动及键盘焦点显示按钮，停在按钮上时保持显示，离开后重新计时；三秒无活动后隐藏 |
| `OnPointerWheelChanged`；头文件定义 200 ms | 同向连续滚轮事件只翻一次，每条被抑制的事件也更新时间；反向或间隔超过 200 ms 才再次翻页；边界处合格事件及 Ctrl+wheel 交还父容器 |
| `OnGotFocus`、`OnLostFocus`、`OnIsEnabledChanged` | 键盘焦点反馈、禁用时阻断用户翻页并隐藏按钮；模型更新仍然生效 |

源码方法名虽然包含 FadeOut，实际到期调用的是立即折叠，没有对应 opacity 动画；本实现没有
凭名称添加一段淡出。水平 AppKit wheel 按 RTL 镜像，纵向 wheel 保持逻辑上一页/下一页。
按钮从 11pt SF Symbol 配置改到 8pt；这只是字号对齐，SF 字形及当前按钮背景仍不是 WinUI
原始字形和 Acrylic 配方的完全复刻。

原先的 `testFlipViewButtonsKeyboardAndBindingNavigation` 把 20×36 写成了期望值。本次改为
源码明确的 16×38，并增加位置、边距和窄视口断言。测试通过不能替代核对它的预期来源。

## 框架关联修复

FlipView 的宿主现在参与 NSControl 的 enabled 状态。禁用期间，键盘、滚轮与辅助功能翻页
无效，但绑定仍会更新选中项。重新启用时按当前边界状态恢复按钮，不恢复过期的页边界值。

`FluentDisabledContainer` 的处理分为整树快照、禁用和子节点优先恢复三个阶段。原因是组合
控件修改自身 enabled 时也会修改子控件；原先边快照边禁用会污染后续快照，父节点优先恢复
又会让过期子状态覆盖父控件算出的当前状态。弱键表追踪真实控件对象，避免过期 ObjectIdentifier
被新控件复用，并在禁用期间补记新挂载的控件。

辅助功能子节点只包含当前页和可见导航按钮，并提供增/减页动作。焦点跟随当前页迁移；
鼠标点击导航按钮会清除键盘焦点视觉，即使第一响应者仍是同一个宿主。按下状态在 NSButton
自己的鼠标跟踪循环返回后清除，因为该循环会消费 mouse-up。

## 验证范围

- 新增 7 项回归测试：边界显隐/三秒真实 timer、按钮悬停、滚轮连续事件/反向/空闲/父容器传递、RTL、禁用与恢复、禁用期间重建页面、极窄尺寸、辅助功能动作、键盘与合成鼠标跟踪。
- 完整测试、Release 门禁、原生验证程序、Xcode Gallery 构建的最终结果与源文件摘要见 `verification.json` 及对应日志。
- `run-visual.sh` 可重现浅色/深色/RTL 下 idle、pointer、last、keyboard、disabled、empty 共 18 张截图，并检查几何、显隐和选择值。
- 旧的受控 light/dark 基线比较见 `pixel-comparison.json`；该基线不包含 FlipView，也不是 Windows 对拍。

本次事件均由测试程序构造；没有把合成 wheel 或鼠标跟踪当成物理触控板、触摸拖拽和真实 VoiceOver
验收。FlipView 仍为 partial，剩余包括逐指针拖拽/吸附、虚拟化、纵向布局、完整 item-container
选择语义及字形/材质精确还原。嵌套 disabled 修饰器在外层禁用期间自身改值等组合仍需专项复核。
