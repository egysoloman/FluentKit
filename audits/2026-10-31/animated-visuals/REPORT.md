# AnimatedIcon 与 AnimatedVisualPlayer 实现（2026-10-31）

Gallery 目录中两者原为 **missing**，现新增公开 `FluentAnimatedIcon`、`FluentAnimatedVisualPlayer`、
`FluentAnimatedVisualSource` 协议与 5 个内置图标源，覆盖均记为 **partial**。

## WinUI 参照

- `AnimatedIcon/AnimatedIcon.cpp`：
  - `OnStatePropertyChanged`：同一轮中的多次状态变化合并为最后一次，在下一次布局时应用。
  - `TransitionStates` 查找顺序：`From`To`To`_Start/_End` 片段 → 仅 _End → 仅 _Start → `FromToTo` →
    以目标状态命名的标记 → 任意以 `To<目标>_End` 结尾的标记 → 数字状态（作为进度）→ 第 0 帧。
  - `PlaySegment`：线性、时长 = 源时长 × 片段长度 / 倍率；短于 20ms 或系统关闭动画时直接跳到终点。
  - 队列：QueueOne（默认）、Cut、SpeedUpQueueOne；队列长度 4，加速倍率 7。
- `AnimatedIcon/AnimatedVisuals/*.cpp`：Back、ChevronDownSmall、Settings、GlobalNavigationButton、Find 的
  标记时间线与时长（1.333s / 0.483s / 2.0s / 1.333s / 1.333s）——原样采用。
- `AnimatedVisualPlayer/AnimatedVisualPlayer.cpp`：AutoPlay 以循环方式播放 0…1；Stretch 默认 Uniform；
  PlayAsync(from, to, looped)、Pause、Resume、Stop、SetProgress、PlaybackRate；未加载源时显示 FallbackContent。

## 实现

- `FluentAnimatedVisualSource`/`FluentAnimatedVisual` 协议：时长、自然尺寸、标记、按进度渲染。
- `FluentAnimatedVisualPlayer` + `FluentAnimatedVisualPlayerController`（播放完成回调区分完成与取消）。
- `FluentAnimatedIcon`：状态驱动；未指定 `state` 时跟随自身的指针悬停/按下；无源时显示 SF Symbol 回退图标。
- 内置图标：使用 WinUI 的标记时间线与时长，图形与姿态是基于 SF Symbols 的 Core Animation 近似实现
  （原版为 Lottie 导出的合成代码）。

## 验证（结果在 `results/`）

- `swift test -Xswiftc -warnings-as-errors`：**229 项通过**，新增 `AnimatedVisualTests` 7 项。
- 质量门禁、Gallery 挂载检查、原生验证、完整 Gallery 构建通过。
- [截图审计](results/visual.json)：light/dark × Normal/PointerOver/Pressed，5 个内置图标 + 回退图标。
  截图检查发现按下时箭头方向错误（翻转坐标下多取了一次反），已修正并补充测试。

## 发现

- 实现过程中出现一次运行时崩溃（“weak reference … not in the weak references table”），原因是局部清理闭包
  同时捕获 `[weak self]` 与可变标志；改为按 WinUI 顺序直接更新状态后消失。

## 局限

- 不支持加载 Lottie JSON（需要完整渲染引擎）；只能用代码实现 `FluentAnimatedVisualSource`。
- 内置图标的形状与动作是近似，未与 Windows 逐帧对照；Accept、ChevronRightDownSmall、ChevronUpDownSmall 未提供。
- 没有接入 Button、NavigationView 等父控件的视觉状态（WinUI 中由父控件设置 AnimatedIcon.State）。
