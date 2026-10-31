# SwipeControl 实现（2026-10-31）

Gallery 目录中 SwipeControl 原为 **missing**，现新增公开 `FluentSwipeControl`，覆盖记为 **partial**。

## WinUI 参照

`src/controls/dev/SwipeControl/`：

- `SwipeControl.cpp`：`c_ThresholdValue = 100`；打开需超过 min(命令区尺寸 - 1, 100)，
  已打开时任何关闭方向的移动都会关闭（`UpdateThresholdReached`）；甩向另一侧直接关闭
  （`InertiaStateEntered`）；打开后同一手势中阻止另一侧内容（`blockNear/FarContent`）；
  Execute 模式停在打开状态时调用第一项（`IdleStateEntered`），之后按 `BehaviorOnInvoked`
  关闭或保持（`CloseIfNotRemainOpenExecuteItem`）；同时只有一个打开；点击其他位置关闭，
  内容上的按下被 `InputEater` 吞掉。
- `SwipeControl_themeresources.xaml`：命令按钮最小 68×40、内容边距 4,4,4,2、16pt 图标、12pt 文字；
  背景 ControlFillTertiary，按下 ControlAltFillQuarternary；Execute 过阈值前 ControlFillTertiary，
  过阈值后 AccentFillDefault + TextOnAccentPrimary。
- 不能同时有水平与垂直命令；本实现中水平优先。

## 实现

- 建立在共享输入基础层上（`FluentPanGestureDriver`）：macOS 27 触摸屏手指滑动、触控板双指滑动；
  和 WinUI 一样，鼠标拖动不触发滑动。
- 左/右（RTL 镜像）与上/下命令；Reveal 沿滑动方向堆叠，Execute 背景铺满已露出区域、命令留在露出边缘。
- 打开、回弹、甩动按速度投影判定；收尾动画与 Pivot 一致。
- 禁用的祖先控件阻止滑动；从窗口移除时直接关闭。
- VoiceOver：每个命令都暴露为内容上的自定义操作，无需滑动即可调用。
- Gallery 示例：三条消息，左侧 Execute 归档、右侧 Reveal 标记/删除。

## 验证（`run.sh`，结果在 `results/`）

- `swift test -Xswiftc -warnings-as-errors`：**200 项通过**，新增 `SwipeControlTests` 10 项、
  `InputFoundationTests` 4 项。
- 质量门禁、Gallery 挂载检查、原生验证、完整 Gallery 构建通过。
- [截图审计](results/visual.json)：用真实触控板事件，light/dark/RTL × 3 状态（Reveal 打开、
  Execute 阈值前/后）共 9 张；断言过阈值保持打开、按内容关闭、松手执行并关闭。全部人工查看。

## 局限

- 未在真实触摸屏上验证；Execute 停留打开时的指针按下颜色、垂直方向截图未覆盖。
- 自定义 IconSource 仅支持 SF Symbols 名称。
